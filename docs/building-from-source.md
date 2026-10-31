# Building from source

**Can anyone build it?** Yes. Clone the repository and run `make app`. You need macOS 15 or later and the Swift 6 toolchain (Xcode 16 or the matching command line tools). Nothing else is installed and no network access is needed beyond the clone, because the project has no third-party dependencies.

This is the route that needs no trust in a binary: you read the code, you build it, and macOS has no quarantine flag to complain about, because nothing was downloaded.

```
git clone https://github.com/midhunkrishna/deepyellow
cd deepyellow
make app
```

The app is written to `dist/DeepYellow.app`. To run it on the sample disk, which never touches your files:

```
dist/DeepYellow.app/Contents/MacOS/DeepYellow --demo
```

## Make targets

| Target | What it does |
|---|---|
| `make test` | Runs the tests of every package |
| `make app` | Builds a universal (arm64 and x86_64) `dist/DeepYellow.app` with its `Info.plist`, generated icon and resources, and signs it ad hoc. `ARCHS="arm64" make app` gives a quicker single-architecture build. |
| `make dmg` | Builds the app, then `dist/DeepYellow.dmg`, `DeepYellow.zip` and `SHA256SUMS` |
| `make install PREFIX=<dir>` | Installs the app into `<dir>/Applications` and the command link into `<dir>/.local/bin` (default `PREFIX` is your home folder) |
| `make icon` | Regenerates the committed icon files |
| `make clean` | Removes `dist/` |

Release packaging uses the stable names `DeepYellow.dmg`, `DeepYellow.zip` and `SHA256SUMS`. The version is taken from the `VERSION` environment variable, else from `git describe`, else it is `0.0.0-dev`.

The scripts live in [`scripts/`](https://github.com/midhunkrishna/deepyellow/tree/master/scripts) and the [`Makefile`](https://github.com/midhunkrishna/deepyellow/blob/master/Makefile) only wraps them.

## Tests

Each module is its own Swift package under `Packages/` and has its own tests:

```
swift test --package-path Packages/DYAnalysis
```

or all of them with `make test`. Tests use a synthetic disk or temporary directories. They never use the real Trash, and tests that need a GPU skip themselves when no Metal device exists.

## Gatekeeper and your own build

A binary you build locally is signed ad hoc and is not quarantined, so it opens without the dialog described in [Install](install.md#if-macos-blocks-it). If you copy it to another Mac through the internet or AirDrop, that Mac will treat it like any unnotarized download.

## Contributing

Releases are versioned from conventional commit messages: a `feat` makes a minor release, a `fix` or anything else a patch, and `!` or `BREAKING CHANGE` a major one. Documentation-only changes make no release. The [architecture](architecture.md) page explains where things live.
