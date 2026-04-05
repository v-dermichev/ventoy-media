#!/bin/bash
# Clipboard bridge — VM GUEST side
# Receives host clipboard, sends VM clipboard to host
#
# Usage: cb-guest.sh [host-ip]
# Default host IP: 192.168.122.1 (libvirt default gateway)

HOST_IP="${1:-192.168.122.1}"
PORT_FROM_HOST=5556  # host → VM (we listen)
PORT_TO_HOST=5557    # VM → host (we send)

cleanup() {
    kill $PID_RECV $PID_SEND 2>/dev/null
}
trap cleanup EXIT

LAST_SENT=""
LAST_RECV=""

# Host → VM: listen for clipboard data from host
(
    while true; do
        data=$(socat -d0 TCP-LISTEN:$PORT_FROM_HOST,reuseaddr - 2>/dev/null)
        if [ -n "$data" ] && [ "$data" != "$LAST_RECV" ]; then
            LAST_RECV="$data"
            printf '%s' "$data" | wl-copy
        fi
    done
) &
PID_RECV=$!

# VM → Host: poll clipboard every 250ms, send if changed
sleep 1
(
    while true; do
        data=$(wl-paste --no-newline 2>/dev/null) || true
        if [ -n "$data" ] && [ "$data" != "$LAST_SENT" ] && [ "$data" != "$LAST_RECV" ]; then
            LAST_SENT="$data"
            printf '%s' "$data" | socat -d0 - TCP:$HOST_IP:$PORT_TO_HOST 2>/dev/null && true
        fi
        sleep 0.25
    done
) &
PID_SEND=$!

wait
