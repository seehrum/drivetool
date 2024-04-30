#!/bin/bash

declare -r MOUNT_POINT="/media/flashdrive"

# Function to check for required commands
check_dependencies() {
    local dependencies=(lsblk mkdir mount umount cp du grep diff)
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Required command '$cmd' is not installed." >&2
            exit 1
        fi
    done
}

# Function to check if device is mounted and unmount it
safe_unmount() {
    local device="$1"
    if mount | grep -qw "$device"; then
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
    
    echo "Wait finishing changes..."  
    sudo mount -o remount,sync "$MOUNT_POINT"

    # Verify copy integrity
    du -b "$source" "$dest_path"
    if sudo diff -qr "$source" "$dest_path"; then
        echo "Verification successful: No differences found."
    else
        echo "Verification failed: Differences found!"
        return 1
    fi
}

# Function to format the drive
format_drive() {
    local device="$1"
    echo "Checking if device $device is mounted..."
    safe_unmount "$device" || return 1
    echo "Formatting $device..."
    sudo mkfs.exfat "$device" && echo "Drive formatted successfully." || echo "Formatting failed."
}

# Function to display usage information
help() {
    echo "Usage: $0 OPTION [ARGUMENTS]"
    echo
    echo "Options:"
    echo "  -c, -C DEVICE SOURCE_PATH    Mount DEVICE and copy SOURCE_PATH to it."
    echo "  -l, -L                       List information about block devices."
    echo "  -f, -F DEVICE                Format DEVICE."
    echo
    echo "Examples:"
    echo "  $0 -C /dev/sdx /path/to/data  # Copy /path/to/data to /dev/sdx after mounting it."
    echo "  $0 -L                        # List all block devices."
    echo "  $0 -F /dev/sdx               # Format /dev/sdx."
}

# Process command-line arguments
case "$1" in
    -C | -c)
        check_dependencies
        ensure_mounted "$3"
        copy_files "$2" "$MOUNT_POINT"
        echo "Unmounting $MOUNT_POINT"
	sudo umount "$MOUNT_POINT"
        ;;
    -L | -l) lsblk -o NAME,MODEL,SERIAL,VENDOR,TRAN
	;;
    -F | -f)
        check_dependencies
        format_drive "$2"
        ;;	
    *)
	help
        ;;
esac
