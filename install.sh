#!/bin/bash
# Meeting Auto-Joiner installer for macOS

set -e

INSTALL_DIR="$HOME/.claude/meeting-joiner"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="co.dotfun.meeting-joiner"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Meeting Auto-Joiner Installer"
echo "=============================="

# Check for icalBuddy
if ! command -v icalBuddy &>/dev/null; then
    echo "icalBuddy not found. Installing via Homebrew..."
    if ! command -v brew &>/dev/null; then
        echo "Error: Homebrew is required. Install it from https://brew.sh"
        exit 1
    fi
    brew install ical-buddy
fi

ICALBUDDY_PATH=$(which icalBuddy)
echo "Found icalBuddy at: $ICALBUDDY_PATH"

# Test icalBuddy can access calendars
if ! icalBuddy calendars &>/dev/null; then
    echo ""
    echo "Warning: icalBuddy can't access your calendars yet."
    echo "You may need to grant Calendar access to your terminal app:"
    echo "  System Settings > Privacy & Security > Full Disk Access > add your terminal app"
    echo ""
fi

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy scripts
cp "$SCRIPT_DIR/check-meetings.sh" "$INSTALL_DIR/check-meetings.sh"
chmod +x "$INSTALL_DIR/check-meetings.sh"

# Create process wrapper (shows as "MeetingJoiner" in Activity Monitor)
cat > "$INSTALL_DIR/MeetingJoiner" << EOF
#!/bin/bash
exec -a MeetingJoiner /bin/bash "$INSTALL_DIR/check-meetings.sh"
EOF
chmod +x "$INSTALL_DIR/MeetingJoiner"

# Create launchd plist
mkdir -p "$PLIST_DIR"
cat > "$PLIST_DIR/$PLIST_NAME.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/MeetingJoiner</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/launchd-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
EOF

# Load the agent
launchctl unload "$PLIST_DIR/$PLIST_NAME.plist" 2>/dev/null || true
launchctl load "$PLIST_DIR/$PLIST_NAME.plist"

echo ""
echo "Installed successfully!"
echo "  Script:  $INSTALL_DIR/check-meetings.sh"
echo "  Logs:    $INSTALL_DIR/joiner.log"
echo "  Service: $PLIST_NAME (runs every 5 minutes)"
echo ""
echo "Commands:"
echo "  View logs:  cat $INSTALL_DIR/joiner.log"
echo "  Stop:       launchctl unload $PLIST_DIR/$PLIST_NAME.plist"
echo "  Start:      launchctl load $PLIST_DIR/$PLIST_NAME.plist"
echo "  Uninstall:  bash $(dirname "$0")/uninstall.sh"
