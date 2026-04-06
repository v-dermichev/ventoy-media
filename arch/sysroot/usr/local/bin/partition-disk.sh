#!/bin/bash
# Artix Linux partition helper
# 1) Opens cfdisk for manual partitioning
# 2) Detects or creates EFI partition
# 3) Asks which partitions to use
# 4) Formats and mounts them

set -e

# cfdisk and fdisk may return non-zero on quit
run_cfdisk() { cfdisk "$@" || true; }

# Auto-partition: EFI (512M) + Root (rest)
auto_partition_full() {
    local dev="$1"

    echo "Creating: EFI (512MB) + Root (remaining)"
    {
        echo g
        echo n; echo 1; echo ""; echo "+512M"
        echo n; echo 2; echo ""; echo ""
        echo t; echo 1; echo 1
        echo w
    } | fdisk "$dev" >/dev/null 2>&1 || true

    sleep 1
    blockdev --rereadpt "$dev" 2>/dev/null || true
    sleep 1

    if [[ "${dev##*/}" == nvme* || "${dev##*/}" == mmcblk* ]]; then
        local p="${dev}p"
    else
        local p="${dev}"
    fi

    echo "Formatting..."
    mkfs.fat -F32 "${p}1"
    mkfs.ext4 -F "${p}2"

    AUTO_EFI="${p}1"
    AUTO_ROOT="${p}2"
    echo "✓ Auto-partitioned: EFI=${p}1 Root=${p}2"
}

# Auto-partition remaining free space: Root after existing EFI
auto_partition_remaining() {
    local dev="$1"

    echo "Creating: Root (all remaining space)"
    {
        echo n; echo ""; echo ""; echo ""
        echo w
    } | fdisk "$dev" >/dev/null 2>&1 || true

    sleep 1
    blockdev --rereadpt "$dev" 2>/dev/null || true
    sleep 1

    local existing=$(fdisk -l "$dev" 2>/dev/null | grep "^${dev}" | wc -l)
    if [[ "${dev##*/}" == nvme* || "${dev##*/}" == mmcblk* ]]; then
        local root_part="${dev}p${existing}"
    else
        local root_part="${dev}${existing}"
    fi

    echo "Formatting..."
    mkfs.ext4 -F "$root_part"

    AUTO_EFI=$(find_efi "$dev" 2>/dev/null) || true
    AUTO_ROOT="$root_part"
    echo "✓ Auto-partitioned: Root=$root_part"
}

# Detect EFI partition on a disk
find_efi() {
    local disk="$1"
    while IFS= read -r part; do
        [ -z "$part" ] && continue
        local dev="/dev/$part"
        # Check GPT partition type UUID
        local ptype=$(blkid -o value -s PART_ENTRY_TYPE "$dev" 2>/dev/null)
        if [ "$ptype" = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]; then
            echo "$dev"; return 0
        fi
        # Fallback: first vfat partition under 1GB is likely EFI
        local fstype=$(blkid -o value -s TYPE "$dev" 2>/dev/null)
        local size=$(lsblk -bno SIZE "$dev" 2>/dev/null | head -1)
        if [ "$fstype" = "vfat" ] && [ -n "$size" ] && [ "$size" -le 1073741824 ] 2>/dev/null; then
            echo "$dev"; return 0
        fi
    done < <(lsblk -nro NAME "$disk" 2>/dev/null | tail -n +2)
    return 1
}

echo "==================================="
echo "  Artix Linux Disk Partitioner"
echo "==================================="
echo ""

# List and select disk
if command -v fzf >/dev/null 2>&1; then
    DISK=$(lsblk -dno NAME,SIZE,MODEL | fzf --prompt="Select disk (Esc to skip): " --header="Available disks:" | awk '{print $1}')
    [ -z "$DISK" ] && DISK="skip"
else
    echo "Available disks:"
    lsblk -dno NAME,SIZE,MODEL | while read -r name size model; do
        echo "  /dev/$name — $size $model"
    done
    echo ""
    read -p "Select disk for cfdisk (e.g. sda, nvme0n1), or 'skip' if already partitioned: " DISK
fi

if [ "$DISK" != "skip" ]; then
    if [ ! -b "/dev/$DISK" ]; then
        echo "Error: /dev/$DISK not found"
        exit 1
    fi

    EFI_DEV=$(find_efi "/dev/$DISK" 2>/dev/null) || true

    # Determine partition suffix
    if [[ "$DISK" == nvme* || "$DISK" == mmcblk* ]]; then
        P="/dev/${DISK}p"
    else
        P="/dev/${DISK}"
    fi

    if [ -n "$EFI_DEV" ]; then
        echo "Found existing EFI partition: $EFI_DEV"
        echo ""
        echo "Options:"
        echo "  1) Auto-partition remaining space (Swap + Root)"
        echo "  2) Open cfdisk (manual)"
        echo "  3) Skip partitioning"
        read -p "Choice [1/2/3]: " part_choice
        case "$part_choice" in
            1) auto_partition_remaining "/dev/$DISK" ;;
            2) run_cfdisk "/dev/$DISK" ;;
            3) echo "Skipping" ;;
        esac
    else
        echo ""
        echo "⚠  No EFI partition found on /dev/$DISK"
        echo ""
        echo "Options:"
        echo "  1) Auto-partition entire disk (EFI + Swap + Root)"
        echo "  2) Create EFI only, then open cfdisk"
        echo "  3) Open cfdisk (fully manual)"
        echo "  4) Skip — EFI partition is on another disk"
        read -p "Choice [1/2/3/4]: " efi_choice

        case "$efi_choice" in
            1)
                echo ""
                echo "⚠  This will ERASE ALL DATA on /dev/$DISK"
                read -p "Type 'yes' to continue: " confirm
                if [ "$confirm" = "yes" ]; then
                    auto_partition_full "/dev/$DISK"
                fi
                ;;
            2)
                echo ""
                echo "⚠  This will create a new GPT partition table on /dev/$DISK"
                echo "   ALL EXISTING PARTITIONS WILL BE LOST"
                read -p "Type 'yes' to continue: " confirm
                if [ "$confirm" = "yes" ]; then
                    echo -e "g\nn\n1\n\n+512M\nt\n1\nw" | fdisk "/dev/$DISK" >/dev/null 2>&1 || true
                    sleep 1
                    blockdev --rereadpt "/dev/$DISK" 2>/dev/null || true
                    sleep 1
                    mkfs.fat -F32 "${P}1"
                    echo "✓ EFI partition created (${P}1)"
                    echo ""
                    echo "Opening cfdisk to create remaining partitions..."
                    sleep 1
                fi
                run_cfdisk "/dev/$DISK"
                ;;
            3)
                run_cfdisk "/dev/$DISK"
                ;;
            4)
                echo "Skipping — make sure EFI partition exists on another disk"
                ;;
        esac
    fi
fi

# Re-read partition tables
if [ "$DISK" != "skip" ] && [ -b "/dev/$DISK" ]; then
    blockdev --rereadpt "/dev/$DISK" 2>/dev/null || true
    sleep 1
fi

# Show all partitions
echo ""
echo "Current partitions:"
echo "==================="
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL,MOUNTPOINT
echo ""

if [ -n "$AUTO_ROOT" ] && [ -n "$AUTO_EFI" ]; then
    # Auto-partitioned — skip manual selection, go straight to mount
    ROOT_PART="$AUTO_ROOT"
    EFI_PART="$AUTO_EFI"
    SWAP_PART="none"
    echo "Auto-detected: Root=$ROOT_PART EFI=$EFI_PART"
else
    # Manual selection
    EFI_AUTO=""
    if [ "$DISK" != "skip" ] && [ -b "/dev/$DISK" ]; then
        EFI_AUTO=$(find_efi "/dev/$DISK" 2>/dev/null) || true
    fi

    read -p "Root partition (e.g. /dev/vda3, /dev/sda3): " ROOT_PART

    if [ -n "$EFI_AUTO" ]; then
        read -p "EFI partition [$EFI_AUTO]: " EFI_PART
        EFI_PART="${EFI_PART:-$EFI_AUTO}"
    else
        read -p "EFI partition (e.g. /dev/vda1, or 'none'): " EFI_PART
    fi

    read -p "Swap partition (e.g. /dev/vda2, or 'none'): " SWAP_PART

    # Validate root
    if [ ! -b "$ROOT_PART" ]; then
        echo "Error: $ROOT_PART not found"
        exit 1
    fi

    # Format root
    read -p "Format root ($ROOT_PART) as ext4? [Y/n]: " fmt_root
    if [ "$fmt_root" != "n" ]; then
        mkfs.ext4 -F "$ROOT_PART"
    fi

    if [ "$EFI_PART" != "none" ] && [ -n "$EFI_PART" ] && [ -b "$EFI_PART" ]; then
        FSTYPE=$(blkid -o value -s TYPE "$EFI_PART" 2>/dev/null)
        if [ "$FSTYPE" = "vfat" ]; then
            read -p "EFI ($EFI_PART) already FAT32. Reformat? [y/N]: " fmt_efi
        else
            read -p "Format EFI ($EFI_PART) as FAT32? [Y/n]: " fmt_efi
            [ "$fmt_efi" != "n" ] && fmt_efi="y"
        fi
        [ "$fmt_efi" = "y" ] && mkfs.fat -F32 "$EFI_PART"
    fi

    if [ "$SWAP_PART" != "none" ] && [ -n "$SWAP_PART" ] && [ -b "$SWAP_PART" ]; then
        mkswap "$SWAP_PART"
    fi
fi

# Confirm
echo ""
echo "Summary:"
echo "  Root: $ROOT_PART"
[ "$EFI_PART" != "none" ] && [ -n "$EFI_PART" ] && echo "  EFI:  $EFI_PART"
[ "$SWAP_PART" != "none" ] && [ -n "$SWAP_PART" ] && echo "  Swap: $SWAP_PART"
echo ""
read -p "Proceed with mounting? [Y/n]: " proceed
[ "$proceed" = "n" ] && exit 0

# Mount
mount "$ROOT_PART" /mnt

if [ "$EFI_PART" != "none" ] && [ -n "$EFI_PART" ] && [ -b "$EFI_PART" ]; then
    mkdir -p /mnt/boot/efi
    mount "$EFI_PART" /mnt/boot/efi
fi

[ "$SWAP_PART" != "none" ] && [ -n "$SWAP_PART" ] && [ -b "$SWAP_PART" ] && swapon "$SWAP_PART"

echo ""
echo "✓ Mounted and ready:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -E "NAME|mnt|SWAP"
echo ""
echo "Next: run install-system"
