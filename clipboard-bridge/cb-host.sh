#!/bin/bash
# Clipboard bridge — HOST side
# Sends host clipboard to VM, receives VM clipboard
#
# Usage: cb-host.sh <vm-ip>
# Example: cb-host.sh 192.168.122.100

VM_IP="${1:?Usage: cb-host.sh <vm-ip>}"
PORT_TO_VM=5556    # host → VM
PORT_FROM_VM=5557  # VM → host

cleanup() {
    kill $PID_SEND $PID_RECV 2>/dev/null
    echo "clipboard bridge stopped"
}
trap cleanup EXIT

echo "clipboard bridge: host ↔ $VM_IP"

LAST_SENT=""
LAST_RECV=""

# Host → VM: poll clipboard every 250ms, send if changed
(
    while true; do
        data=$(wl-paste --no-newline 2>/dev/null) || true
        if [ -n "$data" ] && [ "$data" != "$LAST_SENT" ] && [ "$data" != "$LAST_RECV" ]; then
            LAST_SENT="$data"
            printf '%s' "$data" | socat -d0 - TCP:$VM_IP:$PORT_TO_VM 2>/dev/null && true
        fi
        sleep 0.25
    done
) &
PID_SEND=$!

# VM → Host: listen for clipboard data from VM
(
    while true; do
        data=$(socat -d0 TCP-LISTEN:$PORT_FROM_VM,bind=192.168.122.1,reuseaddr - 2>/dev/null)
        if [ -n "$data" ] && [ "$data" != "$LAST_RECV" ]; then
            LAST_RECV="$data"
            printf '%s' "$data" | wl-copy
        fi
    done
) &
PID_RECV=$!

echo "  host→vm on :$PORT_TO_VM  vm→host on :$PORT_FROM_VM"
echo "  pid $PID_SEND (send) $PID_RECV (recv)"
wait
