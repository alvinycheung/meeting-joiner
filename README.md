# Meeting Auto-Joiner + Announcer

Once installed, you never think about your calendar again.

- **5 minutes before** a meeting, a voice tells you what's coming up — the name, the time, who's in it, and what it's about
- **2 minutes before**, the Zoom or Google Meet link opens automatically
- If the meeting is **somewhere you need to drive**, it factors in travel time from where you are right now and tells you when to leave
- Runs silently in the background and just works

## How it works

- Reads events from macOS Calendar via [icalBuddy](https://hasseg.org/icalBuddy/)
- Checks every **1 minute** for upcoming meetings
- **5 minutes before**: plays a TTS announcement summarizing the meeting (who, what, when) via [Claude CLI](https://claude.ai/claude-code) + [ElevenLabs](https://elevenlabs.io)
- **2 minutes before**: opens Zoom/Google Meet/MS Teams link
- **Location-aware**: if a meeting has a physical location, uses GPS + Apple Maps to calculate travel time and announces when it's time to leave (travel time + 10 min buffer)
- Shows as "MeetingJoiner" in Activity Monitor

Works with any calendar synced to macOS Calendar (Google, Outlook, iCloud, etc.).

## Requirements

- macOS (Apple Silicon)
- [Homebrew](https://brew.sh)
- A calendar synced to macOS Calendar app
- Terminal app granted Full Disk Access (for icalBuddy to read calendars)
- [Claude CLI](https://claude.ai/claude-code) or [OpenAI Codex CLI](https://github.com/openai/codex) installed (falls back to `codex` if `claude` isn't found)
- [ElevenLabs API key](https://elevenlabs.io) for TTS
- `ffmpeg` and `jq` installed via Homebrew

## Personalization

The announcement prompt in `announce-meetings.sh` uses the user's first name (currently "Alvin"). If an agent is setting this up for someone else, ask the user what name they'd like used and replace all occurrences of "Alvin" in `announce-meetings.sh` with their name. Search for "Alvin" in the Claude prompt string and the `location_context` variable.

## Install

### 1. Install dependencies

```bash
brew install ical-buddy ffmpeg jq
```

### 2. Clone and run installer

```bash
git clone https://github.com/alvinycheung/meeting-joiner.git
cd meeting-joiner
bash install.sh
```

The installer will:
1. Install icalBuddy via Homebrew (if not present)
2. Copy scripts to `~/.claude/meeting-joiner/`
3. Register a launchd agent that starts on login

### 3. Set up environment

Create `~/.claude/.env` with your ElevenLabs API key:

```bash
ELEVEN_LABS_API_KEY=sk_your_key_here
```

### 4. Compile the travel-time binary

```bash
cd ~/.claude/meeting-joiner
swiftc -framework CoreLocation -framework MapKit -o travel-time travel-time.swift
```

### 5. Update the launchd plist

The default `install.sh` sets a 5-minute interval. For the announcer to work well, update to 1 minute and add the Claude CLI (or Codex CLI) to the PATH.

Edit `~/Library/LaunchAgents/co.dotfun.meeting-joiner.plist`:

- Change `StartInterval` from `300` to `60`
- Update the `PATH` environment variable to include the directory where `claude` is installed (e.g., `~/.local/bin` or your nvm node bin directory)

Then reload:

```bash
launchctl unload ~/Library/LaunchAgents/co.dotfun.meeting-joiner.plist
launchctl load ~/Library/LaunchAgents/co.dotfun.meeting-joiner.plist
```

### 6. Calendar permissions

If icalBuddy reports "No calendars", grant your terminal app Full Disk Access:

**System Settings > Privacy & Security > Full Disk Access > + > add your terminal app**

Then restart your terminal and run `icalBuddy eventsToday` to verify.

### 7. Location Services (optional)

For travel-time calculations to work, the `travel-time` binary needs Location Services permission. macOS will prompt on first run. Grant access via:

**System Settings > Privacy & Security > Location Services > enable for the binary**

## Usage

Once installed, it runs automatically every minute. No interaction needed.

```bash
# Manually trigger an announcement
bash ~/.claude/meeting-joiner/announce-meetings.sh

# View logs
cat ~/.claude/meeting-joiner/joiner.log

# Stop the service
launchctl unload ~/Library/LaunchAgents/co.dotfun.meeting-joiner.plist

# Start the service
launchctl load ~/Library/LaunchAgents/co.dotfun.meeting-joiner.plist

# Uninstall
bash uninstall.sh
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `LEAD_TIME` | `2` | Minutes before meeting to open link |
| `CACHE_MAX_AGE` | `300` | Seconds between calendar refreshes |
| `ICALBUDDY_PATH` | `/opt/homebrew/bin/icalBuddy` | Path to icalBuddy |
| `VOICE_ID` | (in script) | ElevenLabs voice ID for TTS |

## How the scripts work

| Script | Purpose | Timing |
|---|---|---|
| `MeetingJoiner` | Wrapper that runs both scripts, with lock file to prevent overlap | Every 60s via launchd |
| `check-meetings.sh` | Opens conference links | 2 min before meeting |
| `announce-meetings.sh` | TTS briefing via Claude + ElevenLabs | 5 min before (virtual) or travel-time based (physical) |
| `travel-time` | Swift binary for GPS + Apple Maps drive time | Called by announce-meetings.sh |

## Supported meeting links

- Zoom (`zoom.us/j/...`)
- Google Meet (`meet.google.com/...`)
- Microsoft Teams (`teams.microsoft.com/l/meetup-join/...`)

## License

MIT
