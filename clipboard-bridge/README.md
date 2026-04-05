# Clipboard Bridge for Wayland VMs

Bidirectional clipboard sharing between a Wayland host and a Wayland VM guest over the network. Works with Hyprland, Sway, and any Wayland compositor.

## Why?

SPICE clipboard sharing doesn't work with Wayland compositors — it only supports X11. This bridge uses `wl-copy`/`wl-paste` on both sides with a simple TCP connection.

## How it works

```
Host                          VM
wl-paste --watch ──TCP:5556──► wl-copy    (host → VM)
wl-copy  ◄──────TCP:5557───── wl-paste --watch  (VM → host)
```

Both sides watch for clipboard changes and send them to the other.

## Setup

### Host (one-time)

1. Install the libvirt hook for automatic start/stop:
   ```sh
   sudo mkdir -p /etc/libvirt/hooks
   sudo cp qemu-hook.sh /etc/libvirt/hooks/qemu
   sudo chmod +x /etc/libvirt/hooks/qemu
   sudo systemctl restart libvirtd  # or: sudo rc-service libvirtd restart
   ```

2. Copy `cb-host.sh` somewhere in your PATH:
   ```sh
   cp cb-host.sh ~/.local/bin/
   ```

### VM Guest (one-time)

1. Copy `cb-guest.sh` to the VM and place in PATH:
   ```sh
   cp cb-guest.sh ~/.local/bin/
   ```

2. Add to Hyprland autostart:
   ```
   exec-once = cb-guest.sh
   ```

### Manual usage (without hooks)

```sh
# On host — start bridge for VM at 192.168.122.xxx
cb-host.sh 192.168.122.xxx

# On VM — start bridge (host is always 192.168.122.1)
cb-guest.sh
```

## Ports

| Port | Direction | Purpose |
|------|-----------|---------|
| 5556 | Host → VM | Host clipboard pushed to VM |
| 5557 | VM → Host | VM clipboard pushed to host |

## Requirements

Both host and VM need: `wl-clipboard`, `socat`
