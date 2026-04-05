#!/bin/bash
# Clipboard bridge — HOST side
# Sends host clipboard to VM, receives VM clipboard via SSH
#
# Usage: cb-host.sh <user@vm-ip> [wayland-display]
# Example: cb-host.sh test@192.168.122.100
#
# Requires: SSH key-based auth to VM, wl-clipboard on both sides

VM="${1:?Usage: cb-host.sh user@vm-ip [wayland-display]}"
VM_WL="${2:-wayland-1}"
SSH="ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new -o BatchMode=yes"

STATE="/tmp/cb-bridge-host"
rm -rf "$STATE"
mkdir -p "$STATE"

cleanup() { kill $(jobs -p) 2>/dev/null; rm -rf "$STATE"; echo "stopped"; }
trap cleanup EXIT

echo "clipboard bridge: host ↔ $VM (WAYLAND_DISPLAY=$VM_WL)"

# Host → VM: poll clipboard, send if changed
(
    while true; do
        wl-paste 2>/dev/null > "$STATE/cur"
        if [ -s "$STATE/cur" ] && \
           ! cmp -s "$STATE/cur" "$STATE/sent" 2>/dev/null && \
           ! cmp -s "$STATE/cur" "$STATE/recv" 2>/dev/null; then
            cp "$STATE/cur" "$STATE/sent"
            data=$(base64 -w0 < "$STATE/cur")
            # ssh -f backgrounds the remote wl-copy (it stays alive to serve pastes)
            ssh -f -o BatchMode=yes -o ConnectTimeout=2 "$VM" "echo '$data' | base64 -d | WAYLAND_DISPLAY=$VM_WL wl-copy" 2>/dev/null || true
        fi
        sleep 0.3
    done
) &

# VM → Host: poll VM clipboard via SSH, copy if changed
(
    while true; do
        $SSH "$VM" "WAYLAND_DISPLAY=$VM_WL wl-paste 2>/dev/null | base64" </dev/null 2>/dev/null > "$STATE/remote_b64"
        if [ -s "$STATE/remote_b64" ]; then
            base64 -d < "$STATE/remote_b64" > "$STATE/remote" 2>/dev/null
            if [ -s "$STATE/remote" ] && \
               ! cmp -s "$STATE/remote" "$STATE/recv" 2>/dev/null && \
               ! cmp -s "$STATE/remote" "$STATE/sent" 2>/dev/null; then
                cp "$STATE/remote" "$STATE/recv"
                wl-copy < "$STATE/recv"
            fi
        fi
        sleep 0.3
    done
) &

echo "  polling every 300ms"
wait
