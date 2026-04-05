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

# Host → VM: listen for clipboard data from host
socat TCP-LISTEN:$PORT_FROM_HOST,reuseaddr,fork EXEC:"wl-copy" &
PID_RECV=$!

# VM → Host: watch VM clipboard, send changes to host
sleep 1  # wait for listener to start
wl-paste --watch socat - TCP:$HOST_IP:$PORT_TO_HOST &
PID_SEND=$!

wait
