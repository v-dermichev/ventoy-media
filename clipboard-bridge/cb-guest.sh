#!/bin/bash
# Clipboard bridge — VM GUEST side
# Receives host clipboard, sends VM clipboard to host
#
# Usage: cb-guest.sh [host-ip]
# Default host IP: 192.168.122.1 (libvirt default gateway)

HOST_IP="${1:-192.168.122.1}"
PORT_FROM_HOST=5556  # host → VM (we listen)
PORT_TO_HOST=5557    # VM → host (we send)

STATE_DIR="/tmp/clipboard-bridge-guest"
mkdir -p "$STATE_DIR"

cleanup() {
    kill $(jobs -p) 2>/dev/null
    rm -rf "$STATE_DIR"
}
trap cleanup EXIT

# Host → VM: listen for clipboard data
(
    while true; do
        socat -d0 TCP-LISTEN:$PORT_FROM_HOST,reuseaddr - 2>/dev/null > "$STATE_DIR/raw_incoming"
        if [ -s "$STATE_DIR/raw_incoming" ]; then
            tail -c +11 "$STATE_DIR/raw_incoming" > "$STATE_DIR/incoming"
            if [ -s "$STATE_DIR/incoming" ]; then
                if ! cmp -s "$STATE_DIR/incoming" "$STATE_DIR/last_recv" 2>/dev/null; then
                    cp "$STATE_DIR/incoming" "$STATE_DIR/last_recv"
                    wl-copy < "$STATE_DIR/incoming"
                fi
            fi
        fi
    done
) &

# VM → Host: poll clipboard, send if changed
sleep 1
(
    while true; do
        wl-paste 2>/dev/null > "$STATE_DIR/current"
        if [ -s "$STATE_DIR/current" ]; then
            if ! cmp -s "$STATE_DIR/current" "$STATE_DIR/last_sent" 2>/dev/null; then
                if ! cmp -s "$STATE_DIR/current" "$STATE_DIR/last_recv" 2>/dev/null; then
                    cp "$STATE_DIR/current" "$STATE_DIR/last_sent"
                    len=$(wc -c < "$STATE_DIR/current")
                    { printf '%010d' "$len"; cat "$STATE_DIR/current"; } | \
                        socat -d0 - TCP:$HOST_IP:$PORT_TO_HOST 2>/dev/null || true
                fi
            fi
        fi
        sleep 0.3
    done
) &

wait
