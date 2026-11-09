---
name: write-rule
description: Write or improve a DeepYellow reclaim rule in rules/*.json from what the contributor knows (vendor documentation, research, or a lab measurement), pick the tier the evidence allows, run the checks and draft the pull request text. Use when someone wants to add a rule, fix a rule, or turn a lab compare result into a rule.
---

# Write a reclaim rule

A reclaim rule tells someone what a folder is and what happens if they remove it, and people delete files on the strength of it. Your job is to write a rule that says no more than the evidence supports. [rules/README.md](../../../rules/README.md) is the standard, so read it before you start, and follow the project CLAUDE.md throughout.

## Ground rules

- **Never delete, move or clean anything on this Mac to test a rule.** That includes running the rule's `cleanupCommand`. A measurement happens only in a lab VM (see `lab/`), never on the contributor's own machine.
- **Never invent facts.** No guessed versions, dates, sizes or behaviour. If something wasn't recorded, write "version not recorded" or leave the claim out.
- **Never read the contents of personal files.** Folder names and sizes the contributor gives you are fine. Nothing from their disk goes into a rule except a path pattern with every account-specific part replaced by `*`.
- **Don't commit or push** unless the contributor asks.

## Steps

### 1. Gather what the contributor knows

You need all of these, so ask one question at a time for whatever is missing:

- the app or tool, and its version
- the path, or where it appears
- what the folder holds
- what happens when it is removed: comes back on its own, comes back after a download or sign-in, breaks something, or unknown
- the evidence: a lab measurement (ask for the scrubbed `lab/compare.py` Markdown or JSON output), the vendor's documentation (ask for the link), or research (articles, issues, source code)

### 2. Look for rules that already cover it

Search `rules/*.json` for the app's name, its bundle ID and each distinctive path segment. Then decide:

- **An existing rule covers the same place**: improve it instead of adding one, and keep its `id`.
- **A broader rule also matches**: for example `**/node_modules` or `~/Library/Caches`. The most specific match wins, and a `never` ancestor beats everything beneath it. Note this down, because step 6 needs a test for it.
- **The folder holds a program**, such as an app's own modules inside Application Support. It needs a `never` rule even if nobody would think to delete it, so broad rules can't reach inside.

### 3. Pick the file

Put the rule in the file whose section fits, using the table in rules/README.md. Rules for one app's own folders go in `90-apps.json`, and package managers and build output go in `40-package-managers.json`.

### 4. Pick the tier

Walk the questions under "Choosing a tier" in rules/README.md in order, and stop at the first yes. Then cap the tier by the evidence:

| Evidence method | Highest tier allowed |
|---|---|
| `relaunch-test` (measured in a VM) | any |
| `vendor-doc` (the vendor's own documentation) | any |
| `research` | `review` (or `never`) |
| `location` (only where it sits) | `review` (or `never`) |

When the contributor's description and the evidence disagree, go with the evidence. When anything is uncertain, choose `review`. Tell the contributor which tier you chose and why, in one or two sentences.

### 5. Write the entry

Use the field table in rules/README.md, with these habits:

- `id`: lowercase and dotted, starting with the app or tool (`zoom.components`).
- `title`: short, no trailing period.
- `whatItIs` and `consequence`: one plain sentence each, ending with a period. Be concrete: "You will be signed out of Zoom" beats "Some data may be lost". Put numbers in when they were measured.
- `pattern`: anchored (`~/Library/...`) when possible. A floating `**/name` pattern needs an `if-sibling:` guard. Replace user names, account IDs, team IDs and profile names with `*`.
- `sideCondition`: what to do first ("Quit Slack first."), or `null`.
- `cleanupCommand`: only the tool's own documented command, or `null`. It is shown and never run.
- `source`: one line, such as "Measured: removed and relaunched Slack 4.53 on macOS 15.7" or the vendor's page title.
- `evidence`: the method, plus for `relaunch-test` the `appVersion`, `macOSVersion`, `measuredOn` (YYYY-MM-DD) and an `observed` sentence on what happened. If the measurement showed that removing the folder freed far less than its size (APFS clones or hard links), say so in `observed` and in `consequence`.

Keep the key order of the neighbouring rules and the file's 2-space indentation.

### 6. Add a precedence test when it matters

If step 2 found a broader rule or a `never` ancestor, add a test to `Packages/DYAdvisor/Tests/DYAdvisorTests/RuleFilesTests.swift` that proves the right rule wins for a path inside the folder. Copy the shape of `testDiscordModulesProtectWhatTheyBundle`, and use a made-up home folder such as `/Users/tester`.

### 7. Run the checks

```sh
python3 scripts/check-rules.py
python3 scripts/gen-rules-doc.py
swift test --package-path Packages/DYAdvisor
```

Fix every failure in the rule, never in the checker. If `check-rules.py` reports a privacy problem, replace the flagged part with `*`, or reword the sentence so it doesn't need it.

### 8. Draft the pull request

Give the contributor a title and a short body to paste. The body should say:

- the app or tool and version, and the folder
- the tier, and the evidence that allows it
- what was observed, with numbers
- any precedence test you added

Keep one app or tool per pull request.
