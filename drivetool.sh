#!/bin/bash

declare -r MOUNT_POINT="/media/flashdrive"

# Define sudo command or alternative for elevated privileges
SUDO="sudo"

# Check for sudo access at the start if a sudo command is used
if [[ -n "$SUDO" ]] && ! "$SUDO" -v &> /dev/null; then
    echo "Error: This script requires sudo access to run." >&2
    exit 1
fi

# Function to check for required commands
check_dependencies() {
    local dependencies=(lsblk mkdir rmdir mount umount cp du grep diff rsync sync blkid mkfs.exfat)
    local missing=()
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -ne 0 ]]; then
        echo "Error: Required commands not installed: ${missing[*]}" >&2
        exit 1
    fi
}

# Function to safely sync and unmount the device
safe_unmount() {
    local device="$1"
    if mount | grep -qw "$device"; then
        echo "Syncing device..."
        sync
        echo "$device is currently mounted, attempting to unmount..."
        "$SUDO" umount "$device" && echo "$device unmounted successfully." || { echo "Failed to unmount $device."; return 1; }
    fi
}

# Function to mount drive
ensure_mounted() {
    local device="$1"
    if ! mount | grep -q "$MOUNT_POINT"; then
        echo "Mounting $device..."
        "$SUDO" mkdir -p "$MOUNT_POINT"
        "$SUDO" mount "$device" "$MOUNT_POINT" || { echo "Failed to mount $device."; exit 1; }
    else
        echo "Device is already mounted on $MOUNT_POINT."
    fi
}

# Function to copy files or directories safely
copy_files() {
    local source="$1"
    local destination="$2"
    local dest_path="$destination/$(basename "$source")"

    if [[ -d "$source" ]]; then
        echo "Copying directory $source to $destination using 'cp -r'..."
        "$SUDO" cp -r "$source" "$dest_path" && echo "$source has been copied."
    else
        echo "Copying file $source to $destination using 'cp'..."
        "$SUDO" cp "$source" "$dest_path" && echo "$source has been copied."
    fi
    
    # Verify copy integrity
    if "$SUDO" du -b "$source" && "$SUDO" du -b "$dest_path" && "$SUDO" diff -qr "$source" "$dest_path"; then
        echo "Verification successful: No differences found."
    else
        echo "Verification failed: Differences found!"
        return 1
    fi
}

# Function to copy files or directories using rsync
rsync_files() {
    local source="$1"
    local destination="$2"
    echo "Copying $source to $destination using rsync..."
    "$SUDO" rsync -avh --no-perms --no-owner --no-group --progress "$source" "$destination" && echo "Files copied successfully using rsync."
}


# Function to check filesystem existence
check_filesystem() {
    local device="$1"
    local blkid_output
    blkid_output=$("$SUDO" blkid -o export "$device")
    if [[ -n "$blkid_output" ]]; then
        echo -e "Warning: $device has existing data:"
        echo "$blkid_output" | grep -E '^(TYPE|PTTYPE)='
        echo -e "Please confirm to proceed with formatting:"
        return 0
    else
        return 1
    fi
}

# Function to format the drive
format_drive() {
    local device="$1"
    echo "Checking if device $device is mounted..."
    safe_unmount "$device" || return 1

    # Check existing filesystems or partition tables
    if check_filesystem "$device"; then
        read -p "Are you sure you want to format $device? [y/N]: " confirm
        if [[ $confirm != [yY] ]]; then
            echo "Formatting aborted."
            return 1
        fi
    fi
    
    echo "Formatting $device..."
    "$SUDO" mkfs.exfat "$device" && echo "Drive formatted successfully." || echo "Formatting failed."
}

# Function to display usage information
help() {
    echo "Usage: $0 OPTION [ARGUMENTS]"
    echo
    echo "Options:"
    echo "  -c, -C DEVICE SOURCE_PATH    Mount DEVICE and copy SOURCE_PATH to it using 'cp'."
    echo "  -r, -R DEVICE SOURCE_PATH    Mount DEVICE and copy SOURCE_PATH to it using 'rsync'."
    echo "  -l, -L                       List information about block devices."
    echo "  -f, -F DEVICE                Format DEVICE."
    echo
    echo "Examples:"
    echo "  $0 -C /path/to/data /dev/sdx # Copy /path/to/data to /dev/sdx after mounting it using 'cp'."
    echo "  $0 -R /path/to/data /dev/sdx # Copy /path/to/data to /dev/sdx after mounting it using 'rsync'."
    echo "  $0 -L                        # List all block devices."
    echo "  $0 -F /dev/sdx               # Format /dev/sdx."
}

# Process command-line arguments
case "$1" in
    -C | -c)
        check_dependencies
        ensure_mounted "$3"
        copy_files "$2" "$MOUNT_POINT"
        safe_unmount "$MOUNT_POINT"
	"$SUDO" rmdir "$MOUNT_POINT"
        ;;
    -R | -r)
        check_dependencies
        ensure_mounted "$3"
        rsync_files "$2" "$MOUNT_POINT"
        safe_unmount "$MOUNT_POINT"
	"$SUDO" rmdir "$MOUNT_POINT"
        ;;
    -L | -l)
        lsblk -o NAME,MODEL,SERIAL,VENDOR,TRAN
        ;;
    -F | -f)
        check_dependencies
        format_drive "$2"
        ;;  
    *)
        help
        ;;
esac
