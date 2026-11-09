#!/bin/sh
# Drives the app lab: macOS VMs (tart) where apps are installed, used and measured, so nothing runs on this Mac.
# Every VM is a copy of the frozen base VM, which this script never boots or deletes.
#
# usage: lab/lab.sh <command> <vm> [args]
#   new <vm>                 copy the base VM
#   up <vm>                  boot it in a window and wait for SSH
#   ssh <vm> [command]       run a command in the VM (a shell when none is given)
#   push <vm> <local> <remote>, pull <vm> <remote> <local>
#   install-dy <vm> [app]    copy DeepYellow.app (default dist/DeepYellow.app) and lab/guest/* to /opt/deepyellow
#   snap <vm> <label>        take a disk snapshot in the VM and copy it to the run folder
#   baseline <vm> [seconds]  idle baseline: snapshots n0 and, after the wait (default 120), n1
#   shot <vm> <label>        take a screenshot in the VM and copy it to the run folder
#   down <vm>                shut the VM down
#   rm <vm>                  delete the VM
#
# Environment: TART (path to tart), LAB_BASE (default dy-base), LAB_HOME (default ~/.tart/dy-lab).
# Raw snapshots and screenshots go to $LAB_HOME/runs/<vm>, never into the repo.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tart=${TART:-tart}
base=${LAB_BASE:-dy-base}
lab_home=${LAB_HOME:-$HOME/.tart/dy-lab}

die() { echo "lab: $*" >&2; exit 1; }

# Refuses to act on a base VM (dy-base, dy-base-dev, ...), which must stay as it was frozen.
not_base() {
    case $1 in dy-base*|"$base") die "$1 is a frozen base VM; copy it with 'new' instead" ;; esac
}

# Prints the VM's IP address, waiting up to two minutes for it to boot.
vm_ip() {
    "$tart" ip "$1" --wait 120
}

# Runs ssh against the VM with the lab key and host list, never the user's own SSH settings.
vm_ssh() {
    vm=$1; shift
    ssh -F "$lab_home/ssh_config" -o HostName="$(vm_ip "$vm")" -o BatchMode=yes dy-vm "$@"
}

# Copies files between this Mac and the VM. Remote paths are written as dy-vm:<path>.
vm_scp() {
    vm=$1; shift
    scp -q -F "$lab_home/ssh_config" -o HostName="$(vm_ip "$vm")" -o BatchMode=yes "$@"
}

# The folder that holds a VM's raw snapshots and screenshots.
run_dir() {
    mkdir -p "$lab_home/runs/$1"
    echo "$lab_home/runs/$1"
}

# Boots the VM in its own session (so stopping whatever started it cannot kill the VM) and waits until SSH answers.
cmd_up() {
    not_base "$1"
    perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!"' "$tart" run "$1" \
        < /dev/null > "$(run_dir "$1")/tart-run.log" 2>&1 &
    ip=$(vm_ip "$1")
    tries=0
    until nc -z -G 2 "$ip" 22 2>/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -lt 40 ] || die "SSH on $1 ($ip) did not answer"
        sleep 3
    done
    echo "$1 is up at $ip"
}

# Copies DeepYellow into the VM, outside every measured folder, with its own settings folder.
cmd_install_dy() {
    app=${2:-$root/dist/DeepYellow.app}
    [ -d "$app" ] || die "$app not found"
    vm_ssh "$1" 'sudo mkdir -p /opt/deepyellow/home && sudo chown -R admin /opt/deepyellow && rm -rf /opt/deepyellow/DeepYellow.app'
    vm_scp "$1" -r "$app" dy-vm:/opt/deepyellow/
    vm_scp "$1" "$root"/lab/guest/* dy-vm:/opt/deepyellow/
    vm_ssh "$1" '/opt/deepyellow/DeepYellow.app/Contents/MacOS/DeepYellow --cli --version'
}

# Takes a snapshot in the VM and copies the CSV to the run folder.
cmd_snap() {
    [ -n "${2:-}" ] || die "snap needs a label"
    vm_ssh "$1" "sh /opt/deepyellow/snapshot.sh /tmp/snap-$2.csv"
    vm_scp "$1" "dy-vm:/tmp/snap-$2.csv" "$(run_dir "$1")/$2.csv"
    echo "$(run_dir "$1")/$2.csv"
}

# Takes a screenshot in the VM and copies it to the run folder.
cmd_shot() {
    [ -n "${2:-}" ] || die "shot needs a label"
    vm_ssh "$1" "screencapture -x /tmp/shot-$2.png"
    vm_scp "$1" "dy-vm:/tmp/shot-$2.png" "$(run_dir "$1")/$2.png"
    echo "$(run_dir "$1")/$2.png"
}

# Takes the idle baseline: lets the VM settle for a minute, snapshots n0, waits (default 120 s) and snapshots n1.
cmd_baseline() {
    vm_ssh "$1" 'sleep 60'
    cmd_snap "$1" n0
    vm_ssh "$1" "sleep ${2:-120}"
    cmd_snap "$1" n1
}

# Shuts the VM down and waits until tart reports it stopped.
cmd_down() {
    vm_ssh "$1" 'sudo shutdown -h now' > /dev/null 2>&1 || true
    tries=0
    until "$tart" list | grep -q "[[:space:]]$1[[:space:]].*stopped"; do
        tries=$((tries + 1))
        [ "$tries" -lt 40 ] || die "$1 did not stop"
        sleep 3
    done
    echo "$1 stopped"
}

[ $# -ge 2 ] || die "usage: lab/lab.sh <new|up|ssh|push|pull|install-dy|snap|baseline|shot|down|rm> <vm> [args]"
command=$1; shift
case $command in
    new) not_base "$1"; "$tart" clone "$base" "$1" ;;
    up) cmd_up "$1" ;;
    ssh) vm_ssh "$@" ;;
    push) vm_scp "$1" -r "$2" "dy-vm:$3" ;;
    pull) vm_scp "$1" -r "dy-vm:$2" "$3" ;;
    install-dy) cmd_install_dy "$@" ;;
    snap) cmd_snap "$@" ;;
    baseline) cmd_baseline "$@" ;;
    shot) cmd_shot "$@" ;;
    down) not_base "$1"; cmd_down "$1" ;;
    rm) not_base "$1"; "$tart" delete "$1" ;;
    *) die "unknown command: $command" ;;
esac
