#!/bin/bash
# Simple WiFi connection helper for Artix installer
# Uses connmanctl (available on Artix base ISO)

set -e

echo "Scanning for WiFi networks..."
connmanctl enable wifi 2>/dev/null
connmanctl scan wifi 2>/dev/null
sleep 2

echo ""
echo "Available networks:"
echo "==================="

# Parse and display networks
SERVICES=$(connmanctl services 2>/dev/null | grep wifi_)
if [ -z "$SERVICES" ]; then
    echo "No WiFi networks found. Make sure WiFi is enabled."
    exit 1
fi

# Number the networks
i=1
declare -a SERVICE_IDS
while IFS= read -r line; do
    NAME=$(echo "$line" | sed 's/\*A[ORSC] //' | sed 's/  *wifi_.*//')
    ID=$(echo "$line" | grep -oP 'wifi_\S+')
    echo "  $i) $NAME"
    SERVICE_IDS[$i]="$ID"
    ((i++))
done <<< "$SERVICES"

echo ""
read -p "Select network (1-$((i-1))): " choice

if [ -z "${SERVICE_IDS[$choice]}" ]; then
    echo "Invalid selection"
    exit 1
fi

SELECTED="${SERVICE_IDS[$choice]}"
echo ""
echo "Connecting to $SELECTED..."
connmanctl connect "$SELECTED"

echo ""
echo "Checking connection..."
sleep 2
if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    echo "✓ Connected successfully!"
else
    echo "✗ Connection failed. Try again or check password."
fi
