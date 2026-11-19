---
name: measure-app
description: Measure one Mac app's disk footprint in a tart lab VM (install, use, snapshot, remove and relaunch), produce the scrubbed compare report, then hand it to write-rule as relaunch-test evidence. Use when someone wants to measure an app, or turn a real run of an app into a reclaim rule.
---

# Measure an app in a lab VM

This skill drives the steps in [docs/lab-guide.md](../../../docs/lab-guide.md). Read that guide first, and follow the project CLAUDE.md throughout. The measurement runs only inside a VM made by `lab/lab.sh`. If the contributor can't run a VM, use the `research-app` skill instead, which writes a rule from documentation.

## Ground rules

- **Run nothing against this Mac's real home folder.** Every command that touches app files goes through `lab/lab.sh ssh <vm>` or `lab/lab.sh push/pull`.
- **Never delete or move anything on this Mac.** Deleting is allowed only inside the VM, and never on a `dy-base*` VM (`lab.sh` refuses it).
- **Never sign in with an account that holds other people's private conversations.** Ask the contributor to use a test account, and do not enter credentials for them.
- **Never invent facts.** If a step fails or a value wasn't recorded, say so.
- **Nothing leaves the lab except the scrubbed Markdown report.** Never print or commit `--raw-json` output, snapshots, screenshots or file names. Raw files stay in `$LAB_HOME/runs/<vm>`.
- **Don't commit or push** unless the contributor asks.

## Steps

### 1. Ask what is needed

One question at a time, for whatever is missing:

- the app's name
- how to install it: a Homebrew cask token, or a download URL and the `.app` name
- whether it needs a sign-in, and that they have a test account for it

### 2. Check the lab is ready

Check that `tart` runs (`tart --version`), that `dist/DeepYellow.app` exists, and that the base VM `dy-base` is listed in `tart list`. If one is missing, point to the matching section of the guide. The guide says "not documented yet" for building the base VM and the SSH setup, so tell the contributor that and stop there.

### 3. Run the lab steps

Pick a VM name such as `m-<app>`. Run the commands from "Measure one app" in the guide, in order: `new`, `up`, `install-dy`, `baseline`, install the app, sign in (the contributor does this in the VM window), run the usage script, `snap <vm> after`, the relaunch test.

- For the usage script, copy `lab/apps/TEMPLATE.sh` to `lab/apps/<app>/drive.sh`, fill in the app path and bundle id, and use a script that sends only navigation keys. Show it to the contributor before it runs.
- Record the app version printed by the install step, and the VM's macOS version from `lab/lab.sh ssh <vm> 'sw_vers -productVersion'`.
- Record the date with `date +%F` on this Mac when you finish. Never use a date from memory.

### 4. Produce the scrubbed report

Run `lab/compare.py` as in the guide, with `--home /Users/admin`, an `--app-token` for each word in the app's folder names, `--noise` with `n0.csv` and `n1.csv`, and a `--redact` for each account-specific string the contributor gives you. Don't pass `--raw-json`. Read `report.md` and check that every account-specific part is `*`. Redact again if not.

### 5. Run the relaunch test

Pick the attributed folders with the largest growth. Run `relaunch.sh` on them, with `APP`, `BUNDLE`, `PROC` and `DRIVE` set for the app. Record in plain words whether the app started, whether it was still signed in, and how much of each folder came back. Do not describe anything you saw in a screenshot beyond that.

### 6. Clean up

Run `lab/lab.sh down <vm>`, then `lab/lab.sh rm <vm>` once the contributor agrees. Tell them the raw snapshots remain in `$LAB_HOME/runs/<vm>`.

### 7. Hand off to write-rule

Call the `write-rule` skill with: the app and `appVersion`, `macOSVersion`, `measuredOn` (from `date +%F`), the evidence method `relaunch-test`, the scrubbed report, the folders tested, and the `observed` sentence from step 5. Keep one app per pull request.
