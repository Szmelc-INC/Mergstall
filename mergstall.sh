#!/bin/bash
# SIMPLE RSYNC BASED MERGE INSTALLER SCRIPT FOR ENTROPY LINUX

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or sudo"
  exit 1
fi

clear
figlet " Mergstall " -f slant | lolcat
echo ""
echo " ~ RSYNC based Installer for Entropy Linux"
sleep 2

# Unbind target if bound
umount /mnt/target
sleep 1

# Variables
LIVE_ISO_ROOT="/"
TARGET_ROOT="/mnt/target"
SPAWN="$TARGET_ROOT/szmelc"
EXCLUDE_CONF="/bin/mergstall.d/blacklist.conf"
INCLUDE_CONF="/bin/mergstall.d/whitelist.conf"
USE_WHITELIST=true
LOG_FILE="/tmp/backup_operation_$(date +%Y%m%d%H%M%S).log"
exec &> >(tee -a "$LOG_FILE")

# Check if file exists
check_file() {
    local file="$1"
    if [[ -f "$file" && -s "$file" ]]; then
        return 0 # File exists and is non-empty
    else
        return 1 # File is missing or empty
    fi
}

# Log messages with timestamps
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}
# Start logging
log "Starting disk layout scan..."

# Display disk layout
figlet " Disk layout: " -f miniwi | lolcat
lsblk | boxes -d parchment
echo ""
sleep 3.5

# Detect Linux installations
detect_linux_installations() {
    log "Scanning for existing Linux installations..."
    mapfile -t PARTITIONS < <(lsblk -lnpo NAME,TYPE | awk '$2 == "part" {print $1}')
    
    for PARTITION in "${PARTITIONS[@]}"; do
        TEMP_MOUNT="/mnt/scan_$$"
        mkdir -p "$TEMP_MOUNT"
        
        if mount "$PARTITION" "$TEMP_MOUNT" &> /dev/null; then
            if [[ -f "$TEMP_MOUNT/etc/lsb-release" ]]; then
                DISTRO_NAME=$(grep -oP '^DISTRIB_ID="?\K[^"]+' "$TEMP_MOUNT/etc/lsb-release")
                DISTRO_VERSION=$(grep -oP '^DISTRIB_RELEASE="?\K[^"]+' "$TEMP_MOUNT/etc/lsb-release")
                log "Found: $DISTRO_NAME version $DISTRO_VERSION on $PARTITION"
            fi
            umount "$TEMP_MOUNT"
        fi
        
        rmdir "$TEMP_MOUNT"
    done
}

# Detect Linux installations
detect_linux_installations

# Ask user to select the partition to update
read -p "Select partition to update: (e.g., /dev/sda1) " TARGET_PARTITION

# Verify the partition exists
if [[ ! -b "$TARGET_PARTITION" ]]; then
    log "Error: Invalid partition. Exiting..."
    exit 1
fi

# Mount the target partition
mkdir -p "$TARGET_ROOT"
if ! mount "$TARGET_PARTITION" "$TARGET_ROOT"; then
    log "Error: Failed to mount target partition. Exiting..."
    exit 1
fi

echo " Target succesfully mounted..." | lolcat
sleep 1
figlet "  Stage 2  " -f miniwi | lolcat
sleep 1

# Create szmelc directory
log "Creating szmelc directory at target..."
mkdir -p "$SPAWN"

# Get the list of installed packages from the live ISO
log "Collecting installed packages from the live ISO..."
installed_packages=$(dpkg --get-selections | awk '$2 == "install" {print $1}')
package_list_file="$SPAWN/packages.txt"
echo "$installed_packages" > "$package_list_file"
log "List of installed packages saved to $package_list_file."

# Backup current (live ISO) home directory
log "Backing up live ISO home directory..."
cd "$LIVE_ISO_ROOT/home" && zip -r "$SPAWN/new-home.zip" * &>> "$LOG_FILE"

# Backup target's original home directory
log "Backing up target system home directory..."
cd "$TARGET_ROOT/home" && zip -r "$SPAWN/old-home.zip" * &>> "$LOG_FILE"

log "Backup completed." | lolcat
sleep 1
figlet " Stage 2 complete... " -f miniwi | lolcat 
echo ""
sleep 1

# ============ CHROOT ============
# Prompt for chroot
echo "Would you like to chroot into the target as root and execute post-installation tasks?" | lolcat 
read -t 5 -p "(y/N): " CHROOT_CONFIRM

# Default to 'No' if no input or timeout
CHROOT_CONFIRM=${CHROOT_CONFIRM:-n}

if [[ "$CHROOT_CONFIRM" =~ ^[Yy]$ ]]; then
    log "Preparing to chroot..."
    cp /etc/resolv.conf "$TARGET_ROOT/etc/resolv.conf"
    mount --bind /dev "$TARGET_ROOT/dev"
    mount --bind /proc "$TARGET_ROOT/proc"
    mount --bind /sys "$TARGET_ROOT/sys"
    mount --bind /run "$TARGET_ROOT/run"

    # Temporary script for chroot commands
    cat << 'EOF' > "$TARGET_ROOT/tmp/chroot_script.sh"
#!/bin/bash
# Placeholder for actual chroot logic
echo "Chroot stage complete"
EOF

    chmod +x "$TARGET_ROOT/tmp/chroot_script.sh"
    log "Executing commands inside chroot..."
    chroot "$TARGET_ROOT" /tmp/chroot_script.sh
    # Clean up after chroot
    rm "$TARGET_ROOT/tmp/chroot_script.sh"
    log "Chroot operations completed."
else
    log "Skipped. Operation completed."
fi
# ============ CHROOT ============

sleep 1
figlet "  RSYNC in 3s  " -f miniwi | lolcat
sleep 3

# Check if whitelisting is enabled
if [ "$USE_WHITELIST" = true ]; then
  if [ -f "$INCLUDE_CONF" ]; then
    log "Using whitelist file: $INCLUDE_CONF"
    RSYNC_INCLUDE="--include-from=$INCLUDE_CONF"
  else
    log "Whitelist file not found: $INCLUDE_CONF"
    exit 1
  fi
else
  RSYNC_INCLUDE=""
fi

# Check if exclusion file exists
if [ -f "$EXCLUDE_CONF" ]; then
  log "Using exclusion file: $EXCLUDE_CONF"
  RSYNC_EXCLUDE="--exclude-from=$EXCLUDE_CONF"
else
  RSYNC_EXCLUDE=""
fi

# Merge systems using rsync
log "Starting directory merge..."
rsync -avh $RSYNC_INCLUDE $RSYNC_EXCLUDE "$LIVE_ISO_ROOT" "$TARGET_ROOT" | tee -a "$LOG_FILE"

# Check rsync status
if [ $? -eq 0 ]; then
  log "Merge completed successfully."
else
  log "Error during merge. Exiting..."
  exit 1
fi

figlet " CONFIGURING BOOTLOADER " -f miniwi
sleep 1

mount --bind /dev /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys
mount --bind /run /mnt/target/run

chroot /mnt/target /bin/bash -c "update-grub"

umount /mnt/target/dev
umount /mnt/target/proc
umount /mnt/target/sys
umount /mnt/target/run

# Final message
figlet " COMPLETE! " -f miniwi | lolcat
sleep 3
exit
