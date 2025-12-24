# Multi-Region OpenStack Deployment Guide

This guide describes how to deploy a multi-region OpenStack setup with CRC (Region 1) and Microshift (Region 2) on a single host.

## Architecture

- **Region 1**: CRC (OpenShift) @ 192.168.122.x, networks 172.17-20.x
- **Region 2**: Microshift (lightweight OpenShift) @ host, networks 172.27-30.x
- **Networking**: L3 routed connectivity between regions
- **Shared Keystone**: Region 2 services use Region 1's keystone for multi-region identity

## Prerequisites

1. Pull secret file (download from https://console.redhat.com/openshift/install/pull-secret)
2. **RHEL 9, CentOS Stream 9, or Fedora host**
3. Sufficient resources (16GB+ RAM, 100GB+ disk)
4. sudo access
5. **Microshift installation**: Script will automatically use COPR repository (works on all supported systems)

## Quick Start

### 1. Deploy Both Regions

```bash
# Deploy CRC for Region 1 and Microshift for Region 2
make crc_all

# This runs:
# - make crc_region1  # Deploys CRC
# - make microshift_region2  # Deploys Microshift
```

### 2. Access Each Region

**Region 1 (CRC):**
```bash
export KUBECONFIG=~/.crc/machines/crc/kubeconfig
oc login -u kubeadmin -p 12345678 https://api.crc.testing:6443
```

**Region 2 (Microshift):**
```bash
export KUBECONFIG=~/.microshift/kubeconfig
oc login -u kubeadmin https://api.microshift.testing:6443
```

### 3. Setup Networking (Optional)

If you need L3 routing between regions for inter-region communication:

```bash
make setup_region_routing
```

### 4. Deploy OpenStack Control Planes

```bash
# Deploy networking infrastructure
REGION=region1 make nncp metallb_config
REGION=region2 make nncp metallb_config

# Deploy OpenStack in both regions
make openstack_all
# This runs:
# - REGION=region1 NAMESPACE=openstack-region1 make openstack
# - REGION=region2 NAMESPACE=openstack-region2 make openstack
```

### 5. Configure Multi-Region Keystone

To share keystone between regions (Region 2 uses Region 1's keystone):

```bash
make configure_multi_region_keystone
```

This automated workflow:
1. Gets Region 1 keystone IP
2. Patches Region 2 OpenStackControlPlane to use Region 1 keystone
3. Registers Region 2 endpoints in Region 1 keystone catalog
4. Scales down Region 2 keystone to 0
5. Generates Region 2 EDPM configuration for nova-compute

### 6. Deploy EDPM Nodes

```bash
# Create EDPM VMs
REGION=region1 make -C devsetup edpm_compute EDPM_TOTAL_NODES=2
REGION=region2 make -C devsetup edpm_compute EDPM_TOTAL_NODES=2

# Deploy dataplane
make edpm_deploy_all
```

## Complete Automated Deployment

For a fully automated deployment:

```bash
make multi_region_full_deploy
```

This runs all steps in sequence. Note: You'll still need to run `make configure_multi_region_keystone` manually after Step 4.

## Manual Targets

### Region-Specific Deployments

```bash
# Deploy only Region 1
make crc_region1
REGION=region1 make nncp metallb_config
make openstack_region1
make edpm_deploy_region1

# Deploy only Region 2
make microshift_region2
REGION=region2 make nncp metallb_config
make openstack_region2
make edpm_deploy_region2
```

### Cleanup

```bash
# Cleanup Microshift (Region 2)
make -C devsetup microshift_cleanup

# Cleanup CRC (Region 1)
make -C devsetup crc_cleanup
```

## Network Configuration

### Region 1 (CRC)
- Control Plane: 192.168.122.0/24
- InternalAPI: 172.17.0.x
- Storage: 172.18.0.x
- Tenant: 172.19.0.x
- StorageMgmt: 172.20.0.x

### Region 2 (Microshift)
- Control Plane: 192.168.123.0/24 (if using isolated network)
- InternalAPI: 172.27.0.x
- Storage: 172.28.0.x
- Tenant: 172.29.0.x
- StorageMgmt: 172.30.0.x

To override network ranges:

```bash
REGION=region2 \
REGION2_NETWORK_INTERNALAPI_ADDRESS_PREFIX=172.27.0 \
REGION2_NETWORK_STORAGE_ADDRESS_PREFIX=172.28.0 \
make nncp
```

## EDPM Node Configuration

Configure number of nodes per region:

```bash
# Region 1: 3 compute nodes
REGION=region1 REGION1_DATAPLANE_TOTAL_NODES=3 \
make -C devsetup edpm_compute

# Region 2: 2 compute nodes
REGION=region2 REGION2_DATAPLANE_TOTAL_NODES=2 \
make -C devsetup edpm_compute
```

## Troubleshooting

### Microshift packages not available

**Error:**
```
No match for argument: microshift
No match for argument: microshift-networking
```

**Solution:**

The script automatically uses COPR repository which works on RHEL 9, CentOS Stream 9, and Fedora. This error usually means:

1. **Network connectivity issue** - Check internet connection
2. **COPR plugin missing** - Script will install it automatically

The installation flow:
- If RHEL is registered → Try Red Hat repos first, fallback to COPR
- If not registered → Use COPR repository + Kubernetes repos for CRI-O

To manually enable COPR and install:
```bash
# Install COPR plugin
sudo dnf install -y 'dnf-command(copr)'

# Enable Microshift COPR
sudo dnf copr enable -y @redhat-et/microshift

# Add Kubernetes repository (provides cri-tools)
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF

# Add CRI-O repository (provides cri-o)
cat <<EOF | sudo tee /etc/yum.repos.d/cri-o.repo
[cri-o]
name=CRI-O
baseurl=https://pkgs.k8s.io/addons:/cri-o:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/addons:/cri-o:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF

# Install CRI-O and cri-tools
sudo dnf install -y cri-o cri-tools

# Install Microshift
sudo dnf install -y microshift microshift-selinux
```

**Note**:
- The COPR repository provides `microshift` and `microshift-selinux` packages
- The `microshift-networking` package is only available in official Red Hat repositories (networking functionality is included in the main COPR package)
- Container runtime dependencies (`cri-o` and `cri-tools`) are installed from Kubernetes repositories when using COPR on unregistered systems

**Alternative Option: Use K3s for Region 2**

If COPR is not accessible, you can use K3s as a lightweight Kubernetes alternative:

```bash
# Install K3s
curl -sfL https://get.k3s.io | sh -

# Get kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config-k3s
sudo chown $(id -u):$(id -g) ~/.kube/config-k3s

# Use it
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
```

### Microshift not starting
```bash
# Check service status
sudo systemctl status microshift

# Check logs
sudo journalctl -u microshift -f

# Verify kubeconfig exists
ls -la ~/.microshift/kubeconfig
```

### Cannot access Microshift API
```bash
# Verify Microshift is running
sudo systemctl status microshift

# Check for kubeconfig
export KUBECONFIG=~/.microshift/kubeconfig
oc get nodes
```

### Region 2 services not using Region 1 keystone
```bash
# Verify the patch was applied
oc get openstackcontrolplane -n openstack-region2 -o yaml | grep keystone

# Re-run keystone configuration
make configure_multi_region_keystone
```

## Key Differences from CRC-CRC Multi-Region

1. **Simpler Setup**: No VM cloning, no complex networking
2. **Resource Efficient**: Microshift uses less memory than full CRC
3. **Independent Clusters**: Each region is truly independent
4. **Native DNS**: Microshift has its own domain (microshift.testing)
5. **Direct Access**: Microshift runs on host, easier debugging

## Files Modified

- `Makefile`: Multi-region targets and network configuration
- `devsetup/Makefile`: Added Microshift targets
- `devsetup/scripts/microshift-setup.sh`: Microshift installation script
- `devsetup/scripts/crc-setup.sh`: Removed CRC multi-instance code
- `scripts/gen-edpm-kustomize.sh`: Region suffix for EDPM nodes
- `devsetup/scripts/gen-edpm-node-common.sh`: Region suffix for VM names

## Files Removed (Obsolete CRC Cloning Approach)

- `scripts/clone-crc-vm.sh`: VM cloning (not needed)
- `scripts/cleanup-crc-clone.sh`: Cloning cleanup (not needed)
- `scripts/setup-crc-multi-dns.sh`: Multi-CRC DNS (not needed)
