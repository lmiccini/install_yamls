#!/bin/bash
#
# Setup Microshift for multi-region deployment
#

set -e

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

    # Check if system is registered
    REGISTERED=false
    if command -v subscription-manager &> /dev/null; then
        if sudo subscription-manager status &> /dev/null; then
            REGISTERED=true
        fi
    fi

    # Install Microshift
    if ! command -v microshift &> /dev/null; then
        echo "Installing Microshift..."

        # Try RHEL subscription method first if registered
        if [ "$REGISTERED" = true ]; then
            echo "System is registered, trying Red Hat repositories..."
            RHEL_VERSION=$(rpm -E %rhel)

            # Try to enable repos, but don't fail if they're not available
            if sudo subscription-manager repos --enable "rhocp-${MICROSHIFT_VERSION}-for-rhel-${RHEL_VERSION}-$(uname -m)-rpms" 2>/dev/null && \
               sudo subscription-manager repos --enable "fast-datapath-for-rhel-${RHEL_VERSION}-$(uname -m)-rpms" 2>/dev/null; then
                echo "Red Hat repositories enabled successfully"
                sudo dnf install -y microshift microshift-networking microshift-selinux
            else
                echo "Could not enable Red Hat repositories, falling back to COPR..."
                REGISTERED=false
            fi
        fi

        # Use COPR repository if not registered or if Red Hat repos failed
        if [ "$REGISTERED" = false ]; then
            echo "Using COPR repository for Microshift packages..."

            # Install COPR plugin
            sudo dnf install -y 'dnf-command(copr)'

            # Enable Microshift COPR repository
            sudo dnf copr enable -y @redhat-et/microshift

            # Install CRI-O dependencies (required for microshift)
            # These are normally in fast-datapath repo, but we need alternative source
            echo "Installing CRI-O dependencies from Kubernetes repositories..."

            # Determine OS version for CRI-O repo
            OS_VERSION=$(rpm -E %rhel)
            CRIO_VERSION="1.28"

            # Add CRI-O repository from Kubernetes project
            cat <<EOF | sudo tee /etc/yum.repos.d/cri-o.repo
[cri-o]
name=CRI-O
baseurl=https://pkgs.k8s.io/addons:/cri-o:/stable:/v${CRIO_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/addons:/cri-o:/stable:/v${CRIO_VERSION}/rpm/repodata/repomd.xml.key
EOF

            # Install CRI-O
            sudo dnf install -y cri-o

            # Install Microshift from COPR (will pull additional dependencies)
            sudo dnf install -y microshift

            # Install SELinux policies (available in COPR)
            sudo dnf install -y microshift-selinux

            # Note: microshift-networking package is not available in COPR (included in main package)
        fi
    else
        echo "Microshift already installed"
    fi
else
    echo "ERROR: This script requires RHEL, CentOS Stream, or Fedora"
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
