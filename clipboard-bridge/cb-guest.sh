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

# Host → VM: listen for clipboard data, deduplicate
(
    last=""
    socat -d0 TCP-LISTEN:$PORT_FROM_HOST,reuseaddr,fork STDOUT | while IFS= read -r line; do
        [ "$line" = "$last" ] && continue
        [ -z "$line" ] && continue
        last="$line"
        echo "$line" | wl-copy
    done
) &
PID_RECV=$!

# VM → Host: watch clipboard, send only non-empty changes
sleep 1
(
    last=""
    wl-paste --watch sh -c '
        data=$(wl-paste 2>/dev/null)
        [ -n "$data" ] && echo "$data"
    ' | while IFS= read -r line; do
        [ "$line" = "$last" ] && continue
        [ -z "$line" ] && continue
        last="$line"
        echo "$line" | socat - TCP:$HOST_IP:$PORT_TO_HOST 2>/dev/null
    done
) &
PID_SEND=$!

wait
