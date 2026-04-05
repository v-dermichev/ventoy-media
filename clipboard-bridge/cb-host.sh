#!/bin/bash
# Clipboard bridge — HOST side
# Sends host clipboard to VM, receives VM clipboard
#
# Usage: cb-host.sh <vm-ip>
# Example: cb-host.sh 192.168.122.100

VM_IP="${1:?Usage: cb-host.sh <vm-ip>}"
PORT_TO_VM=5556    # host → VM
PORT_FROM_VM=5557  # VM → host

STATE_DIR="/tmp/clipboard-bridge-host"
mkdir -p "$STATE_DIR"

cleanup() {
    kill $(jobs -p) 2>/dev/null
    rm -rf "$STATE_DIR"
    echo "clipboard bridge stopped"
}
trap cleanup EXIT

echo "clipboard bridge: host ↔ $VM_IP"

# Host → VM: poll clipboard, send if changed
(
    while true; do
        wl-paste 2>/dev/null > "$STATE_DIR/current"
        if [ -s "$STATE_DIR/current" ]; then
            if ! cmp -s "$STATE_DIR/current" "$STATE_DIR/last_sent" 2>/dev/null; then
                if ! cmp -s "$STATE_DIR/current" "$STATE_DIR/last_recv" 2>/dev/null; then
                    cp "$STATE_DIR/current" "$STATE_DIR/last_sent"
                    cat "$STATE_DIR/current" | socat -d0 -u - TCP:$VM_IP:$PORT_TO_VM 2>/dev/null || true
                fi
            fi
        fi
        sleep 0.3
    done
) &

# VM → Host: listen for clipboard data
(
    while true; do
        socat -d0 -u TCP-LISTEN:$PORT_FROM_VM,bind=192.168.122.1,reuseaddr - > "$STATE_DIR/incoming" 2>/dev/null
        if [ -s "$STATE_DIR/incoming" ]; then
            if ! cmp -s "$STATE_DIR/incoming" "$STATE_DIR/last_recv" 2>/dev/null; then
                cp "$STATE_DIR/incoming" "$STATE_DIR/last_recv"
                wl-copy < "$STATE_DIR/incoming"
            fi
        fi
    done
) &

echo "  host→vm :$PORT_TO_VM  vm→host :$PORT_FROM_VM"
wait
