#!/bin/sh
# Runs inside a lab VM: listens to Spotify the way a person skipping through playlists does, so its streaming cache
# fills. It uses only Spotify's own AppleScript commands "play track" and "next track"; it never likes, follows, saves
# or creates anything. The first run asks once (in the VM) to allow controlling Spotify.
#
# usage: sh drive.sh [tracks] [seconds-per-track]
set -eu

tracks=${1:-40}
secs=${2:-20}
# Public Spotify editorial playlists: Today's Top Hits, Rock Classics, Peaceful Piano, All Out 2000s.
playlists="37i9dQZF1DXcBWIGoYBM5M 37i9dQZF1DWXRqgorJj26U 37i9dQZF1DX4sWSpwq3LiO 37i9dQZF1DX4o1oenSJRJd"

# Sends one AppleScript command to Spotify.
spotify() {
    osascript -e "tell application id \"com.spotify.client\" to $1"
}

per_list=$(( (tracks + 3) / 4 ))
played=0
for id in $playlists; do
    spotify "play track \"spotify:playlist:$id\""
    n=0
    while [ "$n" -lt "$per_list" ] && [ "$played" -lt "$tracks" ]; do
        sleep "$secs"
        spotify "next track"
        n=$((n + 1)); played=$((played + 1))
    done
done
spotify "pause"
echo "played $played tracks"
