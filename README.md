# Meeting Auto-Joiner

Automatically opens Zoom and Google Meet links when your meetings are about to start. Runs as a lightweight macOS background service.

## How it works

- Reads events from macOS Calendar via [icalBuddy](https://hasseg.org/icalBuddy/)
- Checks every 5 minutes for upcoming meetings
- Opens Zoom/Google Meet links ~5 minutes before start
- Tracks opened meetings to avoid duplicates
- Shows as "MeetingJoiner" in Activity Monitor

Works with any calendar synced to macOS Calendar (Google, Outlook, iCloud, etc.).

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- A calendar synced to macOS Calendar app
- Terminal app granted Full Disk Access (for icalBuddy to read calendars)

## Install

```bash
git clone https://github.com/dotfundavid/meeting-joiner.git
cd meeting-joiner
bash install.sh
```

The installer will:
1. Install icalBuddy via Homebrew (if not present)
2. Copy scripts to `~/.claude/meeting-joiner/`
3. Register a launchd agent that starts on login

### Calendar permissions

If icalBuddy reports "No calendars", grant your terminal app Full Disk Access:

**System Settings > Privacy & Security > Full Disk Access > + > add your terminal app**

Then restart your terminal and run `icalBuddy eventsToday` to verify.

## Usage

Once installed, it runs automatically. No interaction needed.

```bash
# View log of opened meetings
cat ~/.claude/meeting-joiner/joiner.log

# Stop the service
launchctl unload ~/Library/LaunchAgents/co.dotfun.meeting-joiner.plist

# Start the service
launchctl load ~/Library/LaunchAgents/co.dotfun.meeting-joiner.plist

# Uninstall
bash uninstall.sh
```

## Configuration

Environment variables in the launchd plist or script:

| Variable | Default | Description |
|---|---|---|
| `LEAD_TIME` | `5` | Minutes before meeting to open link |
| `CACHE_MAX_AGE` | `300` | Seconds between calendar refreshes |
| `ICALBUDDY_PATH` | `/opt/homebrew/bin/icalBuddy` | Path to icalBuddy |

## Supported meeting links

- Zoom (`zoom.us/j/...`)
- Google Meet (`meet.google.com/...`)

## License

MIT
