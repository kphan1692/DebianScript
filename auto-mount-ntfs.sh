#!/usr/bin/env bash
set -euo pipefail

echo "Detecting NTFS partitions..."
lsblk -f | grep -i ntfs || { echo "❌ No NTFS partitions found."; exit 1; }

read -rp "Enter NTFS device (example: /dev/sda1): " DEVICE
if ! blkid "$DEVICE" | grep -qi 'TYPE="ntfs"'; then
  echo "❌ Invalid NTFS device (not TYPE=ntfs)."
  exit 1
fi

UUID="$(blkid -s UUID -o value "$DEVICE")"
echo "✅ UUID detected: $UUID"

# If already mounted, offer to unmount first
MOUNTED_TARGET="$(findmnt -rn -S "$DEVICE" -o TARGET 2>/dev/null || true)"
if [[ -n "${MOUNTED_TARGET}" ]]; then
  echo "⚠️ $DEVICE is already mounted at: $MOUNTED_TARGET"
  read -rp "Unmount it now so we can mount via /etc/fstab? [y/N]: " ANS
  if [[ "${ANS}" =~ ^[Yy]$ ]]; then
    umount "$MOUNTED_TARGET" 2>/dev/null || udisksctl unmount -b "$DEVICE" || true
  else
    echo "❌ Aborting without changing /etc/fstab."
    exit 1
  fi
fi

read -rp "Enter mount point (default: /mnt/ntfsdrive): " MOUNTPOINT
MOUNTPOINT="${MOUNTPOINT:-/mnt/ntfsdrive}"

USERNAME="${SUDO_USER:-$(whoami)}"
UID_NUM="$(id -u "$USERNAME")"
GID_NUM="$(id -g "$USERNAME")"

echo "Creating mount point: $MOUNTPOINT"
mkdir -p "$MOUNTPOINT"

echo "Installing ntfs-3g (if needed)..."
apt-get update -y
apt-get install -y ntfs-3g

echo "Backing up /etc/fstab..."
BACKUP="/etc/fstab.backup.$(date +%F_%H%M%S)"
cp /etc/fstab "$BACKUP"

trap 'echo "❌ Error occurred. Restoring /etc/fstab from '"$BACKUP"'"; cp "'"$BACKUP"'" /etc/fstab; systemctl daemon-reload || true' ERR

FSTAB_ENTRY="UUID=$UUID $MOUNTPOINT ntfs-3g defaults,nofail,uid=$UID_NUM,gid=$GID_NUM,umask=022 0 0"

if grep -q "$UUID" /etc/fstab; then
  echo "⚠️ An entry with this UUID already exists in /etc/fstab. Not adding another."
else
  echo "$FSTAB_ENTRY" >> /etc/fstab
  echo "✅ Added fstab entry:"
  echo "$FSTAB_ENTRY"
fi

systemctl daemon-reload || true

echo "Testing mount (only $MOUNTPOINT)..."
mount "$MOUNTPOINT"

trap - ERR
echo "✅ Mount successful!"
echo "NTFS drive should now be available at: $MOUNTPOINT"
