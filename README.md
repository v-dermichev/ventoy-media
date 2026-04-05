# Ventoy Media

Ventoy-based multi-boot installation USB with automated setup scripts.

## Prerequisites

- USB drive (16GB+ recommended)
- [Ventoy](https://ventoy.net/) installed on the USB (1.0.53+)

## USB Structure

```
USB (Ventoy)/
  ventoy/
    ventoy.json              # Plugin config
  ISO/
    artix-base-openrc/
      artix-base-openrc-*.iso
    archlinux/
      archlinux-*.iso
    windows/
      Win11_*.iso
  Templates/
    autounattend.xml         # Windows unattended install
  sysroot/
    .live_injection.tar.gz   # LiveInjection hooks (generated once)
    etc/profile.d/           # Auto zsh switch + help
    root/                    # .zshrc, .bashrc with aliases
    usr/local/bin/           # Installer scripts + tools
```

## 0. Ventoy Setup

1. Download [Ventoy](https://ventoy.net/en/download.html)
2. Install to USB:
   ```sh
   sudo sh Ventoy2Disk.sh -i /dev/sdX
   ```
3. Copy `ventoy.json` from this repo to `ventoy/ventoy.json` on the USB
4. Copy `artix/sysroot/` to `sysroot/` on the USB
5. Copy `windows/autounattend.xml` to `Templates/autounattend.xml` on the USB
6. Download ISOs and place in `ISO/` subdirectories

## 1. Windows 11

### Download
- [Windows 11 ISO](https://www.microsoft.com/en-us/software-download/windows11) (English International, 64-bit)
- Place at `ISO/windows/Win11_25H2_EnglishInternational_x64.iso`

### Unattended Install
- `Templates/autounattend.xml` bypasses TPM, Secure Boot, and RAM checks
- When booting the ISO, Ventoy offers the unattended template

### Manual Steps After Install
- Install GPU drivers (NVIDIA/AMD)
- Configure dual-boot with Artix (if applicable)

## 2. Artix Linux (systemd-free, Hyprland desktop)

### Download
- [Artix base OpenRC ISO](https://artixlinux.org/download.php) (base-openrc)
- Place at `ISO/artix-base-openrc/artix-base-openrc-*.iso`

### LiveInjection Setup

Scripts are injected into the live environment using [LiveInjection](https://github.com/ventoy/LiveInjection) with live directory mode — the sysroot directory lives directly on the USB. Edit scripts in place, changes take effect on next boot without repacking.

The hooks archive (`.live_injection.tar.gz`) is included in this repo. Just copy `artix/sysroot/` to `sysroot/` on the USB — no additional setup required.

Optionally add static binaries to `sysroot/usr/local/bin/`:
- `fzf` — fuzzy finder (for timezone/disk selection)
- `yazi` — terminal file manager
- `wproulette` — wallpaper roulette ([repo](https://github.com/v-dermichev/swww-wproulette))

> **Regenerating the hooks archive:** Only needed if you change the sysroot path on the USB. Requires the [patched LiveInjection](https://github.com/v-dermichev/LiveInjection/tree/feature/directory-sysroot) fork:
> ```sh
> git clone -b feature/directory-sysroot https://github.com/v-dermichev/LiveInjection.git /tmp/LiveInjection
> cd /tmp/LiveInjection
> sudo sh pack.sh --live /sysroot /mnt/ventoy-usb/sysroot
> ```

### Installation Flow

Boot the Artix ISO from Ventoy. The injected scripts provide:

| Command | Description |
|---------|-------------|
| `partition` | Interactive disk partitioner (auto or manual via cfdisk) |
| `install-system` | Full system installer with Hyprland desktop |
| `wifi` | WiFi connection helper |
| `install-help` | Show available commands |

#### Step by step:
1. Boot Artix ISO from Ventoy menu
2. Connect to internet: `wifi` (or plug in ethernet)
3. Partition disk: `partition`
4. Install system: `install-system`
5. Reboot: `umount -R /mnt && reboot`

#### What gets installed:
- **Base**: Artix OpenRC, linux, GRUB (EFI)
- **Desktop**: Hyprland, waybar, kitty, wofi, swaync
- **GPU**: Auto-detected NVIDIA (open-dkms) / Intel / VM (virtio)
- **Audio**: PipeWire + WirePlumber
- **Tools**: yazi, fzf, ripgrep, neovim, lazygit, zoxide
- **Shell**: zsh + oh-my-zsh with plugins (autosuggestions, syntax-highlighting)
- **Dotfiles**: Cloned from [dotfiles repo](https://github.com/v-dermichev/dotfiles)
- **Wallpapers**: Default Hyprland wallpapers copied to ~/Pictures/Wallpapers

#### Install prompts:
- Username, hostname, password
- Autologin on tty1 (opt-in)
- Sudo password requirement (opt-out)
- Timezone (fzf selector or manual input)

#### After first boot:
- `Super + D` — launch apps (wofi launcher)
- `Super + Enter` — open terminal (kitty)
- Apps can be assigned to named workspaces in `~/.config/hypr/hyprland.conf`:
  ```
  # Example: assign apps to workspaces
  windowrulev2 = workspace 2, class:^(brave-browser)$
  windowrulev2 = workspace 3, class:^(code)$
  windowrulev2 = workspace name:music, class:^(Spotify)$
  ```
- Special workspaces (scratchpads) are toggled with keybinds — check `hyprland.conf` for details

#### Optional packages
The dotfiles expect some apps that are not installed by the script:
```sh
# From Arch extra repo
sudo pacman -S chromium dotnet-sdk
# From AUR (requires yay or paru)
yay -S brave-bin
```
These can be installed later, or their references removed from `~/.config/hypr/hyprland.conf` and `~/.config/waybar/config.jsonc` if not needed.

## 3. Arch Linux

> TODO: Arch-specific installer scripts

## VM Testing

A libvirt VM template is provided at `artix/vm-template.xml` (virtio-gpu with GL + SPICE).

```sh
# Create a 40GB test disk
qemu-img create -f qcow2 /tmp/vm-disk.qcow2 40G

# Import the VM (update disk paths in the XML first)
virsh define artix/vm-template.xml
virsh start artix-main
```

## Notes

- ISOs are NOT included — download them separately
- The `.live_injection.tar.gz` is generated by LiveInjection — do not commit it
- Network backup directory (`Network/`) is optional for preserving WiFi/WG configs across installs
- `awww` (formerly `swww`) is the wallpaper daemon — symlinks for backward compatibility are created during install
