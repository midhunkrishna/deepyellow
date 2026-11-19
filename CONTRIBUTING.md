# Contributing

Thanks for wanting to help. The most useful thing most people can add is a reclaim rule, which is the advice DeepYellow gives about one folder: what it is, whether it is safe to remove and what removal costs. The rules live as JSON in [`rules/`](rules/), and [rules/README.md](rules/README.md) explains how to write one.

There are three ways to help with rules, depending on how much time you have.

## Pick an app

Look at issues labelled [`good first issue`](https://github.com/midhunkrishna/deepyellow/labels/good%20first%20issue) and [`app-rule`](https://github.com/midhunkrishna/deepyellow/labels/app-rule). Claim one by commenting "I'll take this". If no pull request has arrived after 14 days, it is free again. You can also open an [app rule issue](https://github.com/midhunkrishna/deepyellow/issues/new?template=app-rule.yml) for an app that isn't listed.

There are two paths for an app:

- **No VM.** Use the `research-app` skill. It gives a `review`-tier rule unless a vendor document supports more.
- **Lab.** Follow [docs/lab-guide.md](docs/lab-guide.md) and the `measure-app` skill. You need this for a `safe` or `rebuild` tier.

## Skills

| Skill | What it does | When to use it |
|---|---|---|
| `research-app` | Finds the app's folders and sources without a VM and drafts the evidence | You can't run a lab, or want a first pass |
| `measure-app` | Walks through a lab measurement in a clean VM | You want `safe` or `rebuild` |
| `write-rule` | Picks the tier the evidence allows, writes the entry and runs the checks | You have the evidence and need the rule written |

In Claude Code, ask for the skill by name, for example "run the `research-app` skill for Example App". For other agents, point them at `.claude/skills/<name>/SKILL.md` in this repo.

Using an agent is welcome. Say so in the pull request. You are responsible for what it wrote, so read the rule before you submit it.

## 1. Tell us about a folder

You may know a folder on your Mac that DeepYellow says nothing about, or says the wrong thing about. [Open an issue](https://github.com/midhunkrishna/deepyellow/issues/new) with:

- the app or tool, and its version
- the path, with any user name, account or team ID replaced by `*`
- what it holds, and what happened when it was removed, if you know
- where that knowledge comes from: the vendor's documentation, a measurement, or an article or forum thread

Please don't paste file names or screenshots from your own disk.

## 2. Write a rule from documentation or research

If the vendor documents the folder, or you have good sources, you can write the rule yourself. Add it to the right file in `rules/`, then run the checks in [rules/README.md](rules/README.md#checking-your-change) and open a pull request. Rules based on `research` can only say `review` or `never`, and rules based on `vendor-doc` can have any tier, so link the documentation in `source`.

If you use [Claude Code](https://claude.com/claude-code), run the `write-rule` skill from this repo. It asks what you know, picks the tier the evidence allows, writes the entry and runs the checks.

## 3. Measure a rule

The strongest evidence is a measurement. That means installing the app in a clean macOS virtual machine, using it, removing the folder, relaunching the app and recording what came back and what broke. That is how the rules in `90-apps.json` and most of `40-package-managers.json` were made, with the scripts in [`lab/`](lab/). They need an Apple Silicon Mac and [tart](https://tart.run). The step-by-step guide is [docs/lab-guide.md](docs/lab-guide.md).

Never measure on your own Mac, and never record from someone else's private conversation or meeting while testing an app.

## Pull requests

- Keep one app or tool per pull request, so each one can be reviewed against its evidence.
- Run `make check-rules`. It runs `scripts/check-rules.py`, `scripts/gen-rules-doc.py --check` and `swift test --package-path Packages/DYAdvisor`, and is the fast check. CI runs them too, along with every other test.
- Every rule change is reviewed by the maintainer before it ships, because people will delete files on the strength of it.

## Code

For changes to the app itself, start with [building from source](docs/building-from-source.md) and [architecture](docs/architecture.md). A few conventions apply everywhere: every function gets a doc comment, the app has no network code, colours come only from `Packages/DYCore/Sources/DYCore/Palette.swift`, and copy uses plain words and concrete numbers with no claim that hasn't been measured or tested.
