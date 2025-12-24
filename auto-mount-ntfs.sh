#!/usr/bin/env bash
set -e

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
sudo cp /etc/fstab "/etc/fstab.backup.$(date +%F_%H%M%S)"

FSTAB_ENTRY="UUID=$UUID  $MOUNTPOINT  ntfs-3g  defaults,nofail,uid=$UID_NUM,gid=$GID_NUM,umask=022  0  0"

if sudo grep -q "$UUID" /etc/fstab; then
  echo "⚠️ An entry with this UUID already exists in /etc/fstab. Not adding another."
else
  echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab >/dev/null
  echo "✅ Added fstab entry:"
  echo "$FSTAB_ENTRY"
fi

echo
echo "🔄 Testing mount (mount -a)..."
sudo mount -a

echo
echo "✅ Mount successful!"
echo "📂 NTFS drive should now be available at: $MOUNTPOINT"
echo
echo "Tip: Reboot to confirm it auto-mounts at boot:"
echo "sudo reboot"
