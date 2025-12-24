#!/bin/bash
#
# Setup Microshift for multi-region deployment
#

set -ex

MICROSHIFT_VERSION=${MICROSHIFT_VERSION:-"4.20"}
PULL_SECRET_FILE=${1:-"${HOME}/pull-secret.txt"}
MICROSHIFT_HOME=${MICROSHIFT_HOME:-"${HOME}/.microshift"}

echo "=== Setting up Microshift for Region 2 ==="

# Verify pull secret exists
if [ ! -f "${PULL_SECRET_FILE}" ]; then
    echo "ERROR: Pull secret file not found at ${PULL_SECRET_FILE}"
    echo "Please provide the path to your pull secret as the first argument"
    exit 1
fi

# Create microshift directory
mkdir -p "${MICROSHIFT_HOME}"

# Check if running on RHEL/Fedora
if [ -f /etc/redhat-release ]; then
    echo "Detected Red Hat-based system"

    # Install Microshift
    if ! command -v microshift &> /dev/null; then
        echo "Installing Microshift..."

        # Enable required repos (adjust for your RHEL version)
        # For RHEL 9:
        # sudo subscription-manager repos --enable rhocp-${MICROSHIFT_VERSION}-for-rhel-9-$(uname -m)-rpms
        # sudo subscription-manager repos --enable fast-datapath-for-rhel-9-$(uname -m)-rpms

        # For Fedora or if repos are already configured:
        sudo dnf install -y microshift microshift-networking microshift-selinux
    else
        echo "Microshift already installed"
    fi
else
    echo "ERROR: This script requires RHEL or Fedora"
    exit 1
fi

# Configure Microshift
echo "Configuring Microshift..."
sudo mkdir -p /etc/microshift

# Create Microshift configuration
cat <<EOF | sudo tee /etc/microshift/config.yaml
apiServer:
  subjectAltNames:
  - api.microshift.testing
  - api-int.microshift.testing
dns:
  baseDomain: microshift.testing
network:
  clusterNetwork:
  - 10.43.0.0/16
  serviceNetwork:
  - 10.44.0.0/16
node:
  hostnameOverride: microshift
  nodeIP: 127.0.0.1
EOF

# Copy pull secret
sudo mkdir -p /etc/crio
sudo cp "${PULL_SECRET_FILE}" /etc/crio/openshift-pull-secret

# Enable and start required services
echo "Starting firewalld..."
sudo systemctl enable --now firewalld

# Configure firewall
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
sudo firewall-cmd --permanent --zone=public --add-port=80/tcp
sudo firewall-cmd --permanent --zone=public --add-port=443/tcp
sudo firewall-cmd --permanent --zone=public --add-port=6443/tcp
sudo firewall-cmd --reload

# Start Microshift
echo "Starting Microshift service..."
sudo systemctl enable --now microshift

# Wait for Microshift to be ready
echo "Waiting for Microshift to be ready (this may take a few minutes)..."
timeout 300 bash -c '
while ! sudo test -f /var/lib/microshift/resources/kubeadmin/kubeconfig; do
    echo "Waiting for kubeconfig..."
    sleep 10
done
'

# Copy kubeconfig
mkdir -p "${MICROSHIFT_HOME}"
sudo cp /var/lib/microshift/resources/kubeadmin/kubeconfig "${MICROSHIFT_HOME}/kubeconfig"
sudo chown $(id -u):$(id -g) "${MICROSHIFT_HOME}/kubeconfig"

echo ""
echo "=== Microshift setup complete! ==="
echo ""
echo "Kubeconfig location: ${MICROSHIFT_HOME}/kubeconfig"
echo ""
echo "To use Microshift:"
echo "  export KUBECONFIG=${MICROSHIFT_HOME}/kubeconfig"
echo "  oc get nodes"
echo ""
echo "To stop Microshift:"
echo "  sudo systemctl stop microshift"
echo ""
echo "To start Microshift:"
echo "  sudo systemctl start microshift"
echo ""
