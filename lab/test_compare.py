"""Tests for lab/compare.py, written against the snapshot-compare contract."""

import json
import os
import tempfile
import unittest

import compare

HEADER = "path,is_dir,size,logical,file_count,modified,safety"
MB = 1_000_000


def read(path):
    """Return a file's text, closing the file."""
    with open(path) as handle:
        return handle.read()


def write(path, text):
    """Write text to a file, closing the file."""
    with open(path, "w") as handle:
        handle.write(text)


def snap(rows):
    """Build snapshot CSV text from (path, size, files, safety) directory tuples."""
    lines = [HEADER]
    for path, size, files, *rest in rows:
        safety = rest[0] if rest else ""
        lines.append(f'"{path}",1,{size},{size},{files},0,{safety}')
    return "\n".join(lines) + "\n"


def load(rows):
    """Parse directory tuples into a snapshot dict through the public loader."""
    return compare.parse_snapshot(snap(rows).splitlines())


def compute(before, after, **kw):
    """Run the analysis on two row lists and return the result dict (scrubbed)."""
    kw.setdefault("home", "/Users/admin")
    return compare.analyze(load(before), load(after), **kw)


def patterns(rows):
    """Return the pattern list of a row list."""
    return [r["pattern"] for r in rows]


class DeltaTests(unittest.TestCase):
    def test_parse_requires_header(self):
        with self.assertRaises(ValueError):
            compare.parse_snapshot(["a,b,c", "x,y,z"])

    def test_parse_skips_files(self):
        text = HEADER + "\n/a,1,10,10,1,0,\n/a/f,0,10,10,1,0,\n"
        snapshot = compare.parse_snapshot(text.splitlines())
        self.assertEqual(list(snapshot), ["/a"])

    def test_concentrated_growth_recurses(self):
        before = [("/Users/admin", 10 * MB, 10), ("/Users/admin/L", 10 * MB, 10),
                  ("/Users/admin/L/A", 5 * MB, 5), ("/Users/admin/L/B", 5 * MB, 5)]
        after = [("/Users/admin", 60 * MB, 60), ("/Users/admin/L", 60 * MB, 60),
                 ("/Users/admin/L/A", 55 * MB, 55), ("/Users/admin/L/B", 5 * MB, 5)]
        res = compute(before, after)
        self.assertEqual(patterns(res["growth"]), ["~/L/A"])
        self.assertEqual(res["growth"][0]["bytesAdded"], 50 * MB)
        self.assertEqual(res["growth"][0]["filesAdded"], 50)
        self.assertEqual(res["totals"]["bytesAdded"], 50 * MB)

    def test_spread_growth_reports_parent(self):
        before = [("/R", 0, 0)] + [(f"/R/c{i}", 0, 0) for i in range(10)]
        after = [("/R", 10 * MB, 10)] + [(f"/R/c{i}", MB // 10, 1) for i in range(10)]
        res = compute(before, after, min_bytes=MB)
        self.assertEqual(patterns(res["growth"]), ["/R"])

    def test_below_min_bytes_nothing(self):
        res = compute([("/R", 0, 0)], [("/R", MB - 1, 1)], min_bytes=MB)
        self.assertEqual(res["growth"], [])

    def test_eighty_percent_threshold(self):
        # child explains 79% -> report the folder itself
        before = [("/R", 0, 0), ("/R/a", 0, 0)]
        after = [("/R", 100 * MB, 1), ("/R/a", 79 * MB, 1)]
        self.assertEqual(patterns(compute(before, after)["growth"]), ["/R"])
        after = [("/R", 100 * MB, 1), ("/R/a", 80 * MB, 1)]
        self.assertEqual(patterns(compute(before, after)["growth"]), ["/R/a"])

    def test_missing_before_counts_zero_and_is_new(self):
        res = compute([("/R", 0, 0)], [("/R", 5 * MB, 5), ("/R/n", 5 * MB, 5)])
        self.assertEqual(patterns(res["newFolders"]), ["/R/n"])
        self.assertTrue(res["newFolders"][0]["isNew"])
        self.assertEqual(res["growth"][0]["pattern"], "/R/n")
        self.assertTrue(res["growth"][0]["isNew"])

    def test_new_folders_only_top_of_subtree_any_size(self):
        res = compute([("/R", 0, 0)],
                      [("/R", 10, 1), ("/R/n", 10, 1), ("/R/n/deep", 10, 1)])
        self.assertEqual(patterns(res["newFolders"]), ["/R/n"])
        self.assertEqual(res["growth"], [])

    def test_shrank(self):
        before = [("/R", 50 * MB, 5), ("/R/a", 50 * MB, 5)]
        after = [("/R", 0, 0), ("/R/a", 0, 0)]
        res = compute(before, after)
        self.assertEqual(patterns(res["shrank"]), ["/R/a"])
        self.assertEqual(res["shrank"][0]["bytesAdded"], -50 * MB)
        self.assertEqual(res["growth"], [])

    def test_sorted_descending_and_size_after(self):
        before = [("/R", 0, 0), ("/R/a", 0, 0), ("/R/b", 0, 0)]
        after = [("/R", 30 * MB, 3), ("/R/a", 10 * MB, 1), ("/R/b", 20 * MB, 2)]
        res = compute(before, after)
        self.assertEqual(patterns(res["growth"]), ["/R/b", "/R/a"])
        self.assertEqual(res["growth"][0]["sizeAfter"], 20 * MB)


class NoiseAndAttributionTests(unittest.TestCase):
    def test_noise_marked_not_dropped(self):
        before = [("/R", 0, 0), ("/R/a", 0, 0), ("/R/b", 0, 0)]
        after = [("/R", 20 * MB, 2), ("/R/a", 10 * MB, 1), ("/R/b", 10 * MB, 1)]
        n0 = load([("/R", 0, 0), ("/R/a", 0, 0)])
        n1 = load([("/R", 5, 0), ("/R/a", 5, 0), ("/R/c", 1, 0)])
        res = compute(before, after, noise=(n0, n1))
        by = {r["pattern"]: r for r in res["growth"]}
        self.assertTrue(by["/R/a"]["noise"])
        self.assertFalse(by["/R/b"]["noise"])

    def test_noise_for_appeared_path(self):
        n0 = load([("/R", 0, 0)])
        n1 = load([("/R", 0, 0), ("/R/x", 1, 0)])
        self.assertIn("/R/x", compare.noise_paths(n0, n1))
        self.assertNotIn("/R", compare.noise_paths(n0, n1))

    def test_attributed_case_insensitive_and_total(self):
        before = [("/R", 0, 0), ("/R/Slack", 0, 0), ("/R/other", 0, 0)]
        after = [("/R", 30 * MB, 3), ("/R/Slack", 10 * MB, 1), ("/R/other", 20 * MB, 2)]
        res = compute(before, after, app_tokens=["slack"])
        by = {r["pattern"]: r for r in res["growth"]}
        self.assertTrue(by["/R/Slack"]["attributed"])
        self.assertFalse(by["/R/other"]["attributed"])
        self.assertEqual(res["totals"]["attributedBytesAdded"], 10 * MB)
        self.assertEqual(res["totals"]["bytesAdded"], 30 * MB)


class ScrubTests(unittest.TestCase):
    def test_home_and_ordinary_names_survive(self):
        for name in ["Cache", "Code Cache", "GPUCache", "Application Support",
                     "com.tinyspeck.slackmacgap", "TEMPLATES", "Service Worker"]:
            out = compare.scrub_path(f"/Users/admin/Library/{name}", "/Users/admin", [])
            self.assertEqual(out, f"~/Library/{name}")

    def test_individual_rules(self):
        s = lambda p, redact=(): compare.scrub_path(p, "/Users/admin", list(redact))
        uuid = "123e4567-e89b-12d3-a456-426614174000"
        self.assertEqual(s(f"/L/{uuid}/x"), "/L/*/x")
        self.assertEqual(s("/L/a@b.com/x"), "/L/*/x")
        self.assertEqual(s("/L/id-1234567/x"), "/L/id-*/x")
        self.assertEqual(s("/L/ab12cd34ef56ab78cd90/x"), "/L/*/x")
        self.assertEqual(s("/L/storage.T01AB2CD3EF.dat"), "/L/storage.*.dat")
        self.assertEqual(s("/L/Abcdefghij1234567890Klmn/x"), "/L/*/x")
        self.assertEqual(s("/L/abcdefghijklmnopqrstuvwxyz/x"), "/L/abcdefghijklmnopqrstuvwxyz/x")
        self.assertEqual(s("/L/Jane Doe's thing/x", ["jane doe"]), "/L/*'s thing/x")
        self.assertEqual(s("/var/folders/9m/abc_random/T/x"), "/var/folders/*/*/T/x")
        self.assertEqual(s("/private/var/folders/xy/abc123_random/C/com.x"),
                         "/private/var/folders/*/*/C/com.x")

    def test_privacy_nothing_leaks_and_rows_merge(self):
        uuid = "123e4567-e89b-12d3-a456-426614174000"
        paths = [
            "/Users/admin/Library/Application Support/Slack/" + uuid,
            "/Users/admin/Library/Application Support/Slack/jane.doe@corp.com",
            "/Users/admin/Library/Application Support/Slack/T01AB2CD3EF",
            "/Users/admin/Library/Application Support/Slack/Zk3Jd9Qp2Lm8Xv4Bn7Rt5Yh1",
            "/Users/admin/Library/Application Support/Slack/order1234567",
            "/Users/admin/Library/Application Support/Slack/zebra-secret-name",
            "/private/var/folders/xy/abc123_random/C/com.tinyspeck.slackmacgap",
            "/var/folders/9m/abc_random/T/x",
        ]
        before, after = [], []
        for p in paths:
            before.append((p, 0, 0))
            after.append((p, 10 * MB, 1))
        res = compute(before, after, redact=["Zebra-Secret-Name"], min_bytes=MB)
        with tempfile.TemporaryDirectory() as d:
            js, md = os.path.join(d, "o.json"), os.path.join(d, "o.md")
            compare.write_outputs(res, js, md)
            text = read(js) + read(md)
        for piece in ["admin", "jane", "corp.com", uuid, "T01AB2CD3EF",
                      "Zk3Jd9Qp2Lm8Xv4Bn7Rt5Yh1", "1234567", "zebra",
                      "xy/", "abc123_random", "9m", "abc_random"]:
            self.assertNotIn(piece.lower(), text.lower(), piece)
        self.assertIn("com.tinyspeck.slackmacgap", text)
        # uuid, email, slack id, token, digits, redact rows all merge to one pattern
        self.assertEqual(patterns(res["growth"]).count(
            "~/Library/Application Support/Slack/*"), 1)
        row = [r for r in res["growth"]
               if r["pattern"] == "~/Library/Application Support/Slack/*"][0]
        self.assertEqual(row["bytesAdded"], 50 * MB)
        self.assertEqual(row["filesAdded"], 5)

    def test_raw_json_is_unscrubbed(self):
        before = [("/Users/admin", 0, 0), ("/Users/admin/x", 0, 0)]
        after = [("/Users/admin", 5 * MB, 1), ("/Users/admin/x", 5 * MB, 1)]
        res = compute(before, after, raw=True)
        self.assertEqual(patterns(res["growth"]), ["/Users/admin/x"])


class AccountFolderTests(unittest.TestCase):
    def test_folder_inside_users_or_accounts_is_masked(self):
        s = lambda p: compare.scrub_path(p, "/Users/admin", [])
        self.assertEqual(s("/Users/admin/Library/Application Support/Spotify/PersistentCache/Users/jane.doe-user/primary.ldb"),
                         "~/Library/Application Support/Spotify/PersistentCache/Users/*/primary.ldb")
        self.assertEqual(s("/Users/admin/Library/Foo/Accounts/janedoe/cache"), "~/Library/Foo/Accounts/*/cache")
        self.assertEqual(s("/Users/other/Documents"), "/Users/*/Documents")


class OutputTests(unittest.TestCase):
    def test_format_size(self):
        self.assertEqual(compare.format_size(12_300_000), "12.3 MB")
        self.assertEqual(compare.format_size(999), "999 B")
        self.assertEqual(compare.format_size(1_500_000_000), "1.5 GB")

    def test_cli_end_to_end(self):
        with tempfile.TemporaryDirectory() as d:
            p = lambda n: os.path.join(d, n)
            write(p("b.csv"), snap([("/Users/admin", 0, 0), ("/Users/admin/App", 0, 0)]))
            write(p("a.csv"), snap([("/Users/admin", 12_300_000, 4),
                                              ("/Users/admin/App", 12_300_000, 4)]))
            code = compare.main([p("b.csv"), p("a.csv"), "--home", "/Users/admin",
                                 "--app-token", "app", "--json", p("o.json"),
                                 "--md", p("o.md"), "--raw-json", p("r.json")])
            self.assertEqual(code, 0)
            out = json.loads(read(p("o.json")))
            self.assertEqual(set(out), {"totals", "growth", "newFolders", "shrank"})
            self.assertEqual(set(out["growth"][0]), {
                "pattern", "bytesAdded", "filesAdded", "sizeAfter", "isNew",
                "attributed", "noise", "safety"})
            self.assertEqual(out["growth"][0]["pattern"], "~/App")
            self.assertIn("12.3 MB", read(p("o.md")))
            self.assertEqual(json.loads(read(p("r.json")))["growth"][0]["pattern"],
                             "/Users/admin/App")


if __name__ == "__main__":
    unittest.main()
