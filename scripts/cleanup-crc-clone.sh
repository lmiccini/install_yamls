#!/bin/bash
#
# Cleanup a cloned CRC instance
#

set -e

TARGET_VM=${1:-"crc2"}
TARGET_NETWORK=${2:-"crc2"}

echo "=== Cleaning up cloned CRC instance ==="
echo "Target VM: ${TARGET_VM}"
echo "Target Network: ${TARGET_NETWORK}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run with sudo"
    exit 1
fi

# Stop and undefine VM if it exists
if virsh dominfo "${TARGET_VM}" &>/dev/null; then
    echo "Removing VM: ${TARGET_VM}"
    virsh destroy "${TARGET_VM}" 2>/dev/null || true
    virsh undefine "${TARGET_VM}" --remove-all-storage 2>/dev/null || virsh undefine "${TARGET_VM}" 2>/dev/null || true
fi

# Stop and undefine network if it exists
if virsh net-info "${TARGET_NETWORK}" &>/dev/null; then
    echo "Removing network: ${TARGET_NETWORK}"
    virsh net-destroy "${TARGET_NETWORK}" 2>/dev/null || true
    virsh net-undefine "${TARGET_NETWORK}" 2>/dev/null || true
fi

# Remove any orphaned disk files
echo "Checking for orphaned disk files..."
DISK_PATTERN="/home/*/.crc/machines/crc/*-${TARGET_VM}.qcow2"
for disk in ${DISK_PATTERN}; do
    if [ -f "$disk" ]; then
        echo "Removing disk: $disk"
        rm -f "$disk"
    fi
done

echo ""
echo "Cleanup complete!"
