#!/bin/sh
# Notarizes dist/DeepYellow.app with Apple's notary service and staples the ticket.
# Requires a Developer ID signed app and NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD
# (an app-specific password) in the environment. Used by CI only when those secrets exist.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/dist/DeepYellow.app"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ditto -c -k --keepParent "$app" "$tmp/notarize.zip"
xcrun notarytool submit "$tmp/notarize.zip" \
    --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
xcrun stapler staple "$app"
