
#!/usr/bin/env bash
set -euo pipefail

SWAPFILE="/workspace/swapfile"
SWAPSIZE="32G"
SWAPDIR="$(dirname "$SWAPFILE")"

# Require root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Please run with: sudo bash setup_swap.sh"
    exit 1
fi

# Verify the data volume is mounted and suitable for swap
if [[ ! -d "$SWAPDIR" ]]; then
    echo "ERROR: $SWAPDIR does not exist."
    exit 1
fi

MOUNT=$(findmnt -n -o TARGET -T "$SWAPDIR")
FSTYPE=$(findmnt -n -o FSTYPE -T "$SWAPDIR")

if [[ "$MOUNT" == "/" ]]; then
    echo "ERROR: /workspace appears to be on the root filesystem."
    echo "Mount the data volume before continuing."
    exit 1
fi

if [[ "$FSTYPE" != "ext4" && "$FSTYPE" != "xfs" ]]; then
    echo "ERROR: Unsupported filesystem: $FSTYPE"
    exit 1
fi

echo "Using $MOUNT ($FSTYPE)"

# Create swap only if it doesn't already exist
if [[ ! -e "$SWAPFILE" ]]; then
    echo "Creating $SWAPSIZE swap file..."

    AVAILABLE=$(df -B1 --output=avail "$SWAPDIR" | tail -1)
    REQUIRED=$((32 * 1024 * 1024 * 1024))

    if (( AVAILABLE < REQUIRED )); then
        echo "ERROR: Insufficient disk space."
        exit 1
    fi

    fallocate -l "$SWAPSIZE" "$SWAPFILE"
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE"
else
    echo "Existing swap file found."

    if [[ ! -f "$SWAPFILE" || -L "$SWAPFILE" ]]; then
        echo "ERROR: Swap path is not a regular file."
        exit 1
    fi

    # Verify existing file if not already active
    if ! swapon --show=NAME --noheadings | grep -Fxq "$SWAPFILE"; then
        TYPE=$(blkid -p -o value -s TYPE "$SWAPFILE" 2>/dev/null || true)
        if [[ "$TYPE" != "swap" ]]; then
            echo "ERROR: Existing file is not initialized as swap."
            exit 1
        fi
    fi
fi

chmod 600 "$SWAPFILE"

# Activate swap if necessary
if ! swapon --show=NAME --noheadings | grep -Fxq "$SWAPFILE"; then
    echo "Activating swap..."
    swapon "$SWAPFILE"
else
    echo "Swap is already active."
fi

# Persist across reboots without duplicating entries
if ! awk -v p="$SWAPFILE" '$1 == p {found=1} END {exit !found}' /etc/fstab; then
    cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d-%H%M%S)"
    echo "$SWAPFILE none swap sw,nofail 0 0" >> /etc/fstab
    echo "Added swap to /etc/fstab."
else
    echo "Swap entry already exists in /etc/fstab."
fi

systemctl daemon-reload

echo ""
echo "=== Swap configuration ==="
swapon --show

echo ""
echo "=== Memory summary ==="
free -h

echo ""
echo "Swap configuration complete."

