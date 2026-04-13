#!/bin/bash
# Arch Linux install script — systemd + Hyprland desktop
# Mirror of install-artix.sh, adapted for Arch/systemd.
#
# Prerequisites:
#   - Internet connection (run wifi-connect.sh if needed)
#   - Partitions mounted at /mnt (run partition-disk.sh)

set -e
trap 'echo "ERROR: script failed at line $LINENO (exit code $?)"' ERR

echo "==================================="
echo "  Arch Linux Installer"
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

# Optimize pacman
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf

# Refresh mirrorlist with reflector if available
if command -v reflector >/dev/null 2>&1; then
    echo "Refreshing mirrorlist..."
    reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || true
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

# SDDM autologin
read -p "Enable SDDM autologin? [y/N]: " AUTOLOGIN

# Sudo password
read -p "Require password for sudo? [Y/n]: " SUDO_PASSWD

# Additional compositors (Hyprland is installed by default)
echo ""
echo "Additional Wayland compositors to install alongside Hyprland:"
echo "  1) sway"
echo "  2) plasma (KDE)"
echo "  3) gnome"
echo "  4) all of the above"
echo "  5) none"
read -p "Choice [1/2/3/4/5]: " EXTRA_WM

# AUR helper
echo ""
echo "AUR (Arch User Repository) is a community archive of build scripts"
echo "for apps not available in official repos (e.g. Brave, Zen Browser, Obsidian)."
echo ""
echo "  1) yay   — Go-based, most popular"
echo "  2) paru  — Rust-based, feature-rich"
echo "  3) skip"
read -p "Install AUR helper? [1/2/3]: " AUR_HELPER

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
    # Bootloader
    grub efibootmgr os-prober
    # Filesystem
    dosfstools mtools exfat-utils
    # Network
    networkmanager
    # Essential
    sudo nano git curl wget jq socat
    # Shell
    zsh
    # Mirror management
    reflector
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

pacstrap /mnt "${PACKAGES[@]}" || { echo "ERROR: pacstrap failed with exit code $?"; exit 1; }

# Generate fstab
if [ ! -s /mnt/etc/fstab ] || ! grep -q "UUID" /mnt/etc/fstab 2>/dev/null; then
    echo "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
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
systemctl enable NetworkManager

# GRUB
GRUB_ARGS=""
$HAS_NVIDIA && GRUB_ARGS="nvidia-drm.modeset=1 nvidia_drm.fbdev=1"
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\".*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 \\\$GRUB_ARGS\"/" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch
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
arch-chroot /mnt bash /root/phase1.sh
rm -f /mnt/root/phase1.sh

echo ""
echo "Base system installed. Installing desktop environment..."

# Chroot phase 2: desktop packages
cat > /mnt/root/phase2.sh << PHASE2
#!/bin/bash
set -e

# Desktop environment — Hyprland + SDDM
pacman -S --noconfirm --needed \\
    hyprland waybar wofi awww swaync socat \\
    grim slurp swappy hyprshot wf-recorder \\
    kitty \\
    pipewire pipewire-pulse wireplumber \\
    bluez bluez-utils blueman \\
    polkit-gnome gnome-keyring \\
    ttf-jetbrains-mono-nerd noto-fonts-emoji \\
    qt6-wayland \\
    wl-clipboard cliphist \\
    brightnessctl network-manager-applet \\
    pavucontrol \\
    libcanberra sound-theme-freedesktop \\
    xdg-utils \\
    thunar gvfs udisks2 \\
    mission-center \\
    yazi ffmpeg p7zip jq poppler fd ripgrep fzf zoxide \\
    neovim lazygit \\
    base-devel nodejs npm unzip \\
    sddm

# Additional compositors
case "$EXTRA_WM" in
    1) pacman -S --noconfirm --needed sway swaybg swaylock swayidle ;;
    2) pacman -S --noconfirm --needed plasma-meta konsole dolphin ;;
    3) pacman -S --noconfirm --needed gnome-shell gnome-session gnome-terminal gnome-control-center ;;
    4) pacman -S --noconfirm --needed \\
        sway swaybg swaylock swayidle \\
        plasma-meta konsole dolphin \\
        gnome-shell gnome-session gnome-terminal gnome-control-center ;;
esac

# Services
systemctl enable bluetooth
systemctl enable sddm

# SDDM autologin
if [ "$AUTOLOGIN" = "y" ] || [ "$AUTOLOGIN" = "Y" ]; then
    mkdir -p /etc/sddm.conf.d
    cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=$USERNAME
Session=hyprland.desktop
EOF
fi

# Pipewire RT scheduling
mkdir -p /etc/security/limits.d
cat > /etc/security/limits.d/99-audio.conf << EOF
@audio - rtprio 95
@audio - nice -19
@audio - memlock unlimited
EOF

echo "Phase 2 complete"
PHASE2
arch-chroot /mnt bash /root/phase2.sh
rm -f /mnt/root/phase2.sh

# Install wproulette if available on live media
if [ -f /usr/local/bin/wproulette ]; then
    cp /usr/local/bin/wproulette /mnt/usr/local/bin/
    chmod +x /mnt/usr/local/bin/wproulette
fi

# Install wayland-vdagent for VM clipboard support
if $IS_VM && [ -f /usr/local/bin/wayland-vdagent ]; then
    cp /usr/local/bin/wayland-vdagent /mnt/usr/local/bin/
    chmod +x /mnt/usr/local/bin/wayland-vdagent
fi

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
arch-chroot /mnt su - "$USERNAME" -c "bash /var/tmp/setup-dotfiles.sh"
rm -f /mnt/var/tmp/setup-dotfiles.sh

# AUR helper
if [ "$AUR_HELPER" = "1" ] || [ "$AUR_HELPER" = "2" ]; then
    if [ "$AUR_HELPER" = "1" ]; then
        AUR_NAME="yay"
        AUR_REPO="https://aur.archlinux.org/yay-bin.git"
    else
        AUR_NAME="paru"
        AUR_REPO="https://aur.archlinux.org/paru-bin.git"
    fi
    echo "Installing $AUR_NAME..."
    cat > /mnt/var/tmp/install-aur.sh << AURSCRIPT
#!/bin/bash
set -e
git clone $AUR_REPO /tmp/$AUR_NAME
cd /tmp/$AUR_NAME
makepkg -si --noconfirm
rm -rf /tmp/$AUR_NAME
AURSCRIPT
    arch-chroot /mnt su - "$USERNAME" -c "bash /var/tmp/install-aur.sh"
    rm -f /mnt/var/tmp/install-aur.sh
fi

# VM: setup spice-vdagentd service and wayland-vdagent user unit
if $IS_VM; then
    echo "Configuring VM clipboard support..."
    # spice-vdagentd ships a systemd unit with the package — just enable it
    arch-chroot /mnt systemctl enable spice-vdagentd.service

    # wayland-vdagent as a systemd user service bound to graphical-session.target
    mkdir -p /mnt/etc/systemd/user
    cat > /mnt/etc/systemd/user/wayland-vdagent.service << 'UNIT'
[Unit]
Description=SPICE clipboard bridge for Wayland
PartOf=graphical-session.target
After=graphical-session.target
Requisite=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wayland-vdagent
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
UNIT
    # Enable globally for all users
    mkdir -p /mnt/etc/systemd/user/graphical-session.target.wants
    ln -sf /etc/systemd/user/wayland-vdagent.service \
        /mnt/etc/systemd/user/graphical-session.target.wants/wayland-vdagent.service
fi

echo ""
echo "==========================================="
echo "  ✓ Installation complete!"
echo "==========================================="
echo ""
echo "  Hostname: $HOSTNAME"
echo "  User:     $USERNAME"
echo ""
echo "  To adjust the installed system before rebooting:"
echo "    arch-chroot /mnt         # chroot as root"
echo "    arch-chroot /mnt su - $USERNAME  # chroot as user"
echo ""
echo "  To reboot:"
echo "    umount -R /mnt && reboot"
echo ""
echo "  After reboot:"
echo "    SDDM greets you — pick Hyprland (or another session) and log in"
echo "    Connect WiFi: nmtui  (or from NetworkManager applet)"
echo ""
$HAS_NVIDIA && echo "  NVIDIA: configured with modesetting + VRAM preservation"
echo ""
