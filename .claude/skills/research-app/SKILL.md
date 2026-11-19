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

Search `rules/*.json` for the app's name and bundle ID. If rules already exist, note which folders they cover, and put only new or disputed folders in the report. If no rule mentions the app, report every row. See `rules/90-apps.json` for what finished entries look like.

### 3. Read public sources

Use web search and web fetch. Start with the cask `zap` stanza, because it is the list of paths. It is only a starting list: for each path, keep looking for what it holds and what removing it does. Look in this order and stop looking for a path once you have a source for what it holds and what removal does.

1. **The Homebrew cask `zap` stanza.** Fetch the raw file at `https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/<first letter>/<token>.rb`. It lists the folders and files the app creates. A token with slashes (`user/tap/name`) is a tapped cask, and its file lives in that tap's own repository, not in homebrew-cask. The `zap` list says where things are, not what removing them does.
2. **The vendor's support and help pages.** Search for "clear cache", "reset", "uninstall", "where are logs stored" and "troubleshooting" on the vendor's site.
3. **The app's open-source repository and issue tracker**, if it has one. Search the code for the folder names it creates.
4. **Uninstall guides and forum threads.** Weakest, but good for "what happened when someone removed it".
5. **General macOS knowledge** for the standard locations, using the table below.

Stop rule: about 15 fetches per app. For a large documentation page, fetch the specific page or search within it instead of loading everything.

The standard locations to consider are `~/Library/Application Support`, `Caches`, `Containers`, `Group Containers`, `Logs`, `Preferences`, `Saved Application State`, `HTTPStorages` and `WebKit`, plus dot folders in the home folder such as `~/.appname`. Record a path only if a source names it. For a location no source names, write "nothing found".

A `zap` entry that is a single file (a Preferences plist, a config file) gets a row too.

What the standard locations mean by default. This is macOS convention, not app-specific, and it can fill a row when the app's own sources are silent. Say so in the Source column ("macOS convention").

| Location | Convention |
|---|---|
| `~/Library/Caches/<id>` | Data the app can fetch or compute again. It is slower until it refills. |
| `~/Library/HTTPStorages/<id>` | Network session data such as cookies for the app's own requests. Removing it can sign the user out. |
| `~/Library/WebKit/<id>` | Web view storage: caches, cookies, local storage. Removing it can sign the user out of anything shown in a web view. |
| `~/Library/Saved Application State/<id>.savedState` | Window positions and open documents from last quit. Removing it loses that layout only. |
| `~/Library/Preferences/<id>.plist` | The app's settings. Removing it resets them. |
| `~/Library/Logs/<App>` | Text logs for troubleshooting. Removing them loses the history only. |

### 4. Choose the evidence method and the proposed tier

Use the vendor's own words where they exist. These are the four methods in `rules/README.md`.

| Evidence method | What it means | Highest tier allowed |
|---|---|---|
| `relaunch-test` | Removed in a clean macOS VM, the app relaunched, the result observed | any |
| `vendor-doc` | The vendor's own documentation says what the folder is and that it can be removed | any |
| `research` | Articles, forum posts, issue trackers or reading the source | `review`, `never` |
| `location` | Only where it sits, such as a folder inside an app's container | `review`, `never` |

This skill reports `vendor-doc`, `research` or `location`. Only a lab measurement gives `relaunch-test`.

A vendor page that documents only where a folder is does not count as `vendor-doc`. Use `research`, or `location` when the only evidence is where it sits (a `zap` entry, a container path). `vendor-doc` needs the vendor saying what the folder is and that removing it is fine, or what it costs.

The cap is firm. A `safe` or `rebuild` proposal without a vendor document needs a lab `relaunch-test` first. Don't propose it from research. Put it under open questions, and see `docs/lab-guide.md` and the `measure-app` skill for how to run the measurement.

For the tier itself, walk the questions under "Choosing a tier" in `rules/README.md`. Anything that could hold messages, projects, purchases or sign-in data is `review`, and a folder that holds the app's own programs or modules is `never`. User config and preferences are normally `never` or `review`, never proposed as reclaimable space. When unsure, propose `review`.

### 5. Write the report

Use exactly this shape.

```markdown
# App research: <App>

- App: <name>
- Version or date researched: <version if a source names it, otherwise "version unknown, researched <date>">
- Bundle ID: <id, with a source link, or "not found">

| Path pattern | What it holds | What removing it does | Rebuilt by the app? | Source | Evidence method | Proposed tier |
|---|---|---|---|---|---|---|
| `~/Library/Application Support/ExampleApp/Cache` | Pages and images ExampleApp downloaded to show again. | ExampleApp downloads them again as you browse, and you stay signed in. | yes | <link to the vendor's "Clear cache" page> | vendor-doc | rebuild |
| `~/Library/Application Support/ExampleApp/Sessions` | Not stated. | Not stated. | unknown | <link to the cask zap list> | location | review |

## Open questions

- <a question a lab measurement would settle, for example "Does the app sign out after this folder is removed?">
```

Get the date from `date +%F`, not from memory.

Rules for the table:

- One row per folder or file. A path with no source link does not get a row.
- `Path pattern` uses `~` and `*` for every account-specific part.
- `What it holds` and `What removing it does` are one plain sentence each, taken from the source or from the convention table. If neither says, write "Not stated" and propose `review`.
- `Rebuilt by the app?` is `unknown` unless a source says so.
- Never write a size, a version or a time you didn't read in a source.

### 6. Hand it over

Give the contributor the report to paste as a comment on the issue and into the pull request body. If you can't reach the issue, print the report for the contributor to paste. Then hand the report to the `write-rule` skill (`.claude/skills/write-rule/SKILL.md`), which writes the entries and the pull request text. Finally run:

```sh
make check-rules
```

It runs `scripts/check-rules.py`, `scripts/gen-rules-doc.py --check` and `swift test --package-path Packages/DYAdvisor`. Fix every failure in the rule, never in the checker.
