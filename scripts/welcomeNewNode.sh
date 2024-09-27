#!/bin/bash

# Path to meshtastic (update your path to meshtastic)
MPATH="/home/XXXX/my-venv/bin/meshtastic"
# Define a file to store the new nodes
OUTPUT_FILE="new_nodes.csv"
# Define a file to keep track of known node IDs
KNOWN_NODES_FILE="known_nodes.txt"

# Create the output files if they do not exist
touch "$OUTPUT_FILE"
touch "$KNOWN_NODES_FILE"

# Get the current list of nodes
CURRENT_NODES=$("$MPATH" --host localhost --nodes)

# Parse the output and extract ID and LastHeard information
echo "$CURRENT_NODES" | awk -F '│' 'NR>5 && NF>=15 {gsub(/^[ \t]+|[ \t]+$/, "", $3); gsub(/^[ \t]+|[ \t]+$/, "", $4); gsub(/^[ \t]+|[ \t]+$/, "", $17); print $4 "," $17}' | while IFS=',' read -r NODE_ID LAST_HEARD; do
    # Check if this node ID is already known
    if ! grep -q "$NODE_ID" "$KNOWN_NODES_FILE"; then
        # If it's a new node, log it and send a welcome message
        echo "$NODE_ID,$LAST_HEARD" >> "$OUTPUT_FILE"
        echo "$NODE_ID" >> "$KNOWN_NODES_FILE"
        
        # Send a welcome message
        "$MPATH" --host localhost --dest "$NODE_ID" --sendtext "Welcome to the Mesh from Sparta, MI" --ack
    fi
done
