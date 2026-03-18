#!/bin/bash
# Meeting Announcer — summarizes the next upcoming meeting via Claude CLI + ElevenLabs TTS
# Location-aware: uses travel-time binary for physical meetings, opens conference links for virtual ones

DIR="$HOME/.claude/meeting-joiner"
STATE="$DIR/announced.txt"
LOG="$DIR/joiner.log"
ICALBUDDY="${ICALBUDDY_PATH:-/opt/homebrew/bin/icalBuddy}"
VOICE_ID="wrxvN1LZJIfL3HHvffqe"

# Load API key
source "$HOME/.claude/.env"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [announce] $1" >> "$LOG"; }

today=$(date +%Y-%m-%d)
now_mins=$(( $(date +%-H) * 60 + $(date +%-M) ))

# Fetch today's events with attendees
events=$("$ICALBUDDY" -ea -nc -nrd -tf "%H:%M" -df "%Y-%m-%d" \
    -iep "title,datetime,notes,location,attendees" \
    eventsToday 2>/dev/null)

# Fall back to check-meetings cache if icalBuddy can't access calendars
CACHE="$DIR/events-cache.txt"
if [[ -z "$events" ]] && [[ -f "$CACHE" ]] && [[ -s "$CACHE" ]]; then
    events=$(cat "$CACHE")
    log "Using cached events"
fi

if [[ -z "$events" ]]; then
    log "No events found"
    exit 0
fi

# Extract the next upcoming event (first one whose start time is in the future)
next_event=""
next_title=""
next_block=""
start_mins=0
current_title=""
current_block=""

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "• "* ]]; then
        # Process previous event
        if [[ -n "$current_block" ]]; then
            start_time=$(echo "$current_block" | grep -oE '[0-9]{1,2}:[0-9]{2} - [0-9]{1,2}:[0-9]{2}' | head -1 | cut -d' ' -f1)
            if [[ -n "$start_time" ]]; then
                start_h="${start_time%%:*}"
                start_m="${start_time##*:}"
                start_mins=$(( 10#$start_h * 60 + 10#$start_m ))
                if [[ $start_mins -ge $now_mins ]]; then
                    next_title="$current_title"
                    next_block="$current_block"
                    next_event="• ${current_title}"$'\n'"${current_block}"
                    break
                fi
            fi
        fi
        current_title="${line#• }"
        current_block=""
    else
        current_block+="$line"$'\n'
    fi
done <<< "$events"

# Check last event if we haven't found one yet
if [[ -z "$next_event" ]] && [[ -n "$current_block" ]]; then
    start_time=$(echo "$current_block" | grep -oE '[0-9]{1,2}:[0-9]{2} - [0-9]{1,2}:[0-9]{2}' | head -1 | cut -d' ' -f1)
    if [[ -n "$start_time" ]]; then
        start_h="${start_time%%:*}"
        start_m="${start_time##*:}"
        start_mins=$(( 10#$start_h * 60 + 10#$start_m ))
        if [[ $start_mins -ge $now_mins ]]; then
            next_title="$current_title"
            next_block="$current_block"
            next_event="• ${current_title}"$'\n'"${current_block}"
        fi
    fi
fi

if [[ -z "$next_event" ]]; then
    log "No upcoming meetings remaining"
    exit 0
fi

# Don't re-announce the same meeting
key="${today}|${next_title}"
if grep -qF "$key" "$STATE" 2>/dev/null; then
    exit 0
fi

# Extract location from event block
location=$(echo "$next_block" | grep -E '^\s*location:' | sed 's/^[[:space:]]*location:[[:space:]]*//' | head -1)

# Determine timing and context based on location
location_context=""
mins_until=$(( start_mins - now_mins ))

if [[ -n "$location" ]]; then
    # Physical meeting — use travel-time binary
    travel_json=$("$DIR/travel-time" "$location" 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$travel_json" ]]; then
        travel_minutes=$(echo "$travel_json" | grep -o '"travel_minutes"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
        if [[ -n "$travel_minutes" ]]; then
            leave_by_mins=$(( start_mins - travel_minutes - 10 ))
            if [[ $now_mins -lt $leave_by_mins ]]; then
                log "Too early to announce '$next_title' (leave in $(( leave_by_mins - now_mins )) mins)"
                exit 0
            fi
            location_context="The meeting is at ${location}. Travel time from current location is about ${travel_minutes} minutes. The user should leave soon."
        else
            # travel-time returned but couldn't parse — fall back to 10 min window
            log "Could not parse travel_minutes for '$next_title', falling back to 10 min window"
            if [[ $mins_until -gt 10 ]]; then
                exit 0
            fi
            location_context="The meeting is at ${location}. Travel time could not be determined."
        fi
    else
        # travel-time binary failed — fall back to 10 min window
        log "travel-time binary failed for '$next_title', falling back to 10 min window"
        if [[ $mins_until -gt 10 ]]; then
            exit 0
        fi
        location_context="The meeting is at ${location}. Travel time could not be determined."
    fi
else
    # Virtual meeting — announce 5 min before (link opening handled by check-meetings.sh)
    if [[ $mins_until -gt 5 ]]; then
        exit 0
    fi
    location_context="This is a virtual meeting with no physical location."
fi

# Use Claude CLI to summarize the next meeting
SUMMARY=$(echo "$next_event" | command claude --print --model haiku --settings '{"disableAllHooks":true}' -p \
"You are Alvin's fun business partner casually letting him know about his next meeting. Be warm, sweet, and natural — like you're chatting while hanging out together. Mention the meeting name, the time, who's in it (first names only), and what it's about if you can tell. Keep it short and cute. No markdown, no bullet points, no special characters — just natural spoken words. Don't be over the top or cringey, just genuinely warm and caring.

Additional context: ${location_context}" 2>/dev/null)

if [[ -z "$SUMMARY" ]]; then
    log "Claude summarization failed for: $next_title"
    exit 1
fi
log "Summary for '$next_title': ${SUMMARY:0:200}..."

# Truncate to ElevenLabs limit
SUMMARY="${SUMMARY:0:2000}"

# Generate TTS via ElevenLabs
TMPFILE=$(mktemp /tmp/meeting_announce_XXXXXXXX)
mv "$TMPFILE" "${TMPFILE}.mp3"
TMPFILE="${TMPFILE}.mp3"
PAYLOAD=$(jq -n --arg text "$SUMMARY" '{
    text: $text,
    model_id: "eleven_flash_v2_5",
    voice_settings: {
        stability: 0.5,
        similarity_boost: 0.5
    }
}')

curl -s -X POST "https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}" \
  -H "Accept: audio/mpeg" \
  -H "Content-Type: application/json" \
  -H "xi-api-key: ${ELEVEN_LABS_API_KEY}" \
  -d "$PAYLOAD" \
  -o "$TMPFILE"

if [[ -f "$TMPFILE" ]] && [[ $(stat -f%z "$TMPFILE" 2>/dev/null || echo 0) -gt 1000 ]]; then
    FASTFILE=$(mktemp /tmp/meeting_announce_fast_XXXXXXXX)
    mv "$FASTFILE" "${FASTFILE}.mp3"
    FASTFILE="${FASTFILE}.mp3"
    ffmpeg -i "$TMPFILE" -filter:a "atempo=1.3" -y -loglevel error "$FASTFILE" && afplay "$FASTFILE"
    rm -f "$FASTFILE"
    log "Announcement played for: $next_title"
else
    log "TTS generation failed for: $next_title"
fi

rm -f "$TMPFILE"

# Mark this meeting as announced
echo "$key" >> "$STATE"
