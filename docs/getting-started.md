# Getting started

Let's go from the download to your first reclaimed gigabytes. It takes about five minutes, and most of that is the scan.

## 1. Install and open

Download `DeepYellow.dmg` from the [latest release](https://github.com/midhunkrishna/deepyellow/releases/latest), drag DeepYellow to Applications and open it. The build is not notarized, so the first launch is blocked until you approve it once, and the steps for that are in [If macOS blocks it](install.md#if-macos-blocks-it). Other routes are in [Install](install.md).

DeepYellow needs macOS 15 or later.

## 2. Give it Full Disk Access (recommended)

Without Full Disk Access, macOS hides parts of your disk from every app. DeepYellow tells you this up front and counts what it could not read, but a complete scan needs the permission.

1. Open **System Settings > Privacy & Security > Full Disk Access**.
2. Switch **DeepYellow** on. If it is not listed, click **+** and add it from Applications.
3. Quit and reopen DeepYellow.

If you would rather skip this, you can scan a single folder instead. See [Full Disk Access](safety-and-accounting.md#full-disk-access).

![The welcome screen](screens/app-welcome.png)

## 3. Scan

Choose a volume or a folder on the welcome screen, or drop a folder onto the Dock icon. The map grows while the scan runs and you can interact with it from the first second. You can also try everything on a built-in sample disk:

```
deepyellow --demo
```

### Want to look at your real disk first?

For that, open it in read-only mode:

```
deepyellow ~ --read-only
```

This does a real scan, so the sizes, the map and the advice are real, but **nothing can be moved to the Trash** in that mode. It is a good way to get to know the app before you trust it with a Plan (link the `deepyellow` command first, see [Install](install.md#install-the-command-line-tool)). More in [Command line](cli.md).

## 4. Find the gold

The [Map](views.md#map) is the main view. Press <kbd>c</kbd> until the colour mode is **Safety**. Everything dims except what is safe or rebuildable, and that glows gold.

![The map in Safety mode](screens/app-map-safety.png)

Then press <kbd>7</kbd> for [Reclaim](views.md#reclaim). Items are grouped by tier, and each shows what it is, what removing it costs, and the official cleanup command where there is one.

Not everything has advice. For most personal files, such as photos, documents and downloads, the answer is "no advice", since only you can judge those.

## 5. Decide

Select an item and press one key.

| Key | Verdict |
|---|---|
| <kbd>k</kbd> | Keep |
| <kbd>x</kbd> | Remove (staged, not done) |
| <kbd>l</kbd> | Later |
| <kbd>u</kbd> | Clear |

Nothing is pre-marked. For a long list, press <kbd>r</kbd> to open [Review](views.md#review), which goes through the current set one item at a time with a preview.

## 6. Apply, then check the Trash

Press <kbd>&#8984;&#9166;</kbd> to open the **Plan**: the list of items that will be moved to the Trash, what is protected inside them, and what is blocked and why.

![The plan](screens/app-plan.png)

Apply moves them to the Trash and offers one-step undo. **Space is not freed until you empty the Trash**, and DeepYellow never empties it for you. More in [Safety and accounting](safety-and-accounting.md).

## Next

- [Views and keys](views.md)
- [Query language](query-language.md)
- [The command line](cli.md)
