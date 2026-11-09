# Contributing

Thanks for wanting to help. The most useful thing most people can add is a reclaim rule, which is the advice DeepYellow gives about one folder: what it is, whether it is safe to remove and what removal costs. The rules live as JSON in [`rules/`](rules/), and [rules/README.md](rules/README.md) explains how to write one.

There are three ways to help with rules, depending on how much time you have.

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

The strongest evidence is a measurement. That means installing the app in a clean macOS virtual machine, using it, removing the folder, relaunching the app and recording what came back and what broke. That is how the rules in `90-apps.json` and most of `40-package-managers.json` were made, with the scripts in [`lab/`](lab/). They need an Apple Silicon Mac and [tart](https://tart.run). A step-by-step guide for running them on your own Mac isn't written yet, so for now read the header of `lab/lab.sh` and the scripts in `lab/pm/` as examples.

Never measure on your own Mac, and never record from someone else's private conversation or meeting while testing an app.

## Pull requests

- Keep one app or tool per pull request, so each one can be reviewed against its evidence.
- Run `python3 scripts/check-rules.py`, `python3 scripts/gen-rules-doc.py` and `swift test --package-path Packages/DYAdvisor`. CI runs them too, along with every other test.
- Every rule change is reviewed by the maintainer before it ships, because people will delete files on the strength of it.

## Code

For changes to the app itself, start with [building from source](docs/building-from-source.md) and [architecture](docs/architecture.md). A few conventions apply everywhere: every function gets a doc comment, the app has no network code, colours come only from `Packages/DYCore/Sources/DYCore/Palette.swift`, and copy uses plain words and concrete numbers with no claim that hasn't been measured or tested.
