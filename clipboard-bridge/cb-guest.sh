#!/bin/bash
# Clipboard bridge — VM GUEST side
# Receives host clipboard, sends VM clipboard to host
#
# Usage: cb-guest.sh [host-ip]
# Default host IP: 192.168.122.1 (libvirt default gateway)

HOST_IP="${1:-192.168.122.1}"
PORT_FROM_HOST=5556  # host → VM (we listen)
PORT_TO_HOST=5557    # VM → host (we send)

STATE="/tmp/cb-bridge-guest"
mkdir -p "$STATE"

cleanup() { kill $(jobs -p) 2>/dev/null; rm -rf "$STATE"; }
trap cleanup EXIT

# Host → VM: listen for incoming clipboard
(
    while true; do
        nc -l -p "$PORT_FROM_HOST" > "$STATE/inc" 2>/dev/null
        if [ -s "$STATE/inc" ] && ! cmp -s "$STATE/inc" "$STATE/recv" 2>/dev/null; then
            cp "$STATE/inc" "$STATE/recv"
            wl-copy < "$STATE/inc"
        fi
    done
) &

# VM → Host: poll clipboard, send if changed
sleep 1
(
    while true; do
        wl-paste 2>/dev/null > "$STATE/cur"
        if [ -s "$STATE/cur" ] && \
           ! cmp -s "$STATE/cur" "$STATE/sent" 2>/dev/null && \
           ! cmp -s "$STATE/cur" "$STATE/recv" 2>/dev/null; then
            cp "$STATE/cur" "$STATE/sent"
            nc -q0 -w1 "$HOST_IP" "$PORT_TO_HOST" < "$STATE/cur" 2>/dev/null || true
        fi
        sleep 0.3
    done
) &

wait
