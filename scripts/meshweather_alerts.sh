#!/bin/bash

# Activate virtual environment
source ~/mesh-env/bin/activate

# Config
# Replace with your lat,long
ALERT_API="https://api.weather.gov/alerts/active?point=41.9634,-84.6681"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/meshweather_alerts.log"
SENT_HASHES_FILE="$LOG_DIR/meshweather_sent_alerts.txt"
CHAR_LIMIT=130
MESHTASTIC_RETRIES=3
MESHTASTIC_RETRY_DELAY=2

# --- Ensure log dir exists ---
mkdir -p "$LOG_DIR"
touch "$LOG_FILE" "$SENT_HASHES_FILE"

# --- Logging ---
log_msg() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"; }

# --- Check Meshtastic ---
if ! command -v meshtastic >/dev/null 2>&1; then
    log_error "Meshtastic CLI not found"
    exit 1
fi
if ! meshtastic --host localhost --info >/dev/null 2>&1; then
    log_error "Cannot connect to Meshtastic device"
    exit 1
fi

# --- Fetch alerts ---
ALERTS_JSON=$(curl -s --fail --connect-timeout 10 --max-time 20 "$ALERT_API")
if [ $? -ne 0 ] || [ -z "$ALERTS_JSON" ]; then
    log_error "Failed to fetch alerts"
    exit 1
fi

# --- Extract alert IDs ---
ALERT_IDS=$(echo "$ALERTS_JSON" | jq -r '.features[].id')

# --- Helper to format time ---
short_time() {
    local t="$1"
    if [ "$t" == "null" ] || [ -z "$t" ]; then
        echo ""
    else
        date -d "$t" "+%m/%d %H:%M" 2>/dev/null || echo "$t"
    fi
}

# --- Process Alerts ---
for ALERT_ID in $ALERT_IDS; do
    FEATURE=$(echo "$ALERTS_JSON" | jq -r ".features[] | select(.id==\"$ALERT_ID\")")

    TITLE=$(echo "$FEATURE" | jq -r ".properties.event")
    SEV=$(echo "$FEATURE" | jq -r ".properties.severity")
    DESC=$(echo "$FEATURE" | jq -r ".properties.description")
    START=$(echo "$FEATURE" | jq -r ".properties.onset")

    # Check 'ends' first, then fallback to 'expires' (common for SWS)
    END=$(echo "$FEATURE" | jq -r ".properties.ends")
    if [ "$END" == "null" ]; then
        END=$(echo "$FEATURE" | jq -r ".properties.expires")
    fi

    # --- Extract WHAT section or Fallback ---
    # Attempt to grab the "WHAT" bullet point first
    WHAT=$(echo "$DESC" | sed -n '/\* WHAT/,/\*/p' | sed 's/\* WHAT//;s/\*//g' | tr -d '\n' | sed 's/  */ /g' | xargs)

    # Fallback: if WHAT is empty, take the first 80 characters of the main description
    if [ -z "$WHAT" ]; then
        WHAT=$(echo "$DESC" | tr -d '\n' | sed 's/  */ /g' | cut -c1-80 | xargs)
        WHAT="${WHAT}..."
    fi

    START_FMT=$(short_time "$START")
    END_FMT=$(short_time "$END")
    [ -z "$END_FMT" ] && END_FMT="Term"

    # Map severity to emoji
    case "$SEV" in
        Extreme)  SEV_EMOJI="🚨" ;;
        Severe)   SEV_EMOJI="⚠️" ;;
        Moderate) SEV_EMOJI="❗" ;;
        Minor)    SEV_EMOJI="ℹ️" ;;
        *)        SEV_EMOJI="🌡️" ;;
    esac

    # Construct and truncate message
    MSG="$SEV_EMOJI $TITLE ($START_FMT-$END_FMT): $WHAT"
    MSG=$(echo "$MSG" | cut -c1-$CHAR_LIMIT)

    # --- Compute hash ---
    MSG_HASH=$(echo -n "$MSG" | sha1sum | awk '{print $1}')

    # --- Check if this message was already sent ---
    if grep -q "$MSG_HASH" "$SENT_HASHES_FILE"; then
        log_msg "Alert already sent (content identical). ID: $ALERT_ID"
        continue
    fi

    # --- Send via Meshtastic ---
    ATTEMPT=1
    SUCCESS=0
    while [ $ATTEMPT -le $MESHTASTIC_RETRIES ]; do
        OUTPUT=$(meshtastic --host localhost --ch-index 0 --sendtext "$MSG" 2>&1)
        if [ $? -eq 0 ] && ! echo "$OUTPUT" | grep -qi "error\|failed\|timeout"; then
            log_msg "Alert sent: $MSG"
            SUCCESS=1
            break
        fi
        log_msg "Send attempt $ATTEMPT failed: $OUTPUT"
        ((ATTEMPT++))
        sleep $MESHTASTIC_RETRY_DELAY
    done

    # --- Log hash if successful ---
    if [ $SUCCESS -eq 1 ]; then
        echo "$MSG_HASH $ALERT_ID" >> "$SENT_HASHES_FILE"
    fi
done
