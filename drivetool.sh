#!/bin/bash

declare -r MOUNT_POINT="/media/flashdrive"

# Function to check for required commands
check_dependencies() {
    local dependencies=(sudo lsblk mkdir mount umount cp du grep diff rsync sync)
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
        sudo umount "$device" && echo "$device unmounted successfully." || { echo "Failed to unmount $device."; return 1; }
    fi
}

# Function to mount drive
ensure_mounted() {
    local device="$1"
    if ! mount | grep -q "$MOUNT_POINT"; then
        echo "Mounting $device..."
        sudo mkdir -p "$MOUNT_POINT"
        sudo mount "$device" "$MOUNT_POINT" || { echo "Failed to mount $device."; exit 1; }
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
        sudo cp -r "$source" "$dest_path" && echo "$source has been copied."
    else
        echo "Copying file $source to $destination using 'cp'..."
        sudo cp "$source" "$dest_path" && echo "$source has been copied."
    fi
    
    sync
    echo "Syncing file system..."
    sudo mount -o remount,sync "$MOUNT_POINT"

    # Verify copy integrity
    if sudo du -b "$source" && sudo du -b "$dest_path" && sudo diff -qr "$source" "$dest_path"; then
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
    sudo rsync -avh --progress "$source" "$destination" && echo "Files copied successfully using rsync."
}

# Function to format the drive
format_drive() {
    local device="$1"
    echo "Checking if device $device is mounted..."
    safe_unmount "$device" || return 1
    
    # Confirmation from user
    read -p "Are you sure you want to format "$device"? [y/N]: " confirm
    if [[ $confirm != [yY] ]]; then
        echo "Formatting aborted."
        return 1
    fi
    
    echo "Formatting $device..."
    sudo mkfs.exfat "$device" && echo "Drive formatted successfully." || echo "Formatting failed."
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
        ;;
    -R | -r)
        check_dependencies
        ensure_mounted "$3"
        rsync_files "$2" "$MOUNT_POINT"
        safe_unmount "$MOUNT_POINT"
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
