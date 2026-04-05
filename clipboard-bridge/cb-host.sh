#!/bin/bash
# Clipboard bridge — HOST side
# Sends host clipboard to VM, receives VM clipboard via SSH
#
# Usage: cb-host.sh <user@vm-ip>
# Example: cb-host.sh test@192.168.122.100
#
# Requires: SSH access to VM (key-based auth recommended)

VM="${1:?Usage: cb-host.sh user@vm-ip}"
# Detect VM's WAYLAND_DISPLAY (default wayland-1 for Hyprland)
VM_WL="${2:-wayland-1}"
SSH_OPTS="-o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new"
WL="WAYLAND_DISPLAY=$VM_WL"

STATE="/tmp/cb-bridge-host"
mkdir -p "$STATE"

cleanup() { kill $(jobs -p) 2>/dev/null; rm -rf "$STATE"; echo "stopped"; }
trap cleanup EXIT

echo "clipboard bridge: host ↔ $VM (via SSH)"

# Host → VM: poll clipboard, send if changed
(
    while true; do
        wl-paste 2>/dev/null > "$STATE/cur"
        if [ -s "$STATE/cur" ] && \
           ! cmp -s "$STATE/cur" "$STATE/sent" 2>/dev/null && \
           ! cmp -s "$STATE/cur" "$STATE/recv" 2>/dev/null; then
            cp "$STATE/cur" "$STATE/sent"
            ssh $SSH_OPTS "$VM" "$WL wl-copy" < "$STATE/cur" 2>/dev/null || true
        fi
        sleep 0.3
    done
) &

# VM → Host: poll VM clipboard via SSH, copy if changed
(
    while true; do
        ssh $SSH_OPTS "$VM" "$WL wl-paste 2>/dev/null" > "$STATE/remote" 2>/dev/null
        if [ -s "$STATE/remote" ] && \
           ! cmp -s "$STATE/remote" "$STATE/recv" 2>/dev/null && \
           ! cmp -s "$STATE/remote" "$STATE/sent" 2>/dev/null; then
            cp "$STATE/remote" "$STATE/recv"
            wl-copy < "$STATE/recv"
        fi
        sleep 0.3
    done
) &

echo "  polling every 300ms"
wait
