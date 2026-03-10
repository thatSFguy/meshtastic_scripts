#!/bin/bash

# Activate the Python virtual environment
source ~/mesh-env/bin/activate

# === CONFIGURATION ===
START_MESSAGE="WMI nightly system test. Messages <= 50 chars will be ack for the next 5 min."
END_MESSAGE="This completes the nightly system check. Thanks for your participation!"
LOG_FILE="$HOME/meshtastic_logs/nightly_$(date '+%Y-%m-%d_%H-%M-%S').log"
LISTEN_DURATION=300  # in seconds (5 minutes)

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# === SEND START MESSAGE ===
echo "[*] Sending system check start message..."
meshtastic --ch-index 1 --sendtext "$START_MESSAGE"

# === LISTEN AND LOG RESPONSES ===
echo "[*] Listening for $((LISTEN_DURATION/60)) minutes and logging responses to:"
echo "    $LOG_FILE"
timeout "$LISTEN_DURATION" meshtastic --ch-index 1 --reply 2>&1 | tee "$LOG_FILE"

# === SEND END MESSAGE ===
echo "[*] Sending system check end message..."
meshtastic --ch-index 1 --sendtext "$END_MESSAGE"

echo "[✓] Nightly system check complete. Log saved to:"
echo "    $LOG_FILE"
