# Clipboard Bridge for Wayland VMs

Bidirectional clipboard sharing between a Wayland host and a Wayland VM guest via SSH. Works with Hyprland, Sway, and any Wayland compositor.

## Why?

SPICE clipboard sharing doesn't work with Wayland compositors — it only supports X11. This bridge uses SSH to poll and sync clipboards using `wl-copy`/`wl-paste` on both sides.

## How it works

```
Host                              VM
wl-paste → ssh vm wl-copy         (host → VM)
wl-copy  ← ssh vm wl-paste        (VM → host)
```

A single script runs on the host, polling both clipboards every 300ms via SSH.

## Setup

### VM Guest (one-time)

```sh
sudo pacman -S openssh-openrc wl-clipboard
sudo rc-update add sshd default
sudo rc-service sshd start
```

### Host (one-time)

```sh
# Copy SSH key to VM (so bridge doesn't ask for password)
ssh-copy-id user@192.168.122.xxx

# Copy bridge script to PATH
cp cb-host.sh ~/.local/bin/
```

### Run

```sh
# On host only — no script needed on VM
cb-host.sh user@192.168.122.xxx
```

### Auto-start with libvirt hook

```sh
sudo mkdir -p /etc/libvirt/hooks
sudo cp qemu-hook.sh /etc/libvirt/hooks/qemu
sudo chmod +x /etc/libvirt/hooks/qemu
sudo rc-service libvirtd restart
```

Edit `qemu-hook.sh` to set your VM username and add VM names to the case statement.

## Requirements

- **Host**: `wl-clipboard`, `openssh`
- **VM**: `openssh`, `wl-clipboard`, sshd running
