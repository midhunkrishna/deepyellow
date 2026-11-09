# Writing reclaim rules

Every piece of safety advice DeepYellow gives comes from the JSON files in this folder. The app reads them when it starts, and [docs/reclaim-rules.md](../docs/reclaim-rules.md) is generated from the same files, so a rule you add here shows up in both places. This page is for people who want to add a rule or improve one.

A rule tells someone what a folder is and what happens if they remove it. People will act on that sentence, so a rule is only as good as the evidence behind it. Most of this page is about that evidence.

## The files

Each file is one section of the rules page, and the number in its name sets the order.

| File | What goes in it |
|---|---|
| `10-caches.json` | `~/Library/Caches` and its exceptions |
| `20-developer.json` | Xcode, simulators and the toolchain |
| `30-system.json` | Virtual machines, backups and parts of macOS that are shown but not offered |
| `40-package-managers.json` | Language caches, dependencies and build folders |
| `50-personal.json` | Logs, the Trash, installers, and data that belongs to you |
| `90-apps.json` | One app's folders, measured in the [lab](../lab/) |

`schema/rules.schema.json` describes the format. Editors such as VS Code read it through the `$schema` line at the top of each file, so they show what each field means and flag a missing one as you type.

## Anatomy of a rule

Let's look at a real one.

```json
{
  "id": "slack.cache",
  "title": "Slack's web cache",
  "pattern": "~/Library/Application Support/Slack/Cache",
  "tier": "rebuild",
  "whatItIs": "Images, files and pages Slack downloaded so it can show them again without fetching them.",
  "consequence": "Slack downloads them again as you open them, and you stay signed in.",
  "sideCondition": "Quit Slack first.",
  "cleanupCommand": null,
  "ownerBundleIDs": [
    "com.tinyspeck.slackmacgap"
  ],
  "source": "Measured: removed and relaunched Slack 4.53 on macOS 15.7",
  "evidence": {
    "method": "relaunch-test",
    "appVersion": "4.53.280",
    "macOSVersion": "15.7.7",
    "measuredOn": "2026-11-08",
    "observed": "Reached 55 MB after about 2 hours of use and grew by about 1 MB a minute while reading channels. After removal Slack relaunched signed in; the folder came back at 0.5 MB and reached 2.5 MB after 5 channels."
  }
}
```

| Field | What to write |
|---|---|
| `id` | Lowercase and dotted, starting with the app or tool: `slack.cache`, `cargo.target`. Unique across all files. |
| `title` | A short name for the place, with no trailing period. |
| `pattern` | Where it lives. See [Patterns](#patterns). |
| `tier` | `safe`, `rebuild`, `review` or `never`. See [Choosing a tier](#choosing-a-tier). |
| `whatItIs` | One sentence in plain words on what the folder holds. |
| `consequence` | One sentence on what the person loses or waits for if they remove it. Concrete beats general: "You will be signed out of Zoom" says more than "Some settings may be lost". |
| `sideCondition` | Something to do first, such as "Quit Slack first.", or `null`. |
| `cleanupCommand` | The tool's own cleanup command, such as `brew cleanup --prune=all`, or `null`. The app shows it and never runs it. |
| `ownerBundleIDs` | Bundle IDs of the apps that own the folder, so the app can say who it belongs to. Empty when no app owns it. |
| `source` | Where the claim comes from, in one line. |
| `evidence` | How the claim was checked. See [Evidence](#evidence). |

## Choosing a tier

Ask these in order and stop at the first yes.

1. **Could removing it lose something the person made, bought or can't download again?** That is `review`, or `never` when removal breaks the app or the system. Messages, projects, the extensions someone installed in VS Code and Maven's local repository (where `mvn install` puts your own builds) all land here.
2. **Does the app or tool put it back on its own, with nothing visible lost?** That is `safe`. The bar is high: it comes back without a download the person would notice, without signing them out, and without losing settings.
3. **Does it come back at a cost of time, network or a login?** That is `rebuild`, with the cost written in `consequence`.
4. **Not sure?** That is `review`. Uncertain always means review.

Two traps are worth knowing, because the lab found both.

- **Some things come straight back.** Chrome's components, Zoom's components and Teams' service worker were all downloaded again within minutes of being removed. Removing them frees nothing for long, so they are `review` with that consequence spelled out, never `safe`.
- **Some folders hold programs.** Discord keeps its own modules in `~/Library/Application Support/discord/app-*/modules`. Removing them broke Discord with "Cannot find module discord_desktop_core" until they came back from the Trash. A broad rule such as `**/node_modules` would have matched there, which is why those folders now have `never` rules of their own.

## Evidence

The `evidence.method` says how the claim was checked, and it limits which tier a rule may have.

| Method | What it means | Allowed tiers |
|---|---|---|
| `relaunch-test` | Removed in a clean macOS VM, the app relaunched or the tool run again, and the result observed | any |
| `vendor-doc` | The vendor's own documentation says what the folder is and that it can be removed | any |
| `research` | Articles, forum posts, issue trackers or reading the source | `review`, `never` |
| `location` | Only where it sits, such as a folder inside an app's container | `review`, `never` |

A `relaunch-test` must also fill `appVersion`, `macOSVersion`, `measuredOn` (as `YYYY-MM-DD`) and `observed`. Write `observed` as what happened, with numbers where you have them: "Deleting the 1,064 MB cache freed 0 bytes, because uv clones its files into each environment" is the kind of sentence that makes a rule trustworthy. If you didn't record a version, say "version not recorded" rather than guessing one.

Eight older `rebuild` rules still rest on `research`. The checker keeps a list of them, and that list may only shrink. If you measure one of them, you are welcome to replace its evidence and remove it from the list.

### Space that isn't freed

DeepYellow adds up file sizes, but APFS can share blocks between files, so removing a folder sometimes frees much less than its size. The lab measured this more than once.

| Folder | Counted | Removing it freed |
|---|---:|---:|
| uv cache | 1,064 MB | 0 MB |
| pnpm store | 1,085 MB | 64 MB |
| conda `pkgs` | 1,808 MB | 133 MB |
| Bun cache | 558 MB | about 0 MB |

When your measurement shows this, say so in `observed` and in `consequence`, so nobody removes a folder expecting space they won't get.

## Patterns

The grammar is on the [rules page](../docs/reclaim-rules.md#pattern-grammar). A few habits keep patterns from matching more than they should.

- **Prefer an anchored path** such as `~/Library/Application Support/Slack/Cache`. A floating pattern such as `**/target` matches anywhere on the disk.
- **Guard floating patterns** with `if-sibling:`, so `**/target if-sibling:Cargo.toml` only matches a Rust project's build folder.
- **Use `*` for anything account-specific.** Many apps put a user, team or profile ID in their paths, which is personal data, so Teams' rule says `EBWebView/WV2Profile_*/Service Worker` and never the real profile name.
- **The most specific rule wins**, and a `never` rule above a folder beats anything beneath it. If your rule must win over a broader one, add a test for it in `Packages/DYAdvisor/Tests/DYAdvisorTests/RuleFilesTests.swift`, next to `testDiscordModulesProtectWhatTheyBundle`.

## Privacy

Rules are public, so nothing in them may identify a person. No user names, email addresses, account or team IDs, file names from your own disk, or anything copied from a signed-in app. Replace each account-specific part of a path with `*`. The checker looks for the common cases, but it can't catch everything, so read your rule once more with this in mind.

## Checking your change

Run these from the repo root before opening a pull request.

```sh
python3 scripts/check-rules.py          # format, tier vs evidence, patterns, privacy
python3 scripts/gen-rules-doc.py        # regenerate docs/reclaim-rules.md
swift test --package-path Packages/DYAdvisor   # the app loads every rule and checks which one wins
```

All three run in CI on every pull request. If you use [Claude Code](https://claude.com/claude-code), the `write-rule` skill in this repo walks through all of this for you. See [CONTRIBUTING.md](../CONTRIBUTING.md) for the rest.
