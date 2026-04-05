#!/bin/bash
# Libvirt QEMU hook — auto-start/stop clipboard bridge
# Install: sudo cp qemu-hook.sh /etc/libvirt/hooks/qemu && sudo chmod +x /etc/libvirt/hooks/qemu
#
# Hook arguments: $1=VM_name $2=action $3=sub-action
# Actions: prepare/start/started/stopped/release

VM_NAME="$1"
ACTION="$2"

BRIDGE_SCRIPT="$HOME/.local/bin/cb-host.sh"
PID_DIR="/tmp/clipboard-bridge"

# Only act on VMs we care about — add VM names here
case "$VM_NAME" in
    artix-main|ventoy-poc) ;;
    *) exit 0 ;;
esac

case "$ACTION" in
    started)
        # VM just started — find its IP and launch bridge
        mkdir -p "$PID_DIR"
        sleep 5  # wait for VM to get an IP

        VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '192\.168\.122\.[0-9]+')
        if [ -n "$VM_IP" ] && [ -x "$BRIDGE_SCRIPT" ]; then
            WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
            XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
            nohup "$BRIDGE_SCRIPT" "$VM_IP" > "$PID_DIR/$VM_NAME.log" 2>&1 &
            echo $! > "$PID_DIR/$VM_NAME.pid"
        fi
        ;;
    stopped)
        # VM stopped — kill the bridge
        if [ -f "$PID_DIR/$VM_NAME.pid" ]; then
            kill $(cat "$PID_DIR/$VM_NAME.pid") 2>/dev/null
            rm -f "$PID_DIR/$VM_NAME.pid"
        fi
        ;;
esac
