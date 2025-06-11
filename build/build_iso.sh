#!/bin/bash
# Secure Automated Purge USB - ISO Build Script
# Author: Abdullah Kareem
# License: MIT

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ISO_NAME="SecureAutomatedPurge"
VERSION="1.0.0"
BUILD_DIR="$HOME/sap_usb_build_$$"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Secure Automated Purge USB Builder${NC}"
echo -e "${GREEN}Version: ${VERSION}${NC}"
echo -e "${GREEN}======================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Check for required tools
echo -e "\n${YELLOW}Checking dependencies...${NC}"
for tool in lb debootstrap xorriso mkisofs; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${RED}Error: $tool is not installed${NC}"
        echo "Run: apt install live-build debootstrap xorriso syslinux-utils mtools mkisofs"
        exit 1
    fi
done

# Create build directory
echo -e "\n${YELLOW}Creating build directory: ${BUILD_DIR}${NC}"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ====== FIX: Clean BEFORE configuring ======
# Clean any previous builds (though this is a new directory)
echo -e "\n${YELLOW}Cleaning build environment...${NC}"
lb clean --all 2>/dev/null || true

# Configure live-build
echo -e "\n${YELLOW}Configuring live-build...${NC}"
lb config \
    --distribution bookworm \
    --architectures amd64 \
    --mode debian \
    --binary-images iso-hybrid \
    --bootappend-live "boot=live components quiet splash" \
    --debian-installer false \
    --apt-recommends false \
    --iso-application "Secure Automated Purge ${VERSION}" \
    --iso-preparer "Abdullah Kareem" \
    --iso-publisher "CyberKareem" \
    --iso-volume "SAP_USB_V${VERSION}"

# Copy configuration files
echo -e "\n${YELLOW}Copying configuration files...${NC}"
if [ -d "${REPO_DIR}/build/config" ]; then
    cp -r "${REPO_DIR}/build/config/"* config/ 2>/dev/null || true
fi

# Create directory structure
mkdir -p config/includes.chroot/usr/local/bin
mkdir -p config/includes.chroot/etc
mkdir -p config/includes.chroot/etc/systemd/system
mkdir -p config/includes.chroot/var/log/purge_audit
mkdir -p config/package-lists
mkdir -p config/archives
mkdir -p config/hooks/normal

# Copy secure purge script
echo -e "\n${YELLOW}Installing secure purge script...${NC}"
if [ -f "${REPO_DIR}/secure_purge.sh" ]; then
    cp "${REPO_DIR}/secure_purge.sh" config/includes.chroot/usr/local/bin/
    chmod +x config/includes.chroot/usr/local/bin/secure_purge.sh
else
    echo -e "${RED}Error: secure_purge.sh not found in ${REPO_DIR}${NC}"
    exit 1
fi

# Create rc.local
echo -e "\n${YELLOW}Creating rc.local...${NC}"
cat > config/includes.chroot/etc/rc.local << 'EOF'
#!/bin/sh
# Ensure we have a terminal for user input
exec < /dev/console > /dev/console 2>&1
# Clear the screen first 
clear
# Run the secure purge script
/usr/local/bin/secure_purge.sh
# Exit with success regardless of script outcome
exit 0
EOF
chmod +x config/includes.chroot/etc/rc.local

# Configure packages
echo -e "\n${YELLOW}Configuring packages...${NC}"
cat > config/package-lists/purge.list.chroot << EOF
nvme-cli
hdparm
smartmontools
util-linux
pv
coreutils
pciutils
usbutils
bsdextrautils
openssl
perl
dmidecode
EOF

# Configure repositories
echo -e "\n${YELLOW}Configuring repositories...${NC}"
cat > config/archives/live.list.chroot << EOF
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

# Create systemd service
echo -e "\n${YELLOW}Creating systemd service...${NC}"
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

# Create enable service hook
echo -e "\n${YELLOW}Creating hooks...${NC}"
cat > config/hooks/normal/01-enable-rc-local.chroot << 'EOF'
#!/bin/sh
set -e
systemctl enable rc-local.service
EOF
chmod +x config/hooks/normal/01-enable-rc-local.chroot

# Create disable services hook
cat > config/hooks/normal/02-disable-services.chroot << 'EOF'
#!/bin/sh
set -e
# Only disable services that typically exist in Debian Live
systemctl disable apt-daily.service || true
systemctl disable apt-daily.timer || true
systemctl disable apt-daily-upgrade.timer || true
systemctl disable apt-daily-upgrade.service || true
EOF
chmod +x config/hooks/normal/02-disable-services.chroot

# Create log directory
touch config/includes.chroot/var/log/purge_audit/.gitkeep

# ====== REMOVED: lb clean --all from here ======

# Build bootstrap
echo -e "\n${YELLOW}Building bootstrap (this may take a while)...${NC}"
lb bootstrap

# Build the ISO
echo -e "\n${YELLOW}Building ISO (this will take 10-20 minutes)...${NC}"
lb build

# Check if build succeeded
if [ -f "live-image-amd64.hybrid.iso" ]; then
    # Calculate final ISO name
    OUTPUT_ISO="${ISO_NAME}-v${VERSION}.iso"
    
    # Move to repo directory
    mv live-image-amd64.hybrid.iso "${REPO_DIR}/${OUTPUT_ISO}"
    
    # Generate checksum
    cd "${REPO_DIR}"
    sha256sum "${OUTPUT_ISO}" > "${OUTPUT_ISO}.sha256"
    
    # Display results
    echo -e "\n${GREEN}======================================${NC}"
    echo -e "${GREEN}Build completed successfully!${NC}"
    echo -e "${GREEN}=======================================${NC}"
    echo -e "ISO: ${REPO_DIR}/${OUTPUT_ISO}"
    echo -e "SHA256: $(cat ${OUTPUT_ISO}.sha256)"
    echo -e "Size: $(ls -lh ${OUTPUT_ISO} | awk '{print $5}')"
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo "1. Test the ISO in a VM first"
    echo "2. Create a GitHub release and upload the ISO"
    echo "3. Update README.md with the actual SHA256 checksum"
else
    echo -e "\n${RED}Build failed! Check logs in ${BUILD_DIR}/.build/logs/${NC}"
    exit 1
fi

# Cleanup option
echo -e "\n${YELLOW}Build directory: ${BUILD_DIR}${NC}"
read -p "Remove build directory? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "${BUILD_DIR}"
    echo -e "${GREEN}Build directory removed${NC}"
fi

echo -e "\n${GREEN}Done!${NC}"
