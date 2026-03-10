#!/bin/bash
# Meeting Auto-Joiner uninstaller

INSTALL_DIR="$HOME/.claude/meeting-joiner"
PLIST="$HOME/Library/LaunchAgents/co.dotfun.meeting-joiner.plist"

echo "Uninstalling Meeting Auto-Joiner..."

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$INSTALL_DIR"

echo "Done. Meeting Auto-Joiner has been removed."
