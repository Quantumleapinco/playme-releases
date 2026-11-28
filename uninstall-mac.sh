#!/bin/bash
# Removes Nagenli from a Mac. Your library, settings and watch history stay where they are.
set -euo pipefail

LABEL=app.nagenli.server
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
# The LaunchAgent of the same program under its earlier name (PlayMe), if one is left.
OLD_LABEL=app.playme.server
launchctl bootout "gui/$(id -u)/$OLD_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
rm -rf "$HOME/Library/Nagenli"
echo "Nagenli is removed."
echo "Your data is still in: $HOME/Library/Application Support/Nagenli (delete that folder too to remove everything)."
