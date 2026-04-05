#!/bin/bash
# Libvirt QEMU hook — auto-start/stop clipboard bridge
# Install: sudo cp qemu-hook.sh /etc/libvirt/hooks/qemu && sudo chmod +x /etc/libvirt/hooks/qemu
#
# Hook arguments: $1=VM_name $2=action $3=sub-action

VM_NAME="$1"
ACTION="$2"

BRIDGE_SCRIPT="$HOME/.local/bin/cb-host.sh"
PID_DIR="/tmp/clipboard-bridge"
VM_USER="test"  # change to your VM username

# Only act on VMs we care about — add VM names here
case "$VM_NAME" in
    artix-main|ventoy-poc) ;;
    *) exit 0 ;;
esac

case "$ACTION" in
    started)
        mkdir -p "$PID_DIR"
        sleep 10  # wait for VM to boot and get IP

        VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '192\.168\.122\.[0-9]+')
        if [ -n "$VM_IP" ] && [ -x "$BRIDGE_SCRIPT" ]; then
            WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
            XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
            nohup "$BRIDGE_SCRIPT" "$VM_USER@$VM_IP" > "$PID_DIR/$VM_NAME.log" 2>&1 &
            echo $! > "$PID_DIR/$VM_NAME.pid"
        fi
        ;;
    stopped)
        if [ -f "$PID_DIR/$VM_NAME.pid" ]; then
            kill $(cat "$PID_DIR/$VM_NAME.pid") 2>/dev/null
            rm -f "$PID_DIR/$VM_NAME.pid"
        fi
        ;;
esac
