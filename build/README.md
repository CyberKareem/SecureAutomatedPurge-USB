# Building Secure Automated Purge USB from Source

This guide explains how to build the Secure Automated Purge USB ISO from source.

## Prerequisites

- Debian 12 (Bookworm) or Ubuntu 22.04 LTS
- At least 4GB RAM
- 10GB free disk space
- Root/sudo access

## Quick Build

```bash
# Clone the repository
git clone https://github.com/cyberkareem/SecureAutomatedPurge-USB.git
cd SecureAutomatedPurge-USB

# Run automated build script
sudo ./build/build_iso.sh
```

## Manual Build Steps

### 1. Install Required Packages

```bash
sudo apt update
sudo apt install -y \
    live-build \
    debootstrap \
    xorriso \
    syslinux-utils \
    mtools \
    isolinux
```

### 2. Create Build Directory

```bash
mkdir ~/sap_usb_build
cd ~/sap_usb_build
```

### 3. Configure Live Build

```bash
lb config \
    --distribution bookworm \
    --architectures amd64 \
    --mode debian \
    --binary-images iso-hybrid \
    --bootappend-live "boot=live components quiet splash" \
    --debian-installer false \
    --apt-recommends false \
    --iso-application "Secure Automated Purge v1.0" \
    --iso-preparer "Abdullah Kareem" \
    --iso-publisher "CyberKareem" \
    --iso-volume "SAP_USB_V1"
```

### 4. Copy Configuration Files

```bash
# Copy from repository to build directory
cp -r /path/to/repo/build/config/* config/
```

### 5. Add Secure Purge Script

```bash
# Create directory
mkdir -p config/includes.chroot/usr/local/bin

# Copy script
cp /path/to/repo/secure_purge.sh config/includes.chroot/usr/local/bin/
chmod +x config/includes.chroot/usr/local/bin/secure_purge.sh
```

### 6. Configure Auto-start

```bash
# Create rc.local
mkdir -p config/includes.chroot/etc
cat > config/includes.chroot/etc/rc.local << 'EOF'
#!/bin/sh
exec < /dev/console > /dev/console 2>&1
clear
/usr/local/bin/secure_purge.sh
exit 0
EOF
chmod +x config/includes.chroot/etc/rc.local
```

### 7. Configure Packages

```bash
# Create package list
cat > config/package-lists/purge.list.chroot << EOF
nvme-cli
hdparm
smartmontools
util-linux
pv
dc3dd
shred
bsdmainutils
EOF
```

### 8. Configure Repositories

```bash
cat > config/archives/live.list.chroot << EOF
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
```

### 9. Create Systemd Service

```bash
mkdir -p config/includes.chroot/etc/systemd/system
cat > config/includes.chroot/etc/systemd/system/rc-local.service << EOF
[Unit]
Description=/etc/rc.local Compatibility
ConditionFileIsExecutable=/etc/rc.local
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/rc.local
TimeoutSec=0
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
```

### 10. Create Hooks

```bash
# Enable rc.local service
mkdir -p config/hooks/normal
cat > config/hooks/normal/01-enable-rc-local.chroot << 'EOF'
#!/bin/sh
set -e
systemctl enable rc-local.service
EOF
chmod +x config/hooks/normal/01-enable-rc-local.chroot

# Disable unnecessary services
cat > config/hooks/normal/02-disable-services.chroot << 'EOF'
#!/bin/sh
set -e
systemctl disable apt-daily.service || true
systemctl disable apt-daily.timer || true
systemctl disable apt-daily-upgrade.timer || true
systemctl disable apt-daily-upgrade.service || true
EOF
chmod +x config/hooks/normal/02-disable-services.chroot
```

### 11. Build the ISO

```bash
# Clean any previous builds
sudo lb clean

# Build bootstrap
sudo lb bootstrap

# Build the ISO
sudo lb build
```

### 12. Output

The ISO will be created as:
- `live-image-amd64.hybrid.iso`

Rename it to something more descriptive:
```bash
mv live-image-amd64.hybrid.iso SecureAutomatedPurge-v1.0.0.iso
```

## Build Script

For convenience, use our automated build script:

```bash
#!/bin/bash
# build_iso.sh - Located in build directory

set -e

echo "Building Secure Automated Purge USB ISO..."

# Your build commands here
# ...

echo "Build complete: SecureAutomatedPurge-v1.0.0.iso"
```

## Troubleshooting

### Common Issues

1. **Permission denied**: Run with sudo
2. **Package not found**: Update package lists with `apt update`
3. **Build fails**: Check logs in `.build/logs/`
4. **ISO too large**: Remove unnecessary packages

### Verification

After building, verify the ISO:

```bash
# Check size
ls -lh *.iso

# Test in VM
qemu-system-x86_64 -cdrom SecureAutomatedPurge-v1.0.0.iso -m 2048

# Generate checksum
sha256sum SecureAutomatedPurge-v1.0.0.iso > SHA256SUMS
```

## Customization

### Adding Packages

Edit `config/package-lists/purge.list.chroot`

### Changing Boot Message

Edit `config/includes.chroot/etc/motd`

### Custom Branding

Modify ISO metadata in the `lb config` command

## Support

For build issues, please open an issue on GitHub with:
- Build environment details
- Error messages
- Build logs from `.build/logs/`
