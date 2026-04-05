#!/bin/bash
# Clipboard bridge — HOST side
# Sends host clipboard to VM, receives VM clipboard
#
# Usage: cb-host.sh <vm-ip>
# Example: cb-host.sh 192.168.122.100

VM_IP="${1:?Usage: cb-host.sh <vm-ip>}"
PORT_TO_VM=5556    # host → VM
PORT_FROM_VM=5557  # VM → host
BIND_IP="192.168.122.1"

STATE="/tmp/cb-bridge-host"
mkdir -p "$STATE"

cleanup() { kill $(jobs -p) 2>/dev/null; rm -rf "$STATE"; echo "stopped"; }
trap cleanup EXIT

echo "clipboard bridge: host ↔ $VM_IP"

# Host → VM: poll clipboard, send if changed
(
    while true; do
        wl-paste 2>/dev/null > "$STATE/cur"
        if [ -s "$STATE/cur" ] && \
           ! cmp -s "$STATE/cur" "$STATE/sent" 2>/dev/null && \
           ! cmp -s "$STATE/cur" "$STATE/recv" 2>/dev/null; then
            cp "$STATE/cur" "$STATE/sent"
            nc -q0 -w1 "$VM_IP" "$PORT_TO_VM" < "$STATE/cur" 2>/dev/null || true
        fi
        sleep 0.3
    done
) &

# VM → Host: listen for incoming clipboard
(
    while true; do
        nc -l -p "$PORT_FROM_VM" -s "$BIND_IP" > "$STATE/inc" 2>/dev/null
        if [ -s "$STATE/inc" ] && ! cmp -s "$STATE/inc" "$STATE/recv" 2>/dev/null; then
            cp "$STATE/inc" "$STATE/recv"
            wl-copy < "$STATE/inc"
        fi
    done
) &

echo "  host→vm :$PORT_TO_VM  vm→host :$PORT_FROM_VM"
wait
