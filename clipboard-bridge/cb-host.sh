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

STATE="/tmp/cb-bridge-host"
rm -rf "$STATE"
mkdir -p "$STATE"
LOG="$STATE/debug.log"

cleanup() { kill $(jobs -p) 2>/dev/null; rm -rf "$STATE"; echo "stopped"; }
trap cleanup EXIT

echo "clipboard bridge: host ↔ $VM (WAYLAND_DISPLAY=$VM_WL)"
echo "log: $LOG"

# Host → VM: poll clipboard, send if changed
(
    while true; do
        wl-paste --no-newline 2>/dev/null > "$STATE/cur"
        if [ -s "$STATE/cur" ]; then
            s1=$(! cmp -s "$STATE/cur" "$STATE/sent" 2>/dev/null && echo 1 || echo 0)
            s2=$(! cmp -s "$STATE/cur" "$STATE/recv" 2>/dev/null && echo 1 || echo 0)
            if [ "$s1" = "1" ] && [ "$s2" = "1" ]; then
                cp "$STATE/cur" "$STATE/sent"
                cp "$STATE/cur" "$STATE/recv"
                data=$(base64 -w0 < "$STATE/cur")
                echo "$(date +%T) SEND: $(head -c 40 $STATE/cur)..." >> "$LOG"
                ssh -f -o BatchMode=yes -o ConnectTimeout=2 "$VM" \
                    "echo '$data' | base64 -d | WAYLAND_DISPLAY=$VM_WL wl-copy" 2>>"$LOG" || true
            fi
        fi
        sleep 0.3
    done
) &

# VM → Host: poll VM clipboard via SSH, copy if changed
(
    while true; do
        ssh -o BatchMode=yes -o ConnectTimeout=2 "$VM" \
            "WAYLAND_DISPLAY=$VM_WL wl-paste --no-newline 2>/dev/null | base64 -w0" </dev/null 2>/dev/null > "$STATE/remote_b64"
        if [ -s "$STATE/remote_b64" ]; then
            base64 -d < "$STATE/remote_b64" > "$STATE/remote" 2>/dev/null
            if [ -s "$STATE/remote" ]; then
                r1=$(! cmp -s "$STATE/remote" "$STATE/recv" 2>/dev/null && echo 1 || echo 0)
                r2=$(! cmp -s "$STATE/remote" "$STATE/sent" 2>/dev/null && echo 1 || echo 0)
                if [ "$r1" = "1" ] && [ "$r2" = "1" ]; then
                    cp "$STATE/remote" "$STATE/recv"
                    cp "$STATE/remote" "$STATE/sent"
                    echo "$(date +%T) RECV: $(head -c 40 $STATE/remote)..." >> "$LOG"
                    wl-copy < "$STATE/recv"
                fi
            fi
        fi
        sleep 0.3
    done
) &

echo "  polling every 300ms"
echo "  tail -f $LOG"
wait
