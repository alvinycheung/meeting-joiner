#!/bin/bash
# Meeting Auto-Joiner — opens Zoom/Google Meet/MS Teams links before meetings start

DIR="$HOME/.claude/meeting-joiner"
STATE="$DIR/opened.txt"
LOG="$DIR/joiner.log"
CACHE="$DIR/events-cache.txt"
ICALBUDDY="${ICALBUDDY_PATH:-/opt/homebrew/bin/icalBuddy}"
CACHE_MAX_AGE="${CACHE_MAX_AGE:-300}"  # refresh icalBuddy cache every 5 min
LEAD_TIME="${LEAD_TIME:-2}"  # minutes before meeting to open link

mkdir -p "$DIR"
touch "$STATE"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

# Trim log to last 500 lines (only occasionally)
if [[ -f "$LOG" ]] && [[ $(( RANDOM % 60 )) -eq 0 ]] && [[ $(wc -l < "$LOG") -gt 500 ]]; then
    tail -200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# Clean state — keep only today
today=$(date +%Y-%m-%d)
grep "^${today}|" "$STATE" > "$STATE.tmp" 2>/dev/null || true
mv "$STATE.tmp" "$STATE" 2>/dev/null

# Only call icalBuddy if cache is stale or missing (expensive operation)
refresh_cache=false
if [[ ! -f "$CACHE" ]]; then
    refresh_cache=true
elif [[ $(( $(date +%s) - $(stat -f %m "$CACHE") )) -gt $CACHE_MAX_AGE ]]; then
    refresh_cache=true
fi

if $refresh_cache; then
    "$ICALBUDDY" -ea -nc -nrd -tf "%H:%M" -df "%Y-%m-%d" \
        -iep "title,datetime,notes,location" \
        eventsToday > "$CACHE" 2>/dev/null
fi

# Read from cache (cat for bash 3.2 compatibility)
output=$(cat "$CACHE" 2>/dev/null)
[[ -z "$output" ]] && exit 0

# Current time in minutes since midnight
now_mins=$(( $(date +%-H) * 60 + $(date +%-M) ))

process_event() {
    local title="$1"
    local block="$2"

    [[ -z "$block" ]] && return

    # Extract start time from "HH:MM - HH:MM" line
    local start_time
    start_time=$(echo "$block" | grep -oE '[0-9]{1,2}:[0-9]{2} - [0-9]{1,2}:[0-9]{2}' | head -1 | cut -d' ' -f1)
    [[ -z "$start_time" ]] && return

    local start_h="${start_time%%:*}"
    local start_m="${start_time##*:}"
    local start_mins=$(( 10#$start_h * 60 + 10#$start_m ))

    # Only act if meeting starts within the lead time window
    local diff=$((start_mins - now_mins))
    [[ $diff -lt 0 || $diff -gt $LEAD_TIME ]] && return

    # Extract Zoom URL
    local url
    url=$(echo "$block" | grep -oE 'https://[a-z0-9]+\.zoom\.us/j/[0-9]+\?pwd=[A-Za-z0-9._%-]+' | head -1)

    # Fall back to Google Meet URL
    [[ -z "$url" ]] && url=$(echo "$block" | grep -oE 'https://meet\.google\.com/[a-z]+-[a-z]+-[a-z]+' | head -1)

    # Fall back to MS Teams URL
    [[ -z "$url" ]] && url=$(echo "$block" | grep -oE 'https://teams\.microsoft\.com/l/meetup-join/[^ ")<>]+' | head -1)

    [[ -z "$url" ]] && return

    local key="${today}|${url}"
    if ! grep -qF "$key" "$STATE"; then
        log "Opening: ${title} -> ${url}"
        open "$url"
        echo "$key" >> "$STATE"
    fi
}

# Parse cached output — each event starts with bullet "• "
current_title=""
current_block=""

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "• "* ]]; then
        process_event "$current_title" "$current_block"
        current_title="${line#• }"
        current_block=""
    else
        current_block+="$line"$'\n'
    fi
done <<< "$output"

# Process last event
process_event "$current_title" "$current_block"
