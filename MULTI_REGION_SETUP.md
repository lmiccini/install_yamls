# Multi-Region OpenStack Deployment Guide

This guide describes how to deploy a multi-region OpenStack setup with two SNO (Single Node OpenShift) instances on a single host.

## Architecture

- **Region 1**: SNO @ 192.168.122.x, networks 172.17-20.x
- **Region 2**: SNO @ 192.168.123.x, networks 172.27-30.x
- **Networking**: L3 routed connectivity between regions
- **Shared Keystone**: Region 2 services use Region 1's keystone for multi-region identity

## Prerequisites

1. Pull secret file (download from https://console.redhat.com/openshift/install/pull-secret)
2. **RHEL 9, CentOS Stream 9, or Fedora host**
3. Sufficient resources (**64GB+ RAM recommended**, 300GB+ disk for two SNO instances)
4. sudo access
5. SSH public key at `~/.ssh/id_rsa.pub`

## Quick Start

### 1. Deploy Both Regions

```bash
# Deploy SNO for both regions (this takes 30-45 minutes)
make sno_all

# This runs:
# - make sno_region1  # Deploys SNO for Region 1
# - make sno_region2  # Deploys SNO for Region 2
```

### 2. Access Each Region

**Region 1 (SNO):**
```bash
export KUBECONFIG=~/.sno-region1/ocp/auth/kubeconfig
oc login -u kubeadmin -p 12345678 https://api.sno-region1.example.com:6443
```

**Region 2 (SNO):**
```bash
export KUBECONFIG=~/.sno-region2/ocp/auth/kubeconfig
oc login -u kubeadmin -p 12345678 https://api.sno-region2.example.com:6443
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
# Cleanup both SNO instances
make sno_cleanup_all

# Or cleanup individually
make sno_cleanup_region1
make sno_cleanup_region2
```

## Network Configuration

### Region 1 (SNO)
- Control Plane: 192.168.122.0/24
- InternalAPI: 172.17.0.x
- Storage: 172.18.0.x
- Tenant: 172.19.0.x
- StorageMgmt: 172.20.0.x

### Region 2 (SNO)
- Control Plane: 192.168.123.0/24
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

### SNO deployment taking too long

SNO installation typically takes 30-45 minutes. If it's taking longer:

```bash
# Check VM status
virsh list --all

# Check SNO bootstrap progress
tail -f ~/.sno-region1/.openshift_install.log

# Check VM console
virsh console sno-region1
```

### SNO deployment failed

```bash
# Check the installation log
cat ~/.sno-region1/.openshift_install.log

# Common issues:
# 1. Insufficient resources (need 32GB+ RAM per SNO)
# 2. Network connectivity to pull container images
# 3. Pull secret expired or invalid
```

### Cannot access SNO API

```bash
# Verify SNO VM is running
virsh list | grep sno-region

# Check if API is responsive
export KUBECONFIG=~/.sno-region1/ocp/auth/kubeconfig
oc get nodes

# Get cluster status
oc get co  # Check cluster operators
```

### Region 2 services not using Region 1 keystone
```bash
# Verify the patch was applied
oc get openstackcontrolplane -n openstack-region2 -o yaml | grep keystone

# Re-run keystone configuration
make configure_multi_region_keystone
```

## Key Features

1. **Full OpenShift**: Both regions run complete OpenShift with all operators
2. **Independent Clusters**: Each SNO is fully independent with its own API, networking, and storage
3. **Production-like**: SNO is closer to production OpenShift than CRC
4. **Flexible Networking**: Each SNO on separate libvirt network with L3 routing
5. **Persistent**: SNO installations persist across reboots unlike CRC

## Files Modified

- `Makefile`: Multi-region SNO targets and network configuration
- `devsetup/Makefile`: Added SNO region-specific targets
- `scripts/setup-region-routing.sh`: Updated for CRC-to-Microshift routing (will be updated for SNO-to-SNO)
- `scripts/gen-edpm-kustomize.sh`: Region suffix for EDPM nodes
- `devsetup/scripts/gen-edpm-node-common.sh`: Region suffix for VM names

## Implementation Notes

- Uses existing `devsetup/scripts/ipv6-nat64/sno.sh` script
- Each SNO gets its own work directory (`~/.sno-region1`, `~/.sno-region2`)
- Separate libvirt networks for each region
- L3 routing configured on host for inter-region communication
