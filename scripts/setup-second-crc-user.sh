#!/bin/bash
#
# Setup a second CRC instance using a different system user
# This script helps configure the second user and rename CRC resources
#

set -e

SECOND_USER=${1:-"crc2user"}
SECOND_VM_NAME=${2:-"crc2"}
SECOND_NETWORK_NAME=${3:-"crc2"}

echo "=== Setting up second CRC instance for multi-region ==="
echo ""
echo "This script will:"
echo "1. Create a second system user: ${SECOND_USER}"
echo "2. Configure CRC for that user"
echo "3. Rename the VM and network to avoid conflicts"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Create second user if it doesn't exist
if ! id "${SECOND_USER}" &>/dev/null; then
    echo "Creating user: ${SECOND_USER}"
    useradd -m -G libvirt "${SECOND_USER}"
    echo "${SECOND_USER}:password123" | chpasswd
    echo "User ${SECOND_USER} created with password: password123"
else
    echo "User ${SECOND_USER} already exists"
fi

# Create helper script for second user
cat > /tmp/setup-crc-second-user-helper.sh <<'EOF'
#!/bin/bash
set -e

CRC_URL="$1"
KUBEADMIN_PWD="$2"
PULL_SECRET_FILE="$3"

# Download and install CRC binary
mkdir -p ~/bin
if [ ! -f ~/bin/crc ]; then
    echo "Installing CRC binary..."
    curl -L "${CRC_URL}" | tar --wildcards -U --strip-components=1 -C ~/bin -xJf - '*crc'
    chmod +x ~/bin/crc
fi

export PATH="$HOME/bin:$PATH"

# Configure CRC (same config as primary instance)
crc config set network-mode system
crc config set consent-telemetry no
crc config set kubeadmin-password "${KUBEADMIN_PWD}"
crc config set pull-secret-file "${PULL_SECRET_FILE}"
crc config set skip-check-daemon-systemd-unit true
crc config set skip-check-daemon-systemd-sockets true
crc config set cpus 4
crc config set memory 10752
crc config set disk-size 31

# Run setup
crc setup

echo "CRC setup complete for second user"
echo "VM will be renamed before starting to avoid conflicts"
EOF

chmod +x /tmp/setup-crc-second-user-helper.sh

echo ""
echo "Next steps:"
echo "1. Run CRC setup as the second user:"
echo "   sudo -u ${SECOND_USER} /tmp/setup-crc-second-user-helper.sh <CRC_URL> <KUBEADMIN_PWD> <PULL_SECRET_FILE>"
echo ""
echo "2. After setup, use the rename-crc-vm.sh script to rename resources before starting"
echo ""
