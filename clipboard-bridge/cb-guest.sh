#!/bin/bash
# Clipboard bridge — VM GUEST side
#
# With the SSH-based bridge, no script is needed on the guest.
# The host polls and pushes clipboard data via SSH.
#
# Prerequisites:
#   1. SSH server running: sudo pacman -S openssh-openrc && sudo rc-update add sshd default && sudo rc-service sshd start
#   2. Key-based auth (from host): ssh-copy-id user@vm-ip
#   3. wl-clipboard installed: sudo pacman -S wl-clipboard
#
# Then run on HOST only:
#   cb-host.sh user@vm-ip

echo "No guest script needed — run cb-host.sh on the host."
echo ""
echo "Setup:"
echo "  1. sudo pacman -S openssh-openrc wl-clipboard"
echo "  2. sudo rc-update add sshd default"
echo "  3. sudo rc-service sshd start"
echo "  4. On host: ssh-copy-id $USER@$(hostname -I | awk '{print $1}')"
echo "  5. On host: cb-host.sh $USER@$(hostname -I | awk '{print $1}')"
