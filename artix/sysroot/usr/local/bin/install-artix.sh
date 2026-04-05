#!/bin/bash
# Artix Linux install script — systemd-free Hyprland desktop
# Run AFTER partition-disk.sh (expects /mnt mounted with root + EFI)
#
# Prerequisites:
#   - Internet connection (run wifi-connect.sh if needed)
#   - Partitions mounted at /mnt (run partition-disk.sh)

set -e
trap 'echo "ERROR: script failed at line $LINENO (exit code $?)"' ERR

echo "==================================="
echo "  Artix Linux Installer"
echo "==================================="
echo ""

# Verify mounts
if ! mountpoint -q /mnt; then
    echo "Error: /mnt not mounted. Run partition-disk.sh first."
    exit 1
fi

if ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    echo "Error: No internet. Run wifi-connect.sh first."
    exit 1
fi

# Optimize pacman: parallel downloads + ensure multiple mirrors
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
if [ "$(grep -c '^Server' /etc/pacman.d/mirrorlist)" -lt 3 ]; then
    cat >> /etc/pacman.d/mirrorlist <<'MIRRORS'
Server = https://mirror.pascalroeleven.nl/artixlinux/repos/$repo/os/$arch
Server = https://mirrors.dotsrc.org/artix-linux/repos/$repo/os/$arch
Server = https://ftp.ludd.ltu.se/mirrors/artix-linux/repos/$repo/os/$arch
MIRRORS
fi

# User setup
read -p "Username: " USERNAME
read -p "Hostname: " HOSTNAME
read -sp "Password: " PASSWORD
echo ""
read -sp "Confirm password: " PASSWORD2
echo ""

if [ -z "$PASSWORD" ]; then
    echo "Password cannot be empty"
    exit 1
fi

if [ "$PASSWORD" != "$PASSWORD2" ]; then
    echo "Passwords don't match"
    exit 1
fi

# Autologin
read -p "Enable autologin on tty1? [y/N]: " AUTOLOGIN

# Sudo password
read -p "Require password for sudo? [Y/n]: " SUDO_PASSWD

# Timezone
echo ""
if command -v fzf >/dev/null 2>&1; then
    TIMEZONE=$(find /usr/share/zoneinfo -type f ! -path "*/posix/*" ! -path "*/right/*" | sed 's|/usr/share/zoneinfo/||' | sort | fzf --prompt="Select timezone: " --query="Europe/")
    TIMEZONE="${TIMEZONE:-UTC}"
else
    echo "Common timezones: Europe/London, Europe/Berlin, Europe/Moscow, US/Eastern, US/Pacific, Asia/Tokyo"
    read -p "Timezone [UTC]: " TIMEZONE
    TIMEZONE="${TIMEZONE:-UTC}"
fi
if [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
    echo "Warning: $TIMEZONE not found, using UTC"
    TIMEZONE="UTC"
fi

# Detect hardware
HAS_NVIDIA=false
HAS_INTEL_GPU=false
lspci | grep -qi "nvidia" && HAS_NVIDIA=true
lspci | grep -qi "intel.*graphics\|intel.*UHD\|intel.*iris" && HAS_INTEL_GPU=true

echo ""
echo "Detected hardware:"
$HAS_NVIDIA && echo "  ✓ NVIDIA GPU"
$HAS_INTEL_GPU && echo "  ✓ Intel GPU"
echo ""

# Base packages
echo "Installing base system..."
PACKAGES=(
    # Base
    base linux linux-firmware
    # Init
    openrc elogind-openrc
    # Bootloader
    grub efibootmgr os-prober
    # Filesystem
    dosfstools mtools
    # Network
    networkmanager networkmanager-openrc
    # Essential
    sudo nano git curl wget jq socat
    # Shell
    zsh
)

# VM detection
IS_VM=false
if grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
    IS_VM=true
    echo "  ✓ Virtual machine detected"
    PACKAGES+=(spice-vdagent qemu-guest-agent mesa virglrenderer)
fi

# GPU packages
if $HAS_NVIDIA; then
    PACKAGES+=(nvidia-open-dkms nvidia-utils linux-headers dkms)
fi
if $HAS_INTEL_GPU; then
    PACKAGES+=(mesa intel-media-driver vulkan-intel)
fi

basestrap /mnt "${PACKAGES[@]}" || { echo "ERROR: basestrap failed with exit code $?"; exit 1; }

# Generate fstab
# Generate fstab (only if not already done)
if [ ! -s /mnt/etc/fstab ] || ! grep -q "UUID" /mnt/etc/fstab 2>/dev/null; then
    echo "Generating fstab..."
    fstabgen -U /mnt >> /mnt/etc/fstab
else
    echo "fstab already exists, skipping"
fi

# Chroot phase 1: system configuration
echo "Configuring system..."
mkdir -p /mnt/root
cat > /mnt/root/phase1.sh << PHASE1
#!/bin/bash
set -e

# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Root password
echo "root:$PASSWORD" | chpasswd

# Create user
useradd -m -G wheel,audio,video,input -s /bin/zsh "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
if [ "$SUDO_PASSWD" = "n" ] || [ "$SUDO_PASSWD" = "N" ]; then
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
else
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
fi

# Enable services
rc-update add NetworkManager default
rc-update add elogind default

# Autologin on tty1
if [ "$AUTOLOGIN" = "y" ] || [ "$AUTOLOGIN" = "Y" ]; then
    if [ -f /etc/inittab ]; then
        sed -i 's|^c1:.*agetty.*tty1.*|c1:12345:respawn:/sbin/agetty --autologin $USERNAME --noclear 38400 tty1 linux|' /etc/inittab
    else
        mkdir -p /etc/conf.d
        echo 'agetty_options="--autologin $USERNAME --noclear"' > /etc/conf.d/agetty.tty1
    fi
fi

# GRUB
GRUB_ARGS=""
$HAS_NVIDIA && GRUB_ARGS="nvidia-drm.modeset=1 nvidia_drm.fbdev=1"
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\".*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 \\\$GRUB_ARGS\"/" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Artix
grub-mkconfig -o /boot/grub/grub.cfg

# NVIDIA modprobe
if $HAS_NVIDIA; then
    cat > /etc/modprobe.d/nvidia.conf << EOF
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
    sed -i 's/^MODULES=.*/MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    mkinitcpio -P
fi

# Swap file
RAM_KB=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
# Round up to nearest power of 2 in GB
RAM_GB=\$(( (RAM_KB + 1048575) / 1048576 ))
POW=1
while [ \$POW -lt \$RAM_GB ]; do POW=\$((POW * 2)); done
SWAP_MB=\$((POW * 1024))
echo "Creating \${SWAP_MB}MB (\${POW}GB) swap file..."
dd if=/dev/zero of=/swapfile bs=1M count=\$SWAP_MB status=progress
chmod 600 /swapfile
mkswap /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

echo "Phase 1 complete"
PHASE1
artix-chroot /mnt bash /root/phase1.sh
rm -f /mnt/root/phase1.sh
rm -f /mnt/tmp/phase1.sh

echo ""
echo "Base system installed. Installing desktop environment..."

# Chroot phase 2: desktop packages
cat > /mnt/root/phase2.sh << 'PHASE2'
#!/bin/bash
set -e

# Arch repo support
pacman -S --noconfirm artix-archlinux-support
if ! grep -q '^\[extra\]' /etc/pacman.conf; then
    echo "" >> /etc/pacman.conf
    echo "[extra]" >> /etc/pacman.conf
    echo "Include = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
fi
pacman -Sy

# Desktop environment
pacman -S --noconfirm --needed \
    hyprland waybar wofi awww swaync socat \
    grim slurp swappy hyprshot wf-recorder \
    kitty \
    pipewire pipewire-pulse wireplumber \
    bluez bluez-openrc bluez-utils blueman \
    polkit-gnome gnome-keyring \
    ttf-jetbrains-mono-nerd noto-fonts-emoji \
    qt6-wayland \
    wl-clipboard cliphist \
    brightnessctl network-manager-applet \
    pavucontrol \
    libcanberra sound-theme-freedesktop \
    xdg-utils \
    thunar gvfs udisks2 \
    mission-center \
    yazi ffmpeg p7zip jq poppler fd ripgrep fzf zoxide \
    neovim lazygit \
    base-devel nodejs npm unzip

# awww/swww compatibility (swww was renamed to awww)
ln -sf /usr/bin/awww /usr/local/bin/swww
ln -sf /usr/bin/awww-daemon /usr/local/bin/swww-daemon

# Install wproulette if available on live media
if [ -f /usr/local/bin/wproulette ]; then
    cp /usr/local/bin/wproulette /usr/local/bin/
    chmod +x /usr/local/bin/wproulette
fi

# Bluetooth service
rc-update add bluetoothd default

# Pipewire RT scheduling
mkdir -p /etc/security/limits.d
cat > /etc/security/limits.d/99-audio.conf << EOF
@audio - rtprio 95
@audio - nice -19
@audio - memlock unlimited
EOF

# Disable extra repo (keep artix-archlinux-support for virtual systemd packages)
sed -i 's/^\[extra\]/#[extra]/' /etc/pacman.conf
sed -i '/^#\[extra\]/{n;s/^Include/#Include/}' /etc/pacman.conf

echo "Phase 2 complete"
PHASE2
artix-chroot /mnt bash /root/phase2.sh
rm -f /mnt/root/phase2.sh

# Dotfiles
echo ""
echo "Setting up dotfiles..."
cat > /mnt/var/tmp/setup-dotfiles.sh << 'DOTSCRIPT'
#!/bin/bash
set -e

echo "Installing oh-my-zsh..."
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true

echo "Installing zsh plugins..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" || true
git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" || true
git clone https://github.com/MichaelAqworsk/autoswitch_virtualenv "$ZSH_CUSTOM/plugins/autoswitch_virtualenv" || true

echo "Cloning dotfiles..."
git clone https://github.com/v-dermichev/dotfiles.git ~/.dotfiles-repo
mkdir -p ~/.config
cp -r ~/.dotfiles-repo/.config/* ~/.config/ 2>/dev/null || true
cp ~/.dotfiles-repo/.zshrc ~/ 2>/dev/null || true
cp ~/.dotfiles-repo/.zprofile ~/ 2>/dev/null || true

echo "Setting up default wallpapers..."
mkdir -p ~/Pictures/Wallpapers
cp /usr/share/hypr/* ~/Pictures/Wallpapers/ 2>/dev/null || true

echo "Dotfiles setup complete"
DOTSCRIPT
artix-chroot /mnt su - "$USERNAME" -c "bash /var/tmp/setup-dotfiles.sh"
rm -f /mnt/var/tmp/setup-dotfiles.sh

echo ""
echo "==========================================="
echo "  ✓ Installation complete!"
echo "==========================================="
echo ""
echo "  Hostname: $HOSTNAME"
echo "  User:     $USERNAME"
echo ""
echo "  Next steps:"
echo "  1. Reboot: umount -R /mnt && reboot"
echo "  2. Log in at TTY1 — Hyprland starts automatically"
echo "  3. Connect WiFi: nmtui"
echo ""
$HAS_NVIDIA && echo "  NVIDIA: configured with modesetting + VRAM preservation"
echo ""
