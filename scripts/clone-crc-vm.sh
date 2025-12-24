#!/bin/bash
#
# Clone an existing CRC VM to create a second instance for multi-region
#

set -e

SOURCE_VM=${1:-"crc"}
TARGET_VM=${2:-"crc2"}
TARGET_NETWORK=${3:-"crc2"}

echo "=== Cloning CRC VM for multi-region setup ==="
echo "Source VM: ${SOURCE_VM}"
echo "Target VM: ${TARGET_VM}"
echo "Target Network: ${TARGET_NETWORK}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run with sudo"
    exit 1
fi

# Check if source VM exists
if ! virsh dominfo "${SOURCE_VM}" &>/dev/null; then
    echo "ERROR: Source VM '${SOURCE_VM}' does not exist"
    exit 1
fi

# Check if target VM already exists
if virsh dominfo "${TARGET_VM}" &>/dev/null; then
    echo "ERROR: Target VM '${TARGET_VM}' already exists"
    echo "Remove it first with: virsh undefine ${TARGET_VM} --remove-all-storage"
    exit 1
fi

echo "Step 1: Shutting down source VM..."
virsh shutdown "${SOURCE_VM}" || true
echo "Waiting for VM to shut down..."
timeout 60 bash -c "while virsh domstate ${SOURCE_VM} | grep -q running; do sleep 2; done" || true

echo ""
echo "Step 2: Cloning VM disk..."
SOURCE_DISK=$(virsh domblklist "${SOURCE_VM}" | grep -oP '/.*\.qcow2' | head -1)
if [ -z "${SOURCE_DISK}" ]; then
    echo "ERROR: Could not find source disk for ${SOURCE_VM}"
    exit 1
fi

TARGET_DISK="${SOURCE_DISK%.qcow2}-${TARGET_VM}.qcow2"
echo "Source disk: ${SOURCE_DISK}"
echo "Target disk: ${TARGET_DISK}"

# Create a full independent copy (not COW) so both VMs can run simultaneously
echo "Creating full disk copy (this may take a few minutes)..."
qemu-img convert -O qcow2 "${SOURCE_DISK}" "${TARGET_DISK}"

echo ""
echo "Step 3: Cloning VM definition..."
virsh dumpxml "${SOURCE_VM}" > /tmp/${SOURCE_VM}.xml

# Check if NVRAM is used and copy it
NVRAM_PATH=$(grep -oP '(?<=<nvram>).*(?=</nvram>)' /tmp/${SOURCE_VM}.xml || true)
if [ -n "${NVRAM_PATH}" ]; then
    echo "Copying NVRAM file..."
    NVRAM_DIR=$(dirname "${NVRAM_PATH}")
    NVRAM_FILE=$(basename "${NVRAM_PATH}")
    TARGET_NVRAM="${NVRAM_DIR}/${TARGET_VM}_${NVRAM_FILE}"
    cp "${NVRAM_PATH}" "${TARGET_NVRAM}"
    # Update XML with new NVRAM path
    sed -i "s|${NVRAM_PATH}|${TARGET_NVRAM}|g" /tmp/${SOURCE_VM}.xml
fi

# Modify XML for new VM
sed -i "s|<name>${SOURCE_VM}</name>|<name>${TARGET_VM}</name>|" /tmp/${SOURCE_VM}.xml
sed -i "s|${SOURCE_DISK}|${TARGET_DISK}|g" /tmp/${SOURCE_VM}.xml
sed -i "s|<uuid>.*</uuid>|$(uuidgen | sed 's/^/<uuid>/' | sed 's/$/<\/uuid>/')|" /tmp/${SOURCE_VM}.xml
# Remove MAC addresses to get new ones
sed -i "/<mac address=/d" /tmp/${SOURCE_VM}.xml

# Define new VM
virsh define /tmp/${SOURCE_VM}.xml
rm /tmp/${SOURCE_VM}.xml

echo ""
echo "Step 4: Cloning libvirt network..."
virsh net-dumpxml crc > /tmp/crc-network.xml

# Modify network XML
sed -i "s|<name>crc</name>|<name>${TARGET_NETWORK}</name>|" /tmp/crc-network.xml
sed -i "s|<uuid>.*</uuid>|$(uuidgen | sed 's/^/<uuid>/' | sed 's/$/<\/uuid>/')|" /tmp/crc-network.xml

# Change bridge name to avoid conflicts (bridge='crc' -> bridge='crc2')
sed -i "s|bridge='crc'|bridge='${TARGET_NETWORK}'|g" /tmp/crc-network.xml
sed -i "s|bridge name='crc'|bridge name='${TARGET_NETWORK}'|g" /tmp/crc-network.xml

# Change network range to avoid conflicts (192.168.130.x -> 192.168.131.x for crc2)
sed -i "s|192\.168\.130\.|192.168.131.|g" /tmp/crc-network.xml

# Define and start new network
virsh net-define /tmp/crc-network.xml
virsh net-start "${TARGET_NETWORK}"
virsh net-autostart "${TARGET_NETWORK}"
rm /tmp/crc-network.xml

echo ""
echo "Step 5: Updating VM network attachment..."
# Update the VM's network interface to use new network
virsh dumpxml "${TARGET_VM}" > /tmp/${TARGET_VM}-update.xml
sed -i "s|<source network='crc'/>|<source network='${TARGET_NETWORK}'/>|g" /tmp/${TARGET_VM}-update.xml
virsh define /tmp/${TARGET_VM}-update.xml
rm /tmp/${TARGET_VM}-update.xml

echo ""
echo "Step 6: Starting VMs..."
virsh start "${SOURCE_VM}"
virsh start "${TARGET_VM}"

echo ""
echo "=== Clone complete! ==="
echo ""
echo "VMs:"
virsh list --all | grep -E "(${SOURCE_VM}|${TARGET_VM})"
echo ""
echo "Networks:"
virsh net-list --all | grep -E "(crc|${TARGET_NETWORK})"
echo ""
echo "Next steps:"
echo "1. Wait for both VMs to boot (2-3 minutes)"
echo "2. Run: make setup_crc_multi_dns"
echo "3. Extract kubeconfigs from both VMs"
echo ""
