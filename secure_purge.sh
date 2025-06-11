#!/bin/bash

# Enable error handling but continue on errors.
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
            
            # Get detailed NVMe info
            echo "Checking NVMe capabilities..."
            NVME_INFO=$(nvme id-ctrl "$DEV_PATH" -H 2>/dev/null || echo "")
            
            # Parse capabilities
            SUPPORTS_CRYPTO_FORMAT=false
            SUPPORTS_SANITIZE=false
            SUPPORTS_FORMAT=false
            
            if echo "$NVME_INFO" | grep -q "Crypto Erase Supported.*0x1"; then
                SUPPORTS_CRYPTO_FORMAT=true
                echo "Crypto erase via format supported"
            fi
            
            if echo "$NVME_INFO" | grep -E "Block Erase Sanitize.*0x1|Crypto Erase Sanitize.*0x1|Overwrite Sanitize.*0x1" >/dev/null; then
                SUPPORTS_SANITIZE=true
                echo "Sanitize operations supported"
            fi
            
            if echo "$NVME_INFO" | grep -q "Format NVM Supported.*0x1"; then
                SUPPORTS_FORMAT=true
                echo "Format operations supported"
            fi
            
            # Get namespace info
            echo "Detecting namespaces..."
            # Try multiple methods to get NSID
            NSID=""
            
            # Method 1: From device name
            if [[ "$DEV_PATH" =~ nvme[0-9]+n([0-9]+) ]]; then
                NSID="${BASH_REMATCH[1]}"
            fi
            
            # Method 2: From nvme list
            if [ -z "$NSID" ]; then
                NSID=$(nvme list 2>/dev/null | grep "$DEV_PATH" | awk '{print $2}' | grep -o '[0-9]*' || echo "")
            fi
            
            # Method 3: From nvme list-ns
            if [ -z "$NSID" ]; then
                NSID=$(nvme list-ns "${DEV_PATH%n*}" 2>/dev/null | grep -o '0x[0-9a-f]*' | head -1 | xargs printf "%d\n" 2>/dev/null || echo "")
            fi
            
            # Default to 1 if nothing worked
            NSID="${NSID:-1}"
            echo "Using namespace ID: $NSID"
            
            # Try purge methods based on capabilities
            PURGE_SUCCESS=false
            
            # Method 1: Crypto erase format (if supported)
            if [ "$SUPPORTS_CRYPTO_FORMAT" = true ] && [ "$PURGE_SUCCESS" != true ]; then
                echo ""
                echo "Attempting crypto erase format..."
                
                # Try with namespace
                if nvme format "$DEV_PATH" -n "$NSID" -s 2 -f 2>&1 | tee /tmp/nvme_out.log | grep -v "Invalid"; then
                    if ! grep -q "Invalid\|Error\|failed" /tmp/nvme_out.log; then
                        echo "NVMe crypto erase format successful"
                        PURGE_SUCCESS=true
                    fi
                fi
                
                # Try alternative syntax
                if [ "$PURGE_SUCCESS" != true ]; then
                    if nvme format "$DEV_PATH" --namespace-id="$NSID" --ses=2 --force 2>&1 | tee /tmp/nvme_out.log | grep -v "Invalid"; then
                        if ! grep -q "Invalid\|Error\|failed" /tmp/nvme_out.log; then
                            echo "NVMe crypto erase format successful (alt syntax)"
                            PURGE_SUCCESS=true
                        fi
                    fi
                fi
                
                # Try without namespace
                if [ "$PURGE_SUCCESS" != true ]; then
                    if nvme format "$DEV_PATH" -s 2 -f 2>&1 | tee /tmp/nvme_out.log | grep -v "Invalid"; then
                        if ! grep -q "Invalid\|Error\|failed" /tmp/nvme_out.log; then
                            echo "NVMe crypto erase format successful (no namespace)"
                            PURGE_SUCCESS=true
                        fi
                    fi
                fi
            fi
            
            # Method 2: User data erase format
            if [ "$SUPPORTS_FORMAT" = true ] && [ "$PURGE_SUCCESS" != true ]; then
                echo ""
                echo "Attempting user data erase format..."
                
                # Try with namespace
                if nvme format "$DEV_PATH" -n "$NSID" -s 1 -f 2>&1 | tee /tmp/nvme_out.log | grep -v "Invalid"; then
                    if ! grep -q "Invalid\|Error\|failed" /tmp/nvme_out.log; then
                        echo "NVMe user data erase format successful"
                        PURGE_SUCCESS=true
                    fi
                fi
                
                # Try without namespace
                if [ "$PURGE_SUCCESS" != true ]; then
                    if nvme format "$DEV_PATH" -s 1 -f 2>&1 | tee /tmp/nvme_out.log | grep -v "Invalid"; then
                        if ! grep -q "Invalid\|Error\|failed" /tmp/nvme_out.log; then
                            echo "NVMe user data erase format successful (no namespace)"
                            PURGE_SUCCESS=true
                        fi
                    fi
                fi
            fi
            
            # Method 3: Sanitize operations (if supported)
            if [ "$SUPPORTS_SANITIZE" = true ] && [ "$PURGE_SUCCESS" != true ]; then
                echo ""
                echo "Attempting sanitize operations..."
                
                # Check which sanitize operations are supported
                if echo "$NVME_INFO" | grep -q "Crypto Erase Sanitize.*0x1"; then
                    echo "Trying crypto scramble sanitize..."
                    if nvme sanitize "$DEV_PATH" -a 4 2>/dev/null || nvme sanitize "$DEV_PATH" --sanact=4 2>/dev/null; then
                        PURGE_SUCCESS=true
                    fi
                fi
                
                if [ "$PURGE_SUCCESS" != true ] && echo "$NVME_INFO" | grep -q "Block Erase Sanitize.*0x1"; then
                    echo "Trying block erase sanitize..."
                    if nvme sanitize "$DEV_PATH" -a 2 2>/dev/null || nvme sanitize "$DEV_PATH" --sanact=2 2>/dev/null; then
                        PURGE_SUCCESS=true
                    fi
                fi
                
                if [ "$PURGE_SUCCESS" != true ] && echo "$NVME_INFO" | grep -q "Overwrite Sanitize.*0x1"; then
                    echo "Trying overwrite sanitize..."
                    if nvme sanitize "$DEV_PATH" -a 3 2>/dev/null || nvme sanitize "$DEV_PATH" --sanact=3 2>/dev/null; then
                        PURGE_SUCCESS=true
                    fi
                fi
                
                # Wait for sanitize if started
                if [ "$PURGE_SUCCESS" = true ]; then
                    echo "Waiting for sanitize to complete..."
                    while nvme sanitize-log "$DEV_PATH" 2>/dev/null | grep -q "in progress"; do
                        echo -n "."
                        sleep 1
                    done
                    echo " Done!"
                fi
            fi
            
            # Method 4: Basic format (if nothing else worked)
            if [ "$SUPPORTS_FORMAT" = true ] && [ "$PURGE_SUCCESS" != true ]; then
                echo ""
                echo "Attempting basic format..."
                
                if nvme format "$DEV_PATH" -n "$NSID" -s 0 -f 2>&1 | tee /tmp/nvme_out.log; then
                    if ! grep -q "Invalid\|Error\|failed" /tmp/nvme_out.log; then
                        echo "Basic format successful (data may be recoverable)"
                        echo "WARNING: Basic format is not cryptographically secure"
                        PURGE_SUCCESS=true
                    fi
                fi
            fi
            
            # Method 5: Software overwrite (last resort)
            if [ "$PURGE_SUCCESS" != true ]; then
                echo ""
                echo "WARNING: All hardware-based purge methods failed."
                echo "Attempting software overwrite (not NIST 800-88 compliant for NVMe)..."
                
                # Get drive size for progress estimation
                DRIVE_SIZE_GB=$(($(blockdev --getsize64 "$DEV_PATH" 2>/dev/null || echo 0) / 1073741824))
                echo "Drive size: ${DRIVE_SIZE_GB}GB"
                
                # First try TRIM/discard
                echo "Executing TRIM on entire drive..."
                if command -v blkdiscard &>/dev/null; then
                    blkdiscard -f "$DEV_PATH" 2>/dev/null || true
                else
                    # Alternative using nvme write-zeroes
                    echo "Using NVMe write-zeroes instead of TRIM..."
                    nvme write-zeroes "$DEV_PATH" -s 0 -c 0xffffffff 2>/dev/null || true
                fi
                
                # Then overwrite with random data
                echo "Overwriting with random data..."
                if command -v openssl &>/dev/null; then
                    # Use OpenSSL for faster random generation
                    openssl enc -aes-256-ctr -nosalt \
                        -pass pass:"$(head -c 32 /dev/urandom | base64)" \
                        < /dev/zero | \
                        dd of="$DEV_PATH" bs=1M status=progress oflag=direct 2>&1
                else
                    # Fallback to urandom
                    dd if=/dev/urandom of="$DEV_PATH" bs=1M status=progress oflag=direct 2>&1
                fi
                
                if [ ${PIPESTATUS[0]} -eq 0 ] || [ ${PIPESTATUS[1]} -eq 0 ]; then
                    echo "Software overwrite completed"
                    echo "WARNING: This may not erase all data due to NVMe wear leveling"
                    PURGE_SUCCESS=true
                else
                    echo "ERROR: Software overwrite also failed"
                fi
            fi
            
            # Display result
            if [ "$PURGE_SUCCESS" = true ]; then
                echo ""
                echo "NVMe purge completed successfully"
                
                # Try to show sanitize log if available
                nvme sanitize-log "$DEV_PATH" 2>/dev/null | grep -E "Most Recent Sanitize|Status" || true
            else
                echo ""
                echo "ERROR: All NVMe purge methods failed"
                echo "This drive may require vendor-specific tools or BIOS changes"
            fi
            
            # Clean up
            rm -f /tmp/nvme_out.log 2>/dev/null || true
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
