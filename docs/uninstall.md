# Uninstall

DeepYellow is one app bundle plus a few small folders in your Library. Removing it is deleting these paths. Nothing here is a system location, and nothing in your own files was ever changed by the app.

| What | Path | Notes |
|---|---|---|
| The app | `/Applications/DeepYellow.app` or `~/Applications/DeepYellow.app` | Wherever you or the installer put it |
| Command-line link | `~/.local/bin/deepyellow` | Or the folder you gave with `--bin`. It is a symlink into the app. |
| Decisions, scan cache, removal journal and `recent-folders.json` | `~/Library/Application Support/DeepYellow` | Your keep, remove and later marks, cached scans, the journal used for undo, and the list of recently opened folders. If you set `DEEPYELLOW_HOME`, this folder is that directory instead. |
| Possible system files | `~/Library/Preferences/com.midhunkrishna.deepyellow.plist`, `~/Library/Caches/com.midhunkrishna.deepyellow` | macOS may create these for any app with this bundle identifier. They are safe to remove if they exist. |

Full Disk Access is stored by macOS. Remove the DeepYellow entry in **System Settings > Privacy & Security > Full Disk Access** with the **-** button.

## Step by step

1. Quit DeepYellow.
2. Move the app to the Trash from Finder.
3. If you linked the command, remove the link, which does not touch the app:

   ```
   rm ~/.local/bin/deepyellow
   ```

4. In Finder choose **Go > Go to Folder** (<kbd>&#8679;&#8984;G</kbd>) and open `~/Library/Application Support`. Move the `DeepYellow` folder to the Trash.
5. Do the same for the possible system files if they exist.
6. Empty the Trash when you are ready.

## If you used the installer

The [installer](install.md#route-2-the-one-line-installer) prints exactly which paths it wrote when it finishes. They are the app (in `~/Applications` unless you passed `--dir`) and the command link (in `~/.local/bin` unless you passed `--bin`), and nothing else.

## Things DeepYellow moved to the Trash

Items you applied through a Plan are in the Trash like anything else you trashed, until you empty it. Uninstalling DeepYellow does not restore or remove them. The undo step lives in the app and its journal, so undo anything you want back **before** you delete `~/Library/Application Support/DeepYellow`, or move the items out of the Trash by hand.
