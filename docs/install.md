# Install

Three routes, from easiest to least trust required. All of them install the same app, and the app contains the command-line tool.

Requirements: macOS 15 or later. The app is a universal binary for Apple silicon and Intel.

## Route 1: download the app

1. Download `DeepYellow.dmg` from the [latest release](https://github.com/midhunkrishna/deepyellow/releases/latest/download/DeepYellow.dmg). A `DeepYellow.zip` is also published, along with `SHA256SUMS`. All releases are listed at [Releases](https://github.com/midhunkrishna/deepyellow/releases).
2. Verify the checksum (see [Verify the download](#verify-the-download)).
3. Open the disk image and drag DeepYellow to Applications.
4. Open it. macOS will probably stop you once; see the next section.

## If macOS blocks it

The first time you open DeepYellow, macOS may say **"DeepYellow" Not Opened** because it could not verify the app is free of malware.

### Why it happens

macOS Gatekeeper checks downloaded apps for a Developer ID signature and an Apple notarization ticket. Notarization requires a paid Apple developer account. DeepYellow is a free open source project and its release builds are **signed ad hoc and not notarized**. Gatekeeper cannot tell who made the app, so it asks you to approve it. That is the whole reason. It does not mean the file is damaged.

### Approve it (macOS 15 and later)

**Control-click, then Open, no longer works.** Since macOS 15 that shortcut does not bypass Gatekeeper. Use System Settings instead:

1. Try to open DeepYellow once. When the message appears, click **Done**. Do not click Move to Trash.
2. Open **System Settings > Privacy & Security** and scroll down to the **Security** section.
3. Find "DeepYellow was blocked to protect your Mac" and click **Open Anyway**.
4. Confirm with your password or Touch ID, then click **Open Anyway** in the dialog that follows.

The Open Anyway button stays available for about an hour after your attempt. If it is not there, try opening the app again.

You only do this once per version you download. Updates installed the same way may ask again.

### Alternative: remove the quarantine flag

If you prefer the Terminal, this command clears the quarantine attribute macOS added to the download:

```
xattr -dr com.apple.quarantine /Applications/DeepYellow.app
```

What it does, honestly: when a browser downloads a file, macOS tags it with `com.apple.quarantine`, and that tag is what makes Gatekeeper assess the app on first launch. The command deletes the tag recursively, so macOS stops asking. It does not verify the app, does not change any code, and does not make the app more or less safe. Only run it on a build you have checked, with the next section. The one-line installer below does the same thing for the copy it installs, and only for that copy.

### Verify the download

Each release publishes `SHA256SUMS`. Download it next to `DeepYellow.dmg`, then in that folder run:

```
grep DeepYellow.dmg SHA256SUMS | shasum -a 256 -c -
```

You should see `DeepYellow.dmg: OK`. For the zip, replace the name. Without the checksums file you can print the value and compare by eye:

```
shasum -a 256 DeepYellow.dmg
```

A checksum proves the file matches what was published with that release. It does not prove the publisher is trustworthy, which is why the next route exists.

### The zero-trust route: build it yourself

Yes, anyone can clone the repository and run `make app`. You need the Swift 6 toolchain, nothing else, and you can read every line first. A binary you built is not downloaded, so it carries no quarantine flag and macOS will not block it. See [Building from source](building-from-source.md).

## Route 2: the one-line installer

```
curl -fsSL https://raw.githubusercontent.com/midhunkrishna/deepyellow/master/scripts/install.sh | sh
```

It downloads the latest release zip, verifies its checksum, installs to `~/Applications` by default, clears the quarantine flag only on what it installed, links the command-line tool into `~/.local/bin`, and prints exactly what it did. It never uses `sudo` silently.

Piping a script into a shell trusts that script. [Read it first](https://github.com/midhunkrishna/deepyellow/blob/master/scripts/install.sh), or use the options:

| Option | Effect |
|---|---|
| `--dry-run` | Print what would happen and change nothing |
| `--dir <path>` | Install the app somewhere other than `~/Applications` |
| `--bin <path>` | Put the `deepyellow` link somewhere other than `~/.local/bin` |
| `--from-file <zip>` | Install from a zip you already downloaded and checked |

If `~/.local/bin` is not on your `PATH`, add it, for example `export PATH="$HOME/.local/bin:$PATH"` in `~/.zshrc`.

## Route 3: build from source

```
git clone https://github.com/midhunkrishna/deepyellow
cd deepyellow
make app
```

Details, tests and the install target are in [Building from source](building-from-source.md).

## Full Disk Access

DeepYellow can scan without it, but macOS then hides some folders from every app. A scan without access reports those folders as unreadable rather than leaving them out silently.

1. Open **System Settings > Privacy & Security > Full Disk Access**.
2. Switch DeepYellow on, or click **+** and add it from Applications.
3. Quit and reopen DeepYellow.

**Updates may need the permission again.** Because release builds are signed ad hoc, a new version can look like a different app to macOS, which may drop the earlier approval. If a scan that was complete starts reporting unreadable folders after an update, switch the entry off and on again, or remove it and add it again.

When you run the command-line tool from a terminal, macOS usually applies the permission of the terminal app that started it, so a protected folder may need Full Disk Access granted to your terminal. See [Command line](cli.md).

## Install the command-line tool

The app contains the `deepyellow` command. Use **DeepYellow > Install Command Line Tool...** to link it. It creates the symlink only after you click, and offers `~/.local/bin`, which needs no administrator rights. The one-line installer does this for you.

## Update and uninstall

To update, install the new version over the old one with any route. To remove DeepYellow and everything it stored, see [Uninstall](uninstall.md).
