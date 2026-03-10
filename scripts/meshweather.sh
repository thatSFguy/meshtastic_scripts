#!/bin/bash

# ########################################
# DEBIAN TRIXIE COMPATIBLE VERSION - REVISED
# ########################################

set -Eeuo pipefail

# ########################################
# CONFIG
# ########################################

API_URL="https://api.weather.gov/gridpoints/GRR/38,56/forecast/hourly"
CHANNEL_INDEX=0
BYTE_LIMIT=150
MSG_PAUSE=5
LOG_FILE="$HOME/logs/meshweather.log"
LOG_MAX_SIZE=$((1024 * 1024))

VENV="$HOME/mesh-env/bin/activate"
MAX_RETRIES=3
INITIAL_RETRY_DELAY=5

# ########################################
# LOGGING SETUP
# ########################################

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local timestamp
    timestamp=$(date '+%F %T')
    echo "[$timestamp] $*" | tee -a "$LOG_FILE" >&2
}

failure_handler() {
    local lineno=$1
    local msg=$2
    log "CRITICAL FAILURE at line $lineno: $msg"
    exit 1
}
trap 'failure_handler ${LINENO} "$BASH_COMMAND"' ERR

rotate_log() {
    if [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE") -ge $LOG_MAX_SIZE ]]; then
        mv "$LOG_FILE" "$LOG_FILE.1"
        : > "$LOG_FILE"
        log "Log rotated."
    fi
}

# ########################################
# ENV
# ########################################

log "Checking environment..."
if [[ -f "$VENV" ]]; then
    # shellcheck disable=SC1091
    source "$VENV" || { log "Failed to source $VENV"; exit 1; }
else
    log "Virtual env not found: $VENV."
    exit 1
fi

# ########################################
# UTF-8 Helpers
# ########################################

sanitize_utf8() {
    printf "%s" "$1" | iconv -f UTF-8 -t UTF-8 -c
}

# ########################################
# Emoji Helpers - Priority Based
# ########################################

forecast_to_emoji() {
    local f="${1,,}"

    # Priority logic: returns only the most relevant single emoji
    if [[ $f == *thunder* ]]; then
        echo "⛈️"
    elif [[ $f == *snow* || $f == *ice* || $f == *freezing* ]]; then
        echo "❄️"
    elif [[ $f == *rain* || $f == *shower* ]]; then
        echo "🌧️"
    elif [[ $f == *cloud* || $f == *overcast* ]]; then
        echo "☁️"
    elif [[ $f == *sun* || $f == *clear* || $f == *sunny* ]]; then
        echo "☀️"
    else
        echo "🌡️"
    fi
}

# ########################################
# FETCH WEATHER WITH RETRIES
# ########################################

fetch_weather() {
    local attempt=1
    while (( attempt <= MAX_RETRIES )); do
        log "Fetching weather (Attempt $attempt/$MAX_RETRIES)..."
        TMP_JSON=$(mktemp)
        HTTP_CODE=$(curl -fsS --connect-timeout 10 --max-time 20 \
            -A "MeshWeatherBot/1.0 (RPI Trixie)" \
            -w "%{http_code}" "$API_URL" -o "$TMP_JSON" || echo "000")

        if [[ "$HTTP_CODE" == "200" ]] && jq -e '.properties.periods' "$TMP_JSON" >/dev/null 2>&1; then
            PERIODS=$(jq -c '.properties.periods' "$TMP_JSON")
            rm -f "$TMP_JSON"
            return 0
        fi

        log "API Error or Empty Data (HTTP $HTTP_CODE). Retrying..."
        rm -f "$TMP_JSON"
        ((attempt++))
        sleep $((INITIAL_RETRY_DELAY * attempt))
    done
    return 1
}

# ########################################
# 4-HOUR BLOCK FORECAST
# ########################################

build_4hr_blocks() {
    local label="$1"
    log "Building $label forecast blocks..."
    local msg="$label:"
    local block_hours=(0 4 8 12 16 20)

    for hr in "${block_hours[@]}"; do
        # Format hour to 2 digits (e.g., 4 becomes 04)
        printf -v search_hr "%02d" "$hr"

        # Select the FIRST period matching this hour (closest to now)
        # Prevents averaging across multiple days
        BLOCK=$(jq -c --arg hr "$search_hr" '
            [ .[] | select(.startTime | contains("T" + $hr + ":00:")) ] | .[0]
        ' <<<"$PERIODS")

        if [[ "$BLOCK" == "null" || -z "$BLOCK" ]]; then
            continue
        fi

        temp=$(jq -r '.temperature' <<<"$BLOCK")
        pred=$(jq -r '.shortForecast' <<<"$BLOCK")
        icon=$(forecast_to_emoji "$pred")

        msg+=" ${hr}h:${temp}°${icon}|"
    done
    sanitize_utf8 "$msg"
}

# ########################################
# SPLIT & SEND
# ########################################

split_message() {
    local text="$1"
    local limit="$2"
    local chunks=() current="" bytes=0

    IFS='|' read -ra PARTS <<<"$text"
    for part in "${PARTS[@]}"; do
        [[ -z "$part" ]] && continue
        part=$(sanitize_utf8 "$part")
        part_bytes=$(printf "%s" "$part" | LC_ALL=C wc -c)

        if (( bytes + part_bytes + 1 <= limit )); then
            [[ -n "$current" ]] && current+="|"
            current+="$part"
            bytes=$((bytes + part_bytes + 1))
        else
            [[ -n "$current" ]] && chunks+=("$current")
            current="$part"
            bytes=$part_bytes
        fi
    done
    [[ -n "$current" ]] && chunks+=("$current")
    printf "%s\n" "${chunks[@]}"
}

send_message() {
    local raw="$1"
    mapfile -t chunks < <(split_message "$raw" "$BYTE_LIMIT")

    for msg in "${chunks[@]}"; do
        log "Sending to Mesh: $msg"
        if meshtastic --host localhost --ch-index "$CHANNEL_INDEX" --sendtext "$msg" >>"$LOG_FILE" 2>&1; then
            log "Sent successfully."
        else
            log "WARNING: Meshtastic send failed."
        fi
        sleep "$MSG_PAUSE"
    done
}

# ########################################
# MAIN
# ########################################

rotate_log
log "=== meshweather start ==="

for cmd in jq curl meshtastic iconv; do
    command -v "$cmd" >/dev/null || { log "Missing $cmd"; exit 1; }
done

if fetch_weather; then
    HOUR=$(date +%H)
    HOUR=$((10#$HOUR))

    # If morning, show Today. If afternoon/night, show Tomorrow.
    if (( HOUR >= 4 && HOUR < 12 )); then
        MESSAGE=$(build_4hr_blocks "Today")
    else
        MESSAGE=$(build_4hr_blocks "Next24h")
    fi

    if [[ -n "$MESSAGE" && "$MESSAGE" != *":" ]]; then
        send_message "$MESSAGE"
    else
        log "ERROR: Message was empty."
    fi
else
    log "CRITICAL: Could not fetch weather data."
    exit 1
fi

log "=== meshweather complete ==="
