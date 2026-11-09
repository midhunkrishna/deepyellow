#!/usr/bin/env python3
"""Tests for scripts/check-rules.py, run against fixture rule files in a temp folder."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("chk", HERE / "check-rules.py")
chk = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(chk)


def good_rule(rid="a.b", **extra):
    """Build a fixture rule that passes every check."""
    base = {"id": rid, "title": "Title", "pattern": "~/x/y", "tier": "review", "whatItIs": "It.",
            "consequence": "Cost.", "sideCondition": None, "cleanupCommand": None,
            "ownerBundleIDs": [], "source": None, "evidence": {"method": "location"}}
    base.update(extra)
    return base


def good_doc(*rules):
    """Build a fixture rule file holding the given rules."""
    return {"version": 1, "section": {"title": "T", "intro": "I."}, "rules": list(rules) or [good_rule()]}


class CheckTests(unittest.TestCase):
    """One focused test per check."""

    def setUp(self):
        """Create a temp rules folder."""
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        """Remove the temp folder."""
        self.tmp.cleanup()

    def write(self, name, doc):
        """Write a fixture file, as JSON unless doc is a string."""
        text = doc if isinstance(doc, str) else json.dumps(doc)
        (self.dir / name).write_text(text, encoding="utf-8")

    def problems(self, doc=None, name="10-x.json"):
        """Write one file and return all problem lines."""
        self.write(name, doc if doc is not None else good_doc())
        return chk.check_directory(self.dir)[0]

    def rule_problems(self, **extra):
        """Return the problem lines for a single rule with overrides."""
        return self.problems(good_doc(good_rule(**extra)))

    def assertHas(self, lines, text):
        """Assert some problem line contains the text."""
        self.assertTrue(any(text in l for l in lines), f"{text!r} not in {lines}")

    def test_good_fixture_passes(self):
        """The baseline fixture has no problems and the summary counts it."""
        self.write("10-x.json", good_doc())
        self.assertEqual(chk.check_directory(self.dir), ([], 1, 1))

    def test_file_name(self):
        """A file name without the two-digit prefix is reported."""
        self.assertHas(self.problems(name="caches.json"), "file name")

    def test_invalid_json(self):
        """Broken JSON is reported with the file name."""
        self.assertHas(self.problems("{nope"), "not valid JSON")

    def test_version_and_section(self):
        """Wrong version and empty section text are reported."""
        doc = good_doc()
        doc["version"] = 2
        doc["section"]["title"] = " "
        lines = self.problems(doc)
        self.assertHas(lines, "version must be 1")
        self.assertHas(lines, "section.title")

    def test_unknown_keys(self):
        """Unknown top-level and rule keys are reported, but $schema is allowed."""
        doc = good_doc(good_rule(extra="x"))
        doc["other"] = 1
        doc["$schema"] = "./schema/rules.schema.json"
        lines = self.problems(doc)
        self.assertHas(lines, "unknown top-level key 'other'")
        self.assertHas(lines, "unknown key 'extra'")
        self.assertFalse(any("$schema" in l for l in lines))

    def test_required_strings(self):
        """Empty required strings and blank nullable strings are reported."""
        lines = self.rule_problems(title="", whatItIs=" ", sideCondition="  ", source="")
        for key in ("title", "whatItIs", "sideCondition", "source"):
            self.assertHas(lines, key)

    def test_owner_bundle_ids(self):
        """Owner IDs must be reverse-DNS strings."""
        self.assertHas(self.rule_problems(ownerBundleIDs=["notdns", ""]), "ownerBundleIDs entry")
        self.assertEqual(self.rule_problems(ownerBundleIDs=["com.example.App"]), [])

    def test_id_format_and_uniqueness(self):
        """Uppercase ids and ids repeated across files are reported."""
        self.assertHas(self.rule_problems(id="Bad.Id"), "id must be")
        self.write("10-a.json", good_doc(good_rule("dup.one")))
        self.write("20-b.json", good_doc(good_rule("dup.one")))
        self.assertHas(chk.check_directory(self.dir)[0], "duplicate id")

    def test_enums_and_relaunch_fields(self):
        """Unknown tier and method are reported; relaunch-test needs four fields."""
        self.assertHas(self.rule_problems(tier="maybe"), "unknown tier")
        self.assertHas(self.rule_problems(evidence={"method": "guess"}), "unknown evidence.method")
        lines = self.rule_problems(evidence={"method": "relaunch-test"})
        for field in chk.MEASURED_FIELDS:
            self.assertHas(lines, f"evidence.{field}")

    def test_measured_on_date(self):
        """measuredOn must be a real date in YYYY-MM-DD form, and not in the future."""
        ev = lambda d: {"method": "location", "measuredOn": d}
        self.assertHas(self.rule_problems(evidence=ev("2026-02-30")), "measuredOn")
        self.assertHas(self.rule_problems(evidence=ev("5/1/2026")), "measuredOn")
        self.assertHas(self.rule_problems(evidence=ev("2999-01-01")), "in the future")
        self.assertEqual(self.rule_problems(evidence=ev("2026-01-31")), [])

    def test_tier_vs_evidence(self):
        """Safe and rebuild need strong evidence and a source; location never qualifies."""
        strong = {"method": "vendor-doc"}
        self.assertEqual(self.rule_problems(tier="safe", evidence=strong, source="Vendor page"), [])
        self.assertHas(self.rule_problems(tier="safe", evidence=strong), "need a source")
        self.assertHas(self.rule_problems(tier="rebuild", evidence={"method": "location"}, source="s"), "location")
        self.assertHas(self.rule_problems(tier="safe", evidence={"method": "research"}, source="s"), "research")

    def test_legacy_set_allows_listed_rule(self):
        """A listed rebuild rule with research evidence is accepted."""
        rid = sorted(chk.LEGACY_UNVERIFIED)[0]
        self.assertEqual(self.rule_problems(id=rid, tier="rebuild", evidence={"method": "research"}, source="s"), [])

    def test_legacy_set_is_pruned(self):
        """Listed ids that are missing or have moved on are reported."""
        rid = sorted(chk.LEGACY_UNVERIFIED)[0]
        self.assertEqual(len(chk.check_legacy_set({})), len(chk.LEGACY_UNVERIFIED))
        moved = {rid: good_rule(rid, tier="rebuild", evidence={"method": "vendor-doc"})}
        found = dict(chk.check_legacy_set(moved))
        self.assertIn("no longer rebuild", found[rid])

    def test_pattern_syntax(self):
        """Bad anchors, empty paths and a trailing ** are reported per part."""
        for bad in ("x/y", "~", "**/", "~/a/**", "~/ok || y/z"):
            self.assertHas(self.rule_problems(pattern=bad), "pattern part")
        for good in ("~/a/*", "/Library/x", "**/node_modules if-sibling:package.json", "~/a || /b/c"):
            self.assertEqual(self.rule_problems(pattern=good), [], good)

    def test_privacy(self):
        """Real user names, emails and long numbers are reported; * is fine."""
        self.assertHas(self.rule_problems(whatItIs="Lives in /Users/alice/Library."), "user name")
        self.assertEqual(self.rule_problems(whatItIs="Lives in /Users/*/Library."), [])
        self.assertHas(self.rule_problems(consequence="Mail bob@example.com."), "email")
        self.assertHas(self.rule_problems(source="id 123456789"), "account ID")
        self.assertHas(self.rule_problems(source="hash deadbeefcafe0"), "account ID")
        self.assertEqual(self.rule_problems(ownerBundleIDs=["com.example.123456789012"]), [])
        self.assertEqual(self.rule_problems(source="took 12345678 bytes"), [])

    def test_copy(self):
        """Missing full stops and a trailing period on the title are reported."""
        lines = self.rule_problems(whatItIs="No stop", consequence="No stop", title="Ends.")
        self.assertEqual(len(lines), 3)

    def test_real_rules_pass(self):
        """The repo's own rule files pass, including the legacy set pruning."""
        lines, count, files = chk.check_directory(chk.RULES_DIR)
        self.assertEqual(lines, [])
        self.assertGreater(count, 0)

    def test_schema_enums_match(self):
        """The schema's tier and method enums equal the checker's constants."""
        schema = json.loads((chk.ROOT / "rules" / "schema" / "rules.schema.json").read_text(encoding="utf-8"))
        props = schema["$defs"]["rule"]["properties"]
        self.assertEqual(tuple(props["tier"]["enum"]), chk.TIERS)
        self.assertEqual(tuple(schema["$defs"]["evidence"]["properties"]["method"]["enum"]), chk.METHODS)
        self.assertEqual(set(props), chk.RULE_KEYS)
        self.assertEqual(set(schema["properties"]), chk.TOP_KEYS)


if __name__ == "__main__":
    unittest.main()
