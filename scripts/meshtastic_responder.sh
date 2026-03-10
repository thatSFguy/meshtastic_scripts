#!/bin/bash

# --- CONFIGURATION ---
USER_HOME="/home/$(whoami)"
LOG_DIR="$USER_HOME/logs"
LOGFILE="$LOG_DIR/meshtastic_responder.log"
LAST_SENT_FILE="$LOG_DIR/.last_daily_msg"
VENV="$USER_HOME/mesh-env/bin/activate"
MAX_LOG_SIZE=5242880

# Instructions & Heartbeat
CH0_MSG="Sparta Node: To test, add a public channel named 'Testing' (no key) and send a msg."
HEARTBEAT_MSG="Heartbeat: Responder script is active."

mkdir -p "$LOG_DIR"

# --- HELPER FUNCTIONS ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

# --- ENVIRONMENT SETUP ---
if [[ -f "$VENV" ]]; then
    source "$VENV" || { log "ERROR: Failed to source $VENV"; exit 1; }
else
    log "ERROR: Virtual env not found: $VENV."
    exit 1
fi

# --- DAILY MESSAGES (Heartbeat & Instructions) ---
# Only run if 24 hours (86400 seconds) have passed
current_time=$(date +%s)
last_sent=$(cat "$LAST_SENT_FILE" 2>/dev/null || echo 0)

if (( current_time - last_sent > 86400 )); then
    log "Sending daily heartbeat and instructions..."

    # Send Instructions to Primary Channel (Index 0)
    meshtastic --ch-index 0 --sendtext "$CH0_MSG" >> "$LOGFILE" 2>&1

    # Send Heartbeat to Testing Channel (Index 1)
    meshtastic --ch-index 1 --sendtext "$HEARTBEAT_MSG" >> "$LOGFILE" 2>&1

    echo "$current_time" > "$LAST_SENT_FILE"
    log "Daily messages sent successfully."
fi

# --- PROCESS PERSISTENCE ---
SEARCH_PATTERN="python3 -u -m meshtastic --ch-index 1 --reply"

# Kill any broken/stuck instances first
if pgrep -f "$SEARCH_PATTERN" > /dev/null; then
    if tail -n 20 "$LOGFILE" 2>/dev/null | grep -q "BrokenPipeError"; then
        log "Detected BrokenPipeError — killing stuck responder..."
        pkill -f "$SEARCH_PATTERN"
        sleep 2
    fi
fi

if ! pgrep -f "$SEARCH_PATTERN" > /dev/null; then
    log "Meshtastic responder not running. Starting now..."
    nohup python3 -u -m meshtastic --ch-index 1 --reply >> "$LOGFILE" 2>&1 &

    sleep 2
    if pgrep -f "$SEARCH_PATTERN" > /dev/null; then
        log "Startup successful."
    else
        log "ERROR: Failed to start responder."
    fi
fi
