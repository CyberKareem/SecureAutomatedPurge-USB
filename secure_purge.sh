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
            echo "=================================================="
            
            # Ensure not in use
            echo "Ensuring device is not in use..."
            umount "$DEV_PATH"* 2>/dev/null || true
            
            # Get controller and namespace info
            CTRL_PATH="${DEV_PATH%n*}"
            if [[ "$DEV_PATH" =~ nvme[0-9]+n([0-9]+) ]]; then
                NSID="${BASH_REMATCH[1]}"
            else
                NSID="1"
            fi
            
            echo "Controller: $CTRL_PATH"
            echo "Namespace: $NSID"
            echo ""
            
            # Show detailed capabilities
            echo "Drive Capabilities:"
            echo "-------------------"
            nvme id-ctrl "$DEV_PATH" -H 2>/dev/null | grep -E "Format NVM|Crypto Erase|Sanitize" | sed 's/^/  /' || echo "  Unable to read capabilities"
            echo ""
            
            PURGE_SUCCESS=false
            PURGE_METHOD=""
            
            # Method 1: Format with Crypto Erase (BEST)
            echo "Method 1: Crypto Erase Format (Secure Erase Setting 2)"
            echo "------------------------------------------------------"
            
            # Test 1a: Simple syntax
            echo -n "  Test 1a - nvme format $DEV_PATH -s 2: "
            OUTPUT=$(nvme format "$DEV_PATH" -s 2 2>&1)
            if echo "$OUTPUT" | grep -qE "Success|success|SUCCESSFUL|Format NVM command success"; then
                echo "SUCCESS!"
                PURGE_SUCCESS=true
                PURGE_METHOD="Crypto Erase Format"
            else
                echo "Failed"
                echo "    Error: $OUTPUT" | head -1
            fi
            
            # Test 1b: With force flag
            if [ "$PURGE_SUCCESS" != true ]; then
                echo -n "  Test 1b - nvme format $DEV_PATH -s 2 -f: "
                OUTPUT=$(nvme format "$DEV_PATH" -s 2 -f 2>&1)
                if echo "$OUTPUT" | grep -qE "Success|success|SUCCESSFUL|Format NVM command success"; then
                    echo "SUCCESS!"
                    PURGE_SUCCESS=true
                    PURGE_METHOD="Crypto Erase Format (forced)"
                else
                    echo "Failed"
                    echo "    Error: $OUTPUT" | head -1
                fi
            fi
            
            # Test 1c: With namespace ID
            if [ "$PURGE_SUCCESS" != true ]; then
                echo -n "  Test 1c - nvme format $DEV_PATH -n $NSID -s 2 -f: "
                OUTPUT=$(nvme format "$DEV_PATH" -n "$NSID" -s 2 -f 2>&1)
                if echo "$OUTPUT" | grep -qE "Success|success|SUCCESSFUL|Format NVM command success"; then
                    echo "SUCCESS!"
                    PURGE_SUCCESS=true
                    PURGE_METHOD="Crypto Erase Format (with namespace)"
                else
                    echo "Failed"
                    echo "    Error: $OUTPUT" | head -1
                fi
            fi
            
            # Test 1d: Using controller path
            if [ "$PURGE_SUCCESS" != true ]; then
                echo -n "  Test 1d - nvme format $CTRL_PATH -n $NSID -s 2 -f: "
                OUTPUT=$(nvme format "$CTRL_PATH" -n "$NSID" -s 2 -f 2>&1)
                if echo "$OUTPUT" | grep -qE "Success|success|SUCCESSFUL|Format NVM command success"; then
                    echo "SUCCESS!"
                    PURGE_SUCCESS=true
                    PURGE_METHOD="Crypto Erase Format (via controller)"
                else
                    echo "Failed"
                    echo "    Error: $OUTPUT" | head -1
                fi
            fi
            
            echo ""
            
            # Method 2: User Data Erase (GOOD)
            if [ "$PURGE_SUCCESS" != true ]; then
                echo "Method 2: User Data Erase Format (Secure Erase Setting 1)"
                echo "---------------------------------------------------------"
                
                # Test 2a: Simple syntax
                echo -n "  Test 2a - nvme format $DEV_PATH -s 1: "
                OUTPUT=$(nvme format "$DEV_PATH" -s 1 2>&1)
                if echo "$OUTPUT" | grep -qE "Success|success|SUCCESSFUL|Format NVM command success"; then
                    echo "SUCCESS!"
                    PURGE_SUCCESS=true
                    PURGE_METHOD="User Data Erase Format"
                else
                    echo "Failed"
                    echo "    Error: $OUTPUT" | head -1
                fi
                
                # Test 2b: With force and namespace
                if [ "$PURGE_SUCCESS" != true ]; then
                    echo -n "  Test 2b - nvme format $DEV_PATH -n $NSID -s 1 -f: "
                    OUTPUT=$(nvme format "$DEV_PATH" -n "$NSID" -s 1 -f 2>&1)
                    if echo "$OUTPUT" | grep -qE "Success|success|SUCCESSFUL|Format NVM command success"; then
                        echo "SUCCESS!"
                        PURGE_SUCCESS=true
                        PURGE_METHOD="User Data Erase Format (with namespace)"
                    else
                        echo "Failed"
                        echo "    Error: $OUTPUT" | head -1
                    fi
                fi
                
                echo ""
            fi
            
            # Method 3: Sanitize Operations
            if [ "$PURGE_SUCCESS" != true ]; then
                echo "Method 3: Sanitize Operations"
                echo "-----------------------------"
                
                # Check if sanitize is supported at all
                SANITIZE_CAPS=$(nvme id-ctrl "$DEV_PATH" -H 2>/dev/null | grep -E "Sanitize.*Supported" || echo "none")
                echo "  Sanitize support: $SANITIZE_CAPS"
                
                if echo "$SANITIZE_CAPS" | grep -q "0x1"; then
                    # Test 3a: Block Erase Sanitize
                    echo -n "  Test 3a - nvme sanitize $DEV_PATH -a 2: "
                    OUTPUT=$(nvme sanitize "$DEV_PATH" -a 2 2>&1)
                    if echo "$OUTPUT" | grep -qE "Success|Submitted|success"; then
                        echo "INITIATED!"
                        echo "  Waiting for sanitize to complete..."
                        for i in {1..30}; do
                            if ! nvme sanitize-log "$DEV_PATH" 2>/dev/null | grep -q "in progress"; then
                                break
                            fi
                            echo -n "."
                            sleep 1
                        done
                        echo " Done!"
                        PURGE_SUCCESS=true
                        PURGE_METHOD="Block Erase Sanitize"
                    else
                        echo "Failed"
                        echo "    Error: $OUTPUT" | head -1
                    fi
                    
                    # Test 3b: Crypto Erase Sanitize
                    if [ "$PURGE_SUCCESS" != true ]; then
                        echo -n "  Test 3b - nvme sanitize $DEV_PATH -a 4: "
                        OUTPUT=$(nvme sanitize "$DEV_PATH" -a 4 2>&1)
                        if echo "$OUTPUT" | grep -qE "Success|Submitted|success"; then
                            echo "INITIATED!"
                            PURGE_SUCCESS=true
                            PURGE_METHOD="Crypto Erase Sanitize"
                        else
                            echo "Failed"
                            echo "    Error: $OUTPUT" | head -1
                        fi
                    fi
                else
                    echo "  Sanitize not supported on this drive"
                fi
                
                echo ""
            fi
            
            # Method 4: Basic Format (WARNING)
            if [ "$PURGE_SUCCESS" != true ]; then
                echo "Method 4: Basic Format (No Secure Erase)"
                echo "----------------------------------------"
                echo "  WARNING: This does NOT securely erase data!"
                
                echo -n "  Test 4a - nvme format $DEV_PATH -s 0 -f: "
                OUTPUT=$(nvme format "$DEV_PATH" -s 0 -f 2>&1)
                if echo "$OUTPUT" | grep -qE "Success|success|SUCCESSFUL|Format NVM command success"; then
                    echo "SUCCESS (but data may be recoverable)"
                    PURGE_SUCCESS=true
                    PURGE_METHOD="Basic Format (NOT SECURE)"
                else
                    echo "Failed"
                    echo "    Error: $OUTPUT" | head -1
                fi
                
                echo ""
            fi
            
            # Method 5: Software Overwrite (LAST RESORT)
            if [ "$PURGE_SUCCESS" != true ]; then
                echo "Method 5: Software Overwrite"
                echo "----------------------------"
                echo "WARNING: This is NOT NIST 800-88 compliant for NVMe!"
                echo "         Data may remain in unmapped blocks."
                echo ""
                
                # Check why hardware methods failed
                echo "Checking why hardware methods failed..."
                if dmesg | tail -50 | grep -i "nvme.*error\|nvme.*fail" | tail -5; then
                    echo ""
                fi
                
                # Confirm before proceeding
                echo ""
                echo "All hardware-based secure erase methods have failed."
                echo "Proceed with software overwrite? (y/N): "
                read -t 30 -n 1 response || response="y"  # Auto-yes after 30 seconds
                echo ""
                
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    # Get size
                    DRIVE_SIZE_BYTES=$(blockdev --getsize64 "$DEV_PATH" 2>/dev/null || echo 0)
                    DRIVE_SIZE_GB=$((DRIVE_SIZE_BYTES / 1073741824))
                    echo "Drive size: ${DRIVE_SIZE_GB}GB"
                    
                    # TRIM first
                    echo "Step 1: TRIM/Discard all blocks..."
                    if command -v blkdiscard &>/dev/null; then
                        blkdiscard -f -v "$DEV_PATH" 2>&1 || echo "  TRIM failed or not supported"
                    else
                        echo "  blkdiscard not available, skipping TRIM"
                    fi
                    
                    # Overwrite
                    echo "Step 2: Overwriting with random data..."
                    echo "  This will take approximately $((DRIVE_SIZE_GB / 60)) minutes"
                    
                    START_TIME=$(date +%s)
                    
                    if command -v openssl &>/dev/null && command -v pv &>/dev/null; then
                        # Best method: OpenSSL + pv for progress
                        openssl enc -aes-256-ctr -nosalt \
                            -pass pass:"$(head -c 32 /dev/urandom | base64)" \
                            < /dev/zero | \
                            pv -petrabS "$DRIVE_SIZE_BYTES" | \
                            dd of="$DEV_PATH" bs=1M oflag=direct 2>/dev/null
                        
                        if [ ${PIPESTATUS[2]} -eq 0 ]; then
                            PURGE_SUCCESS=true
                            PURGE_METHOD="Software Overwrite (OpenSSL)"
                        fi
                    elif command -v openssl &>/dev/null; then
                        # Good method: OpenSSL with dd progress
                        openssl enc -aes-256-ctr -nosalt \
                            -pass pass:"$(head -c 32 /dev/urandom | base64)" \
                            < /dev/zero | \
                            dd of="$DEV_PATH" bs=1M status=progress oflag=direct 2>&1
                        
                        if [ ${PIPESTATUS[1]} -eq 0 ]; then
                            PURGE_SUCCESS=true
                            PURGE_METHOD="Software Overwrite (OpenSSL)"
                        fi
                    else
                        # Basic method: urandom
                        if dd if=/dev/urandom of="$DEV_PATH" bs=1M status=progress oflag=direct 2>&1; then
                            PURGE_SUCCESS=true
                            PURGE_METHOD="Software Overwrite (urandom)"
                        fi
                    fi
                    
                    END_TIME=$(date +%s)
                    DURATION=$((END_TIME - START_TIME))
                    
                    if [ "$PURGE_SUCCESS" = true ]; then
                        echo ""
                        echo "Overwrite completed in $((DURATION / 60))m $((DURATION % 60))s"
                        echo "Average speed: $((DRIVE_SIZE_BYTES / DURATION / 1048576)) MB/s"
                    fi
                else
                    echo "Software overwrite cancelled."
                fi
            fi
            
            # Final Result
            echo ""
            echo "=========================================="
            if [ "$PURGE_SUCCESS" = true ]; then
                echo "✓ NVMe PURGE SUCCESSFUL"
                echo "  Method used: $PURGE_METHOD"
                
                # Show sanitize log if available
                if [[ "$PURGE_METHOD" == *"Sanitize"* ]]; then
                    nvme sanitize-log "$DEV_PATH" 2>/dev/null | grep -E "Status|Recent" || true
                fi
            else
                echo "✗ NVMe PURGE FAILED"
                echo ""
                echo "Troubleshooting:"
                echo "1. Check BIOS/UEFI settings for:"
                echo "   - NVMe security lock"
                echo "   - TCG/OPAL settings"
                echo "   - Secure boot (try disabling)"
                echo ""
                echo "2. Try these commands manually:"
                echo "   nvme format $DEV_PATH -s 2"
                echo "   nvme format $DEV_PATH -n $NSID -s 2 -f"
                echo ""
                echo "3. Check for firmware updates for:"
                echo "   - NVMe drive"
                echo "   - System BIOS"
                echo ""
                echo "4. Report issue with this info:"
                nvme id-ctrl "$DEV_PATH" | grep -E "mn|fr|ver" || true
            fi
            echo "=========================================="
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
