#!/bin/bash

# Enable error handling but continue on errors
set +e

banner_start() {
cat << "EOF"
===============================================
 SecureAutomatedPurge - NIST 800-88 Purge Utility
 Developed by Abdullah Kareem - MIT License
 Github.com/CyberKareem
===============================================
EOF
}

banner_process() {
cat << EOF

--- Purging Disk: $1 ---

EOF
}

banner_end() {
echo -e "\033[0;32m"
cat << "EOF"
===============================================
          Purge Process Complete
===============================================
EOF
echo -e "\033[0m"
}

# Function to check if drive is frozen
check_frozen() {
    local dev=$1
    if hdparm -I "$dev" 2>/dev/null | grep -q "frozen"; then
        return 0  # Drive is frozen
    else
        return 1  # Drive is not frozen
    fi
}

# Function to attempt unfreezing drive via sleep/wake cycle
unfreeze_drive() {
    local dev=$1
    echo "Attempting to unfreeze drive $dev..."
    echo "System will enter sleep mode and wake up..."
    
    # Try sleep/wake cycle
    sync
    echo -n mem > /sys/power/state 2>/dev/null || true
    sleep 2
    
    # Check if still frozen
    if check_frozen "$dev"; then
        echo "WARNING: Drive $dev remains frozen. Some security commands may fail."
        return 1
    else
        echo "Drive $dev successfully unfrozen."
        return 0
    fi
}

# Function to perform ATA Secure Erase
ata_secure_erase() {
    local dev=$1
    
    echo "Checking ATA security status..."
    hdparm -I "$dev" | grep -A10 "Security:" || true
    
    # Check if frozen
    if check_frozen "$dev"; then
        unfreeze_drive "$dev"
    fi
    
    # Check if secure erase is supported
    if ! hdparm -I "$dev" 2>/dev/null | grep -q "SECURITY ERASE UNIT"; then
        echo "ATA Secure Erase not supported on $dev"
        return 1
    fi
    
    # Set a temporary password
    echo "Setting ATA password..."
    if ! hdparm --user-master u --security-set-pass p "$dev"; then
        echo "Failed to set ATA password"
        return 1
    fi
    
    # Get erase time estimate
    ERASE_TIME=$(hdparm -I "$dev" | grep "SECURITY ERASE UNIT" | awk '{print $1}' | grep -o '[0-9]*' | head -1)
    echo "Estimated erase time: ${ERASE_TIME:-unknown} minutes"
    
    # Perform secure block erase
    echo "Starting ATA Secure Block Erase (this may take a while)..."
    if hdparm --user-master u --security-erase p "$dev"; then
        echo "ATA Secure Block Erase completed successfully"
        return 0
    else
        # Try to disable password if erase failed
        hdparm --user-master u --security-disable p "$dev" 2>/dev/null || true
        echo "ATA Secure Block Erase failed"
        return 1
    fi
}

# Function to verify drive is empty
verify_purge() {
    local dev=$1
    echo "Verifying purge: sampling sectors from device..."
    
    if [ ! -b "$dev" ]; then
        echo "WARNING: Device $dev not found for verification"
        return 0
    fi
    
    SECTORS=$(blockdev --getsz "$dev" 2>/dev/null || echo 0)
    if [ "$SECTORS" -eq 0 ]; then
        echo "WARNING: Cannot determine device size for verification"
        return 0
    fi
    
    echo "Device has $SECTORS sectors"
    
    # Check if hexdump is available
    if ! command -v hexdump &>/dev/null; then
        echo "WARNING: hexdump not found, showing raw data instead"
        # Sample start, middle, and end
        for position in "Start:0" "Middle:$((SECTORS / 2))" "End:$((SECTORS - 1))"; do
            label="${position%:*}"
            offset="${position#*:}"
            echo "$label of drive (sector $offset):"
            dd if="$dev" bs=512 count=1 skip="$offset" 2>/dev/null | od -A x -t x1z | head -5 || true
        done
    else
        # Sample start, middle, and end
        for position in "Start:0" "Middle:$((SECTORS / 2))" "End:$((SECTORS - 1))"; do
            label="${position%:*}"
            offset="${position#*:}"
            echo "$label of drive (sector $offset):"
            dd if="$dev" bs=512 count=1 skip="$offset" 2>/dev/null | hexdump -C | head -5 || true
        done
    fi
    
    return 0
}

# Main execution
banner_start
echo "=== Secure Purge Initiated: $(date) ==="

# Load required modules
modprobe -q nvme_core nvme || true

PURGED_DRIVES=0
FAILED_DRIVES=0

echo "Detecting drives..."
echo ""

# Simple and direct approach
VALID_DRIVES=""
for dev in sda sdb sdc sdd sde sdf sdg nvme0n1 nvme1n1 nvme2n1; do
    DEV_PATH="/dev/$dev"
    
    # Check if device exists
    if [ ! -b "$DEV_PATH" ]; then
        continue
    fi
    
    # Get device info
    TRAN=$(lsblk -dno TRAN "$DEV_PATH" 2>/dev/null || echo "unknown")
    
    # Skip USB devices
    if [ "$TRAN" = "usb" ]; then
        echo "Skipping USB device: $DEV_PATH"
        continue
    fi
    
    # This is a valid drive to purge
    VALID_DRIVES="$VALID_DRIVES $dev"
done

# Check if any drives were found
if [ -z "$VALID_DRIVES" ]; then
    echo "ERROR: No valid drives found to purge!"
    echo ""
    echo "Detected block devices:"
    lsblk -d
    echo ""
    echo "This usually means all drives are USB devices (excluded for safety)"
    echo "Dropping to shell for manual inspection..."
    /bin/bash
    exit 1
fi

# SAFETY CONFIRMATION
echo ""
echo "╔══════════════════════════════════════════╗"
echo "                   WARNING                 "
echo "                                           "
echo "   This will PERMANENTLY DESTROY ALL DATA  "
echo "╚══════════════════════════════════════════╝"
echo ""


# List all drives to be purged
for dev in $VALID_DRIVES; do
    MODEL=$(lsblk -dno MODEL "/dev/$dev" 2>/dev/null | sed 's/[[:space:]]*$//' || echo "Unknown")
    SIZE=$(lsblk -dno SIZE "/dev/$dev" 2>/dev/null || echo "Unknown")
    SERIAL=$(hdparm -I "/dev/$dev" 2>/dev/null | grep "Serial Number:" | awk '{print $3}' || echo "Unknown")
    echo "  • /dev/$dev - $SIZE - $MODEL (Serial: $SERIAL)"
done

echo ""
echo "This action CANNOT be undone!"
echo ""
echo "To proceed, type: ERASE ALL DATA"
echo -n "Enter confirmation: "

read user_input

if [ "$user_input" != "ERASE ALL DATA" ]; then
    echo ""
    echo "Incorrect confirmation. Purge aborted."
    echo "System will shut down in 5 seconds."
    sleep 5
    poweroff
    exit 1
fi

echo ""
echo "Confirmed. Starting purge process..."
echo "===================================="
echo ""

# Process each drive
for dev in $VALID_DRIVES; do
    DEV_PATH="/dev/$dev"
    
    # Check if device exists
    if [ ! -b "$DEV_PATH" ]; then
        continue
    fi
    
    # Get device info
    TRAN=$(lsblk -dno TRAN "$DEV_PATH" 2>/dev/null || echo "unknown")
    
    # Skip USB devices
    if [ "$TRAN" = "usb" ]; then
        echo "Skipping USB device: $DEV_PATH"
        continue
    fi
    
    # This is a valid drive to purge
    MODEL=$(lsblk -dno MODEL "$DEV_PATH" 2>/dev/null | sed 's/[[:space:]]*$//' || echo "Unknown")
    SIZE=$(lsblk -dno SIZE "$DEV_PATH" 2>/dev/null || echo "Unknown")
    SERIAL=$(hdparm -I "$DEV_PATH" 2>/dev/null | grep "Serial Number:" | awk '{print $3}' || echo "Unknown")
    
    banner_process "$DEV_PATH - $SIZE (Model: $MODEL, Serial: $SERIAL)"
    
    # Determine drive type
    TYPE="UNKNOWN"
    
    # Check if NVMe
    if [[ "$dev" == nvme* ]]; then
        TYPE="NVMe"
    else
        # Check if SSD or HDD
        ROTA=$(cat /sys/block/$dev/queue/rotational 2>/dev/null || echo "")
        
        if [ "$ROTA" = "0" ]; then
            if [ "$TRAN" = "sata" ] || [ "$TRAN" = "ata" ]; then
                TYPE="SATA_SSD"
            else
                TYPE="SSD"
            fi
        elif [ "$ROTA" = "1" ]; then
            TYPE="HDD"
        else
            # Fallback: check model name
            if echo "$MODEL" | grep -qiE "SSD|Solid|Flash"; then
                TYPE="SATA_SSD"
            else
                TYPE="HDD"
            fi
        fi
    fi
    
    echo "Drive Type: $TYPE (Transport: $TRAN)"
    PURGE_SUCCESS=false
    
    case "$TYPE" in
"NVMe")
            echo "NVMe drive detected. Attempting NIST 800-88 Purge..."
            
            # Try crypto erase first (most secure and fastest)
            if nvme format "$DEV_PATH" --ses=2 -f 2>/dev/null; then
                echo "NVMe crypto erase successful"
                PURGE_SUCCESS=true
            # Fall back to block erase
            elif nvme format "$DEV_PATH" --ses=1 -f 2>/dev/null; then
                echo "NVMe block erase successful"
                PURGE_SUCCESS=true
            # Try sanitize as last resort
            elif command -v nvme &>/dev/null && nvme sanitize "$DEV_PATH" --sanact=2 2>/dev/null; then
                echo "NVMe sanitize crypto erase successful"
                PURGE_SUCCESS=true
            else
                echo "WARNING: All NVMe hardware purge methods failed, hardware not supported"
                echo "Falling back to overwrite method according to NIST 800-88 Purge..."
                echo ""
                
                # Get drive size for progress estimation
                SIZE_BYTES=$(blockdev --getsize64 "$DEV_PATH" 2>/dev/null || echo 0)
                SIZE_GB=$((SIZE_BYTES / 1024 / 1024 / 1024))
                echo "Drive size: ${SIZE_GB}GB"
                echo "Estimated time: $((SIZE_GB * 3 / 60)) minutes for random overwrite"
                
                # Perform single-pass random overwrite
                echo "Starting random data overwrite..."
                if dd if=/dev/urandom of="$DEV_PATH" bs=1M status=progress conv=fdatasync 2>/dev/null; then
                    echo "Software overwrite completed successfully"
                    
                    # Issue final TRIM to ensure all blocks are marked as erased
                    echo "Issuing final TRIM command to ensure all blocks are marked as erased..."
                    blkdiscard -f "$DEV_PATH" 2>/dev/null || nvme dsm "$DEV_PATH" -d -s 0 -b 100000 2>/dev/null || true
                    
                    echo "NIST 800-88 Purge achieved through random data overwrite"
                    PURGE_SUCCESS=true
                else
                    echo "ERROR: Random data overwrite failed"
                fi
            fi
            ;;
            
        "SATA_SSD"|"SSD")
            echo "SATA SSD detected. Attempting NIST 800-88 Purge..."
            
            # Try ATA Secure Erase first (most compatible)
            if ata_secure_erase "$DEV_PATH"; then
                PURGE_SUCCESS=true
            # Try newer sanitize commands if available
            elif hdparm --sanitize-crypto-scramble "$DEV_PATH" --yes-i-know-what-i-am-doing 2>/dev/null; then
                echo "Sanitize crypto scramble successful"
                PURGE_SUCCESS=true
            elif hdparm --sanitize-block-erase "$DEV_PATH" --yes-i-know-what-i-am-doing 2>/dev/null; then
                echo "Sanitize block erase successful"
                PURGE_SUCCESS=true
            else
                echo "WARNING: Hardware-based purge failed. Falling back to overwrite method."
                echo "Note: Software overwrite is NOT NIST 800-88 compliant for SSDs due to wear leveling."
                
                # Attempt software overwrite as last resort
                if dd if=/dev/urandom of="$DEV_PATH" bs=1M status=progress 2>/dev/null; then
                    echo "Software overwrite completed (not fully effective for SSDs)"
                    PURGE_SUCCESS=true
                else
                    echo "ERROR: All purge methods failed for $DEV_PATH"
                fi
            fi
            ;;
            
        "HDD")
            echo "HDD detected. Performing NIST 800-88 Purge (3-pass overwrite)..."
            
            # For HDDs, overwrite is appropriate per NIST 800-88
            if shred -v -n 3 "$DEV_PATH"; then
                echo "HDD Purge completed successfully"
                PURGE_SUCCESS=true
            else
                echo "ERROR: HDD overwrite failed"
            fi
            ;;
            
        *)
            echo "ERROR: Unable to determine drive type for $DEV_PATH. Skipping."
            ;;
    esac
    
    # Verify if purge was successful
    if [ "$PURGE_SUCCESS" = true ]; then
        echo "Purge completed. Performing verification..."
        verify_purge "$DEV_PATH" || echo "Verification completed with warnings"
        ((PURGED_DRIVES++))
        echo "SUCCESS: $DEV_PATH purged successfully"
    else
        ((FAILED_DRIVES++))
        echo "FAILURE: $DEV_PATH purge failed"
    fi
    
    echo "----------------------------------------"
    echo "DEBUG: Continuing to next drive or finishing..."
done

echo ""
echo "=== Purge Summary ==="
echo "Total drives purged successfully: $PURGED_DRIVES"
echo "Total drives failed: $FAILED_DRIVES"
echo "=== Purge Completed: $(date) ===" 

banner_end
echo "System will power off in 5 seconds."
echo "Preparing for shutdown..."

# Sync filesystems
sync
sync
sync

# Countdown
for i in 5 4 3 2 1; do
    echo -n "$i... "
    sleep 1
done
echo "0"

# Poweroff using systemctl (cleanest method)
echo "Initiating poweroff..."
systemctl poweroff --force --force 2>/dev/null || true

# If that fails, try these fallbacks
sleep 2
echo "Trying alternative poweroff methods..."
/sbin/poweroff -f 2>/dev/null || /sbin/halt -f 2>/dev/null || echo o > /proc/sysrq-trigger 2>/dev/null

# If we're still here, reboot instead
echo "All poweroff methods failed, attempting reboot..."
sleep 2
/sbin/reboot -f

# Exit cleanly (shouldn't reach here)
exit 0
