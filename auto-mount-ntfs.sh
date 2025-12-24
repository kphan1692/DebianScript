#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Detecting NTFS partitions..."
echo

lsblk -f | grep -i ntfs || {
  echo "❌ No NTFS partitions found."
  exit 1
}

echo
read -rp "Enter NTFS device (example: /dev/sda1): " DEVICE

if ! blkid "$DEVICE" | grep -qi 'TYPE="ntfs"'; then
  echo "❌ Invalid NTFS device (not TYPE=ntfs)."
  exit 1
fi

UUID=$(blkid -s UUID -o value "$DEVICE")
echo "✅ UUID detected: $UUID"

# If already mounted (e.g. by devmon), unmount first or exit cleanly
MOUNTED_TARGET="$(findmnt -rn -S "$DEVICE" -o TARGET 2>/dev/null || true)"
if [[ -n "${MOUNTED_TARGET}" ]]; then
  echo
  echo "⚠️ $DEVICE is already mounted at: $MOUNTED_TARGET"
  read -rp "Unmount it now so we can mount via /etc/fstab? [y/N]: " ANS
  if [[ "${ANS}" =~ ^[Yy]$ ]]; then
    sudo umount "$MOUNTED_TARGET" || sudo udisksctl unmount -b "$DEVICE"
  else
    echo "❌ Aborting without changing /etc/fstab."
    exit 1
  fi
fi

read -rp "Enter mount point (default: /mnt/ntfsdrive): " MOUNTPOINT
MOUNTPOINT=${MOUNTPOINT:-/mnt/ntfsdrive}

USERNAME=${SUDO_USER:-$(whoami)}
UID_NUM=$(id -u "$USERNAME")
GID_NUM=$(id -g "$USERNAME")

echo
echo "📁 Creating mount point: $MOUNTPOINT"
sudo mkdir -p "$MOUNTPOINT"

echo
echo "📦 Installing ntfs-3g (if needed)..."
sudo apt update -y
sudo apt install -y ntfs-3g

echo
echo "🛡️ Backing up /etc/fstab..."
BACKUP="/etc/fstab.backup.$(date +%F_%H%M%S)"
sudo cp /etc/fstab "$BACKUP"

# If anything fails after this point, restore fstab
trap 'echo "❌ Error occurred. Restoring /etc/fstab from '"$BACKUP"'"; sudo cp "'"$BACKUP"'" /etc/fstab; sudo systemctl daemon-reload || true' ERR

FSTAB_ENTRY="UUID=$UUID  $MOUNTPOINT  ntfs-3g  defaults,nofail,uid=$UID_NUM,gid=$GID_NUM,umask=022  0  0"

if sudo grep -q "$UUID" /etc/fstab; then
  echo "⚠️ An entry with this UUID already exists in /etc/fstab. Not adding another."
else
  echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab >/dev/null
  echo "✅ Added fstab entry:"
  echo "$FSTAB_ENTRY"
fi

# systemd caches fstab; reload so we don't get the "old version" hint
sudo systemctl daemon-reload || true

echo
echo "🔄 Testing mount (only $MOUNTPOINT)..."
sudo mount "$MOUNTPOINT"

# Success: disable the restore trap
trap - ERR

echo
echo "✅ Mount successful!"
echo "📂 NTFS drive should now be available at: $MOUNTPOINT"
