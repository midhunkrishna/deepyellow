# Measure an app in a lab VM

This guide walks you through measuring where one Mac app writes its files and what comes back when you remove them. You do it in a macOS virtual machine made with [tart](https://tart.run), so nothing runs on your own Mac. The result is a scrubbed report that you hand to the `write-rule` skill (or to [rules/README.md](../rules/README.md)) to write a reclaim rule with `relaunch-test` evidence.

If you can't run a VM, the `research-app` skill writes a rule from the vendor's documentation instead. That evidence is weaker, so it can only give the `review` or `never` tiers.

## Hard rules

- Never measure on your own Mac's real home folder. Everything below happens inside the VM.
- Never delete anything on your own Mac to test a rule. Deleting inside the VM is fine, which is the point of it.
- Never sign in with an account that holds other people's private conversations, meetings or files. Use an account made for the test.
- Never commit raw snapshots, raw JSON or screenshots. They stay in `$LAB_HOME/runs/<vm>` on your Mac.

## What you need

- A Mac with Apple Silicon. tart runs macOS guests only there.
- [tart](https://tart.run). Install it yourself by the instructions on its site. The lab scripts call `tart`, or the path in the `TART` environment variable.
- Free disk space. Not documented yet: the size of the base VM and of each copy.
- DeepYellow.app in `dist/DeepYellow.app` of this repo, because `install-dy` copies it into the VM. Not documented yet: how an outside contributor gets this build.
- Python 3 for `lab/compare.py`.

## Build the base VM once

Every measurement runs in a copy of one frozen base VM called `dy-base` (change the name with `LAB_BASE`). The lab never boots or deletes the base. `lab.sh` refuses to run `up`, `down`, `rm` or `new` on any name that starts with `dy-base`.

The base is a macOS VM with a user called `admin`, auto-login, passwordless sudo, and Full Disk Access, Accessibility, Screen Recording and System Events control granted to `/usr/libexec/sshd-keygen-wrapper`, so scripts started over SSH can read every folder and press keys.

Not documented yet: the commands to create the base VM and grant those permissions.

## Set up LAB_HOME and SSH

`lab.sh` keeps its SSH key, host list and run folders in `LAB_HOME`, which is `~/.tart/dy-lab` unless you set it. It reaches the VM with `ssh -F $LAB_HOME/ssh_config`, using the host name `dy-vm`, and never uses your own SSH settings.

Not documented yet: how to create `$LAB_HOME/ssh_config`, the key, and how to put the public key into the base VM.

Raw snapshots and screenshots go to `$LAB_HOME/runs/<vm>`, never into the repo.

## Measure one app

Pick a short VM name, such as `m-slack`. The commands run from the repo root. All of them are in the header of `lab/lab.sh`.

1. Copy the base and boot the copy.

   ```sh
   lab/lab.sh new m-slack
   lab/lab.sh up m-slack
   ```

2. Copy DeepYellow and the guest scripts into the VM, to `/opt/deepyellow`.

   ```sh
   lab/lab.sh install-dy m-slack
   ```

3. Take the idle baseline before you install the app. It waits 60 seconds, snapshots `n0`, waits 120 seconds (or the number you give) and snapshots `n1`. The two snapshots show what the VM writes by itself, which `compare.py` marks as noise.

   ```sh
   lab/lab.sh baseline m-slack
   ```

4. Install the app. For a download, `install-app.sh` takes the URL and the `.app` name. For a Homebrew cask, install Homebrew first (see `lab/pm/homebrew/run.sh`) and run `brew install --cask <token>` through `lab/lab.sh ssh`.

   ```sh
   lab/lab.sh ssh m-slack 'sh /opt/deepyellow/install-app.sh "<download url>" "Name.app"'
   ```

   It prints the app's name and version. Write the version down.

5. Sign in if the app needs it, and open it once. Use the VM window that `up` opened, with a test account.

6. Use the app the way a person does. Copy a usage script into the VM and run it. `lab/apps/TEMPLATE.sh` is the starting point, and `lab/apps/slack/drive.sh`, `spotify` and `vscode` are worked examples.

   ```sh
   lab/lab.sh push m-slack lab/apps/<app>/drive.sh /opt/deepyellow/drive.sh
   lab/lab.sh ssh m-slack 'sh /opt/deepyellow/drive.sh'
   ```

7. Take the snapshot after use.

   ```sh
   lab/lab.sh snap m-slack after
   ```

8. Compare, to find the folders that grew (step 9 of this list tests them). `--home` is the VM user's home folder, `/Users/admin`. Add `--app-token` for each word that appears in the app's folder names (the app name, the bundle id), and `--redact` for each account-specific string, such as a workspace or user name, so it becomes `*`.

   ```sh
   RUN=~/.tart/dy-lab/runs/m-slack
   python3 lab/compare.py "$RUN/n1.csv" "$RUN/after.csv" \
       --home /Users/admin --app-token slack --noise "$RUN/n0.csv" "$RUN/n1.csv" \
       --redact "<workspace name>" --json report.json --md report.md
   ```

   Use another `RUN` if you changed `LAB_HOME`. Add `--raw-json raw.json` only if you need real paths for your own checking, and keep that file on your Mac.

9. Run the relaunch test on the folders you want to remove. `relaunch.sh` quits the app, moves each folder to the VM's Trash, relaunches the app, takes a screenshot to check that you are still signed in, runs the usage script and prints the size of each folder before, after relaunch and after use. Set `APP`, `BUNDLE` and `PROC` for your app. `DRIVE` is the usage command, and an empty value skips it.

   ```sh
   lab/lab.sh ssh m-slack 'APP=/Applications/Slack.app BUNDLE=com.tinyspeck.slackmacgap PROC=Slack DRIVE="sh /opt/deepyellow/drive.sh 5 3" sh /opt/deepyellow/relaunch.sh r1 "$HOME/Library/Application Support/Slack/Cache"'
   ```

   Fetch the screenshot with `lab/lab.sh pull m-slack /tmp/relaunch-r1.png "$RUN/"`, or take one with `lab/lab.sh shot m-slack <label>`. Look at it in the VM's run folder and do not share it.

   Note what happened: did the app start, was it still signed in, did the folder come back, and how much of it.

## Read the report

`report.md` starts with the totals: bytes added, files added, and the part attributed to the app by your `--app-token` words. Three tables follow: Growth, New folders and Shrank. Each row has the scrubbed path, bytes added, files added, the size after, and flags for new folder, attributed to the app, noise, and the safety class DeepYellow gives it today.

Look first at attributed rows, then at large rows that are not. Rows flagged as noise also grew during the idle baseline, so the app probably didn't cause them. A folder that grew is a candidate, and only the relaunch test shows whether removing it is safe.

If removing a folder freed far less than its size, APFS clones or hard links may be involved. Say so in the rule.

## What you may share

Share only `report.md`, the Markdown report from `compare.py`, after you read it and check that every account-specific part of every path is `*`. That means no IDs, emails, workspace or team names, and no user names.

Never share the `--raw-json` output, screenshots, file names from the VM, or the CSV snapshots. If a path in the report still holds something personal, run `compare.py` again with another `--redact`.

## Clean up

```sh
lab/lab.sh down m-slack
lab/lab.sh rm m-slack
```

`rm` deletes the VM. The raw snapshots stay in `$LAB_HOME/runs/m-slack` until you remove that folder yourself.

## Hand off to write-rule

Open Claude Code in this repo and run the `write-rule` skill. Give it the scrubbed `report.md`, the app version from step 4, the macOS version of the VM (`lab/lab.sh ssh m-slack 'sw_vers -productVersion'`, run before you remove the VM), today's date, and what you saw in the relaunch test. The evidence method is `relaunch-test`. Or run the `measure-app` skill, which drives these steps and then calls `write-rule`.

Without Claude Code, follow [rules/README.md](../rules/README.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).
