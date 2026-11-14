#!/bin/zsh
# Remove solar-brightness from macOS. Config and state stay unless you pass --purge.
set -eu
LABEL="io.github.solar-brightness"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/solar-brightness"
if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$HOME/.config/solar-brightness" "$HOME/.local/state/solar-brightness" "$HOME/Library/Logs/solar-brightness.log"
fi
echo "solar-brightness removed"
