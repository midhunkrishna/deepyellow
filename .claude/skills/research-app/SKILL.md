---
name: research-app
description: Research, without a VM, where one Mac app stores its data, using only vendor documentation and public sources, and produce a short Markdown report that feeds the write-rule skill. Use when someone picks up an "App rule: <App>" issue, or wants to know which folders an app keeps and what removing each one does.
---

# Research where an app keeps its data

This skill produces a report, not a rule. The report lists an app's folders, what each one holds, what removing it does, and a source for every claim. The `write-rule` skill then turns the report into entries in `rules/90-apps.json`. People delete files on the strength of those entries, so the report says no more than its sources do.

Other agents (not only Claude Code) can use this: point the agent at this file and tell it to follow it.

## Ground rules

- **Never read the contributor's own files to find paths.** Don't list, open or measure the app's folders on this Mac. Work from public sources only.
- **Never delete, move or clean anything**, and never run an app's cleanup command.
- **Never invent facts.** Every path in the report carries a source link. If nothing was found for a location, write "nothing found" for it. Don't guess a path from the app's name.
- **Never paste real file names, user names, account IDs or team IDs.** Replace each account-specific part of a path with `*`.
- **Don't commit or push** unless the contributor asks.

## Steps

### 1. Get the inputs

You need the app's name. The Homebrew cask token (`brew info --cask` shows it, or look it up on formulae.brew.sh) and the bundle ID help if the contributor has them. An issue titled "App rule: <App>" often has them. Ask one question at a time for whatever is missing, and don't read the app's `Info.plist` from the contributor's disk to find the bundle ID. Find it in public sources instead, such as the cask file or the vendor's documentation.

### 2. Check what the repo already says

Search `rules/*.json` for the app's name and bundle ID. If rules already exist, note which folders they cover, and put only new or disputed folders in the report. See `rules/90-apps.json` for what finished entries look like.

### 3. Read public sources

Look in this order and stop looking for a folder once you have a source for it.

1. **The vendor's support and help pages.** Search for "clear cache", "reset", "uninstall", "where are logs stored" and "troubleshooting" on the vendor's site.
2. **The app's open-source repository**, if it has one. Search the code for the folder names it creates.
3. **The Homebrew cask `zap` stanza** in https://github.com/Homebrew/homebrew-cask (`Casks/<first letter>/<token>.rb`). It lists the folders the app creates. It says where things are, not what removing them does, so it is evidence of location only.
4. **Uninstall guides, forum threads and issue trackers.** Weakest, but good for "what happened when someone removed it".

The standard locations to consider are:

- `~/Library/Application Support`
- `~/Library/Caches`
- `~/Library/Containers` and `~/Library/Group Containers`
- `~/Library/Logs`
- `~/Library/Preferences`
- `~/Library/Saved Application State`
- `~/Library/HTTPStorages`
- `~/Library/WebKit`
- dot folders in the home folder, such as `~/.appname`

For each one, record the path if a source names it, and "nothing found" if none does.

### 4. Choose the evidence method and the proposed tier

Use the vendor's own words where they exist.

| Evidence method | Use it when | Highest tier allowed |
|---|---|---|
| `vendor-doc` | the vendor's documentation says what the folder is and that it can be removed | any |
| `research` | articles, forum posts, issues, source code or the cask `zap` list | `review` or `never` |

The cap is firm. A `safe` or `rebuild` proposal without a vendor document needs a lab `relaunch-test` first. Don't propose it from research. Put it under open questions, and see `docs/lab-guide.md` and the `measure-app` skill for how to run the measurement.

For the tier itself, walk the questions under "Choosing a tier" in `rules/README.md`. Anything that could hold messages, projects, purchases or sign-in data is `review`, and a folder that holds the app's own programs or modules is `never`. When unsure, propose `review`.

### 5. Write the report

Use exactly this shape.

```markdown
# App research: <App>

- App: <name>
- Version or date researched: <version if the sources name one, otherwise the date you researched it>
- Bundle ID: <id, with a source link, or "not found">

| Path pattern | What it holds | What removing it does | Rebuilt by the app? | Source | Evidence method | Proposed tier |
|---|---|---|---|---|---|---|
| `~/Library/Application Support/<App>/Cache` | ... | ... | yes / no / unknown | <link> | vendor-doc | rebuild |

## Open questions

- <a question a lab measurement would settle, for example "Does the app sign out after this folder is removed?">
```

Rules for the table:

- One row per folder. A path with no source link does not get a row.
- `Path pattern` uses `~` and `*` for every account-specific part.
- `What it holds` and `What removing it does` are one plain sentence each, taken from the source. If the source doesn't say what removal does, write "not stated" and propose `review`.
- `Rebuilt by the app?` is `unknown` unless a source says so.
- Never write a size, a version or a time you didn't read in a source.

### 6. Hand it over

Give the contributor the report to paste as a comment on the issue and into the pull request body. Then hand the report to the `write-rule` skill, which writes the entries and the pull request text. Finally run:

```sh
make check-rules
```

It runs `scripts/check-rules.py`, `scripts/gen-rules-doc.py --check` and `swift test --package-path Packages/DYAdvisor`. Fix every failure in the rule, never in the checker.
