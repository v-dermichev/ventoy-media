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

# Host → VM: watch host clipboard, send changes to VM
wl-paste --watch socat - TCP:$VM_IP:$PORT_TO_VM &
PID_SEND=$!

# VM → Host: listen for clipboard data from VM
socat TCP-LISTEN:$PORT_FROM_VM,bind=192.168.122.1,reuseaddr,fork EXEC:"wl-copy" &
PID_RECV=$!

echo "  host→vm on :$PORT_TO_VM  vm→host on :$PORT_FROM_VM"
echo "  pid $PID_SEND (send) $PID_RECV (recv)"
wait
