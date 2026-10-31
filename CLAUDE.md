# DeepYellow

Native macOS disk analyzer. Product intent: `docs/DESIGN.md`. Build contract: `CONTRACT.md`.

## Machine safety rules (the owner's hard limits; these override everything)

This is the owner's real machine. **Do nothing here that isn't recoverable, and never use the app to delete anything.**

1. **The app's Apply path never runs against the real filesystem.** Never call `SystemTrash`, and never trigger Apply, from tests, tools, harnesses or manual runs. Any run of the app or CLI on this machine uses `--demo` (in-memory fake Trash) or read-only commands.
2. **Delete, move or overwrite only what you created in this session**, and only inside this project's `.build/`, `dist/` or a temp directory. No `git clean`, `git reset --hard`, `git push --force`, or tag or branch deletion.
3. **Don't change the machine.** No `brew install`, `npm -g`, `sudo`, writes to `/Applications`, `/usr/local` or `~/.local`, `tccutil`, `defaults write`, `security`, `launchctl`, `spctl --add`, System Settings changes, or `xattr` or `codesign` on anything outside `dist/` or a temp directory.
4. **Installers and install scripts are tested only with a temp directory as the destination.**
5. **Set `DEEPYELLOW_HOME` to a temp directory on every app run**, so `~/Library/Application Support` stays untouched.
6. **No personal data leaves this machine.** Screenshots, docs and fixtures come from `SyntheticTree` (`--demo`) only. Never commit or print real file names. Reading the real disk is allowed for aggregate measurements only.
7. **Only the orchestrator commits and pushes.** Agents leave changes in the working tree.

## Conventions

- Each module is its own SwiftPM package in `Packages/`. Test one with `swift test --package-path Packages/<Name>`, or all with `make test`.
- Every function and method gets a doc comment, with one responsibility per type and method.
- No network code in the app. The app never phones home.
- Colours come only from `DYCore/Palette.swift`.
- Copy: plain words, concrete numbers, no hype. Don't claim anything that isn't measured or tested.
