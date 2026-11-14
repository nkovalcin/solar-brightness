#!/bin/zsh
# Install solar-brightness on macOS: script to ~/.local/bin, LaunchAgent every 5 minutes.
#   zsh macos/install.sh
set -eu
DIR="${0:A:h}"
LABEL="io.github.solar-brightness"
BIN="$HOME/.local/bin"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/solar-brightness.log"

[[ "$(uname)" == "Darwin" ]] || { echo "macOS only. On Windows use windows/install.ps1"; exit 1; }
command -v python3 >/dev/null || { echo "python3 is missing: xcode-select --install"; exit 1; }

if [[ "$(uname -m)" == "arm64" ]] && ! command -v m1ddc >/dev/null; then
  if command -v brew >/dev/null; then
    echo "installing m1ddc (external monitors over DDC)"
    brew install m1ddc
  else
    echo "note: external monitors need m1ddc (brew install m1ddc); the built-in panel works without it"
  fi
fi

mkdir -p "$BIN" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
install -m 755 "$DIR/solar-brightness" "$BIN/solar-brightness"
sed -e "s#__BIN__#$BIN#g" -e "s#__LOG__#$LOG#g" -e "s#__LABEL__#$LABEL#g" \
  "$DIR/solar-brightness.plist" > "$AGENT"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT"

echo "--- where:";   "$BIN/solar-brightness" --where
echo "--- today:";   "$BIN/solar-brightness" --sun | tail -n +3
echo "installed. Runs every 5 minutes. Log: $LOG"
[[ ":$PATH:" == *":$BIN:"* ]] || echo "tip: add $BIN to your PATH to call solar-brightness directly"
