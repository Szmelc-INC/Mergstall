#!/bin/bash
# MERGSTALL - MERGE INSTALL SCRIPT FOR ENTROPY LINUX

# Require the script to be run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or sudo"
  exit 1
fi

clear && figlet " Mergstall v2.1 " -f slant | lolcat && echo ""
echo " ====== RSYNC based Installer for Entropy Linux ====== " | lolcat && sleep 2

# Unbind target if already bound
umount /mnt/target
sleep 1

# Define variables
LIVE_ISO_ROOT="/"
TARGET_ROOT="/mnt/target"
SPAWN="$TARGET_ROOT/szmelc"
EXCLUDE_CONF="/bin/mergstall.d/blacklist.conf"
INCLUDE_CONF="/bin/mergstall.d/whitelist.conf"
USE_WHITELIST=true
LOG_FILE="/tmp/backup_operation_$(date +%Y%m%d%H%M%S).log"
exec &> >(tee -a "$LOG_FILE")

# Generate conf
check_file() {
    local file="$1"
    if [[ -f "$file" && -s "$file" ]]; then
        return 0
    else
        return 1 
    fi
}

# log with timestamps
log() {
echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Start logging
log "Starting disk layout scan..."

# Display disk layout
figlet " Disk layout: " -f miniwi | lolcat
lsblk | boxes -d parchment && echo "" && sleep 3.5

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
                log "Found Linux installation: $DISTRO_NAME version $DISTRO_VERSION on partition $PARTITION"
            fi
            umount "$TEMP_MOUNT"
        fi
        
        rmdir "$TEMP_MOUNT"
    done
}

# Detect Linux installations
detect_linux_installations
# Ask user to select the partition
read -p "Select target root partition (e.g., /dev/sda1): " TARGET_PARTITION

# Verify partition
if [[ ! -b "$TARGET_PARTITION" ]]; then
    log "Error: Invalid partition. Exiting..."
    exit 1
fi
# Mount the target
mkdir -p "$TARGET_ROOT"
if ! mount "$TARGET_PARTITION" "$TARGET_ROOT"; then
    log "Error: Failed to mount target partition. Exiting..."
    exit 1
fi

echo " Target succesfully mounted..." | lolcat && sleep 1 && figlet "  Stage 2  " -f miniwi | lolcat && sleep 1

# ============== USER FINDER =================
echo "" && echo " Users found on target: " | lolcat
cut -d: -f1 "$TARGET_ROOT"/etc/passwd | sort | grep -Fxf <(ls "$TARGET_ROOT"/home | sort) && echo ""
read -p " Select user to update, or create new one: " CHOSEN_USER

# backup configs
# [todo: make it actually decent...]
cp "$EXCLUDE_CONF" "$EXCLUDE_CONF"-old && cp "$INCLUDE_CONF" "$INCLUDE_CONF"-old

# change /home/*/ to /home/<user>/
sed -i "s|/home/[^/]\+/|/home/$CHOSEN_USER/|g" "$EXCLUDE_CONF" "$INCLUDE_CONF"

# ============ SZMELC DIR =============
log "Creating szmelc directory at target..." && mkdir -p "$SPAWN"
# List installed packages from live ISO
log "Reading installed packages from live ISO..."
installed_packages=$(dpkg --get-selections | awk '$2 == "install" {print $1}')
package_list_file="$SPAWN/packages.txt"
echo "$installed_packages" > "$package_list_file"
log "List of installed packages saved to $package_list_file."

# ======== BACKUP ==========
# Backup current (live ISO) home
log "Backing up live ISO home..."
cd "$LIVE_ISO_ROOT/home" && zip -r "$SPAWN/new-home.zip" * &>> "$LOG_FILE"
# Backup target's home
log "Backing up target system home..."
cd "$TARGET_ROOT/home" && zip -r "$SPAWN/old-home.zip" * &>> "$LOG_FILE"
log "Backup completed." | lolcat && sleep 1
figlet " Stage 2 complete... " -f miniwi | lolcat && echo "" && sleep 1

# DEBUG! [ it breaks things...]
sudo rm -fr "$TARGET_ROOT/usr/bin/postinstall"
sudo rm -fr "$TARGET_ROOT/bin/postinstall"

# ============ CHROOT ============
# Prompt for chroot
echo " ~ Chroot into the target? " | lolcat 
read -t 5 -p "(y/N): " CHROOT_CONFIRM
# Default to 'N' if no input or timeout
CHROOT_CONFIRM=${CHROOT_CONFIRM:-n}
if [[ "$CHROOT_CONFIRM" =~ ^[Yy]$ ]]; then
    log "Preparing to chroot..."
    cp /etc/resolv.conf "$TARGET_ROOT/etc/resolv.conf"
    mount --bind /dev "$TARGET_ROOT/dev"
    mount --bind /proc "$TARGET_ROOT/proc"
    mount --bind /sys "$TARGET_ROOT/sys"
    mount --bind /run "$TARGET_ROOT/run"
    # Create a temporary script
    cat << 'EOF' > "$TARGET_ROOT/tmp/chroot_script.sh"
#!/bin/bash
figlet CHROOTed
sleep 2
# Placeholder for actual chroot logic
echo "Chroot stage complete"
EOF
    chmod +x "$TARGET_ROOT/tmp/chroot_script.sh"
    log "Executing inside chroot..."
    chroot "$TARGET_ROOT" /tmp/chroot_script.sh
    # Clean up after chroot
    rm "$TARGET_ROOT/tmp/chroot_script.sh"
    log "Chroot completed."
else
    log "Skipped. Continuing!"
fi
sleep 1 && figlet "  RSYNC in 3s  " -f miniwi | lolcat && sleep 3

# ============ RSYNC ============
# Verify whitelist
if [ "$USE_WHITELIST" = true ]; then
  if [ ! -f "$INCLUDE_CONF" ]; then
    log "Whitelist not found: $INCLUDE_CONF"
    exit 1
  else
    log "Whitelist.conf: $INCLUDE_CONF"
  fi
fi
# Verify blacklist
if [ ! -f "$EXCLUDE_CONF" ]; then
  log "Blacklist not found: $EXCLUDE_CONF"
  exit 1
else
  log "Blacklist.conf: $EXCLUDE_CONF"
fi

# Merge directories with rsync
figlet "SYNC" -f miniwi | lolcat
log "Starting sync..."
rsync -avh \
    --filter="include */" \
    --filter="merge $EXCLUDE_CONF" \
    --filter="merge $INCLUDE_CONF" \
    --filter="exclude *" \
    --prune-empty-dirs \
    "$LIVE_ISO_ROOT/" "$TARGET_ROOT/" | tee -a "$LOG_FILE"

# Check status
if [ $? -eq 0 ]; then
  log "Merge succesfull!"
else
  log "Error during merge :( Exiting..."
  exit 1
fi

figlet " CONFIG BOOTLOADER " -f miniwi && sleep 1

mount --bind /dev /mnt/target/dev && mount --bind /proc /mnt/target/proc && mount --bind /sys /mnt/target/sys && mount --bind /run /mnt/target/run

# Optional snippet to create new user
#chroot /mnt/target /bin/bash -c "useradd -M $CHOSEN_USER && echo '$CHOSEN_USER:$CHOSEN_USER' | chpasswd"
# Configure bootloader

chroot /mnt/target /bin/bash -c "update-grub"
chroot /mnt/target /bin/bash -c "plymouth-set-default-theme szmelc -R"
# update-initramfs -u
umount /mnt/target/dev && umount /mnt/target/proc && umount /mnt/target/sys && umount /mnt/target/run

# Final message
figlet " MERGSTALL COMPLETE! " -f miniwi | lolcat && echo "[ Enjoy new features! <3 ]" && sleep 3 && exit
