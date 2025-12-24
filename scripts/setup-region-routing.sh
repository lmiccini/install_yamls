#!/bin/bash
#
# Copyright 2024 Red Hat Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
set -ex

# Setup L3 routing between Region 1 (CRC) and Region 2 (Microshift/host)

# Default values
REGION1_CTLPLANE_NETWORK=${REGION1_CTLPLANE_NETWORK:-"192.168.122.0/24"}
CRC_INSTANCE=${CRC_INSTANCE_NAME:-"crc"}

# Region 1 networks
REGION1_INTERNALAPI_NETWORK=${REGION1_NETWORK_INTERNALAPI_ADDRESS_PREFIX:-"172.17.0"}.0/16
REGION1_STORAGE_NETWORK=${REGION1_NETWORK_STORAGE_ADDRESS_PREFIX:-"172.18.0"}.0/16
REGION1_TENANT_NETWORK=${REGION1_NETWORK_TENANT_ADDRESS_PREFIX:-"172.19.0"}.0/16
REGION1_STORAGEMGMT_NETWORK=${REGION1_NETWORK_STORAGEMGMT_ADDRESS_PREFIX:-"172.20.0"}.0/16

# Region 2 networks
REGION2_INTERNALAPI_NETWORK=${REGION2_NETWORK_INTERNALAPI_ADDRESS_PREFIX:-"172.27.0"}.0/16
REGION2_STORAGE_NETWORK=${REGION2_NETWORK_STORAGE_ADDRESS_PREFIX:-"172.28.0"}.0/16
REGION2_TENANT_NETWORK=${REGION2_NETWORK_TENANT_ADDRESS_PREFIX:-"172.29.0"}.0/16
REGION2_STORAGEMGMT_NETWORK=${REGION2_NETWORK_STORAGEMGMT_ADDRESS_PREFIX:-"172.30.0"}.0/16

# Gateway IPs
REGION1_GATEWAY="192.168.122.1"
REGION2_GATEWAY="192.168.123.1"

echo "Setting up L3 routing between regions..."
echo "Region 1: ${REGION1_CTLPLANE_NETWORK} (CRC VM: ${CRC_INSTANCE})"
echo "Region 2: Microshift networks (running on host)"

# Enable IP forwarding on host
echo "Enabling IP forwarding on host..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1

# Make IP forwarding persistent
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi
if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf
fi

# Configure firewall rules to allow inter-region traffic
echo "Configuring firewall rules..."

# Use firewalld direct rules for persistent configuration
# Allow forwarding for Region 1 networks
for NETWORK in ${REGION1_INTERNALAPI_NETWORK} ${REGION1_STORAGE_NETWORK} ${REGION1_TENANT_NETWORK} ${REGION1_STORAGEMGMT_NETWORK}; do
    sudo firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -s ${NETWORK} -j ACCEPT || true
    sudo firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -d ${NETWORK} -j ACCEPT || true
done

# Allow forwarding for Region 2 networks
for NETWORK in ${REGION2_INTERNALAPI_NETWORK} ${REGION2_STORAGE_NETWORK} ${REGION2_TENANT_NETWORK} ${REGION2_STORAGEMGMT_NETWORK}; do
    sudo firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -s ${NETWORK} -j ACCEPT || true
    sudo firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -d ${NETWORK} -j ACCEPT || true
done

sudo firewall-cmd --reload

# Add static routes on CRC VM (Region 1)
echo "Adding static routes on CRC VM..."

# Check if CRC VM is running
if ! virsh list --name | grep -q "^${CRC_INSTANCE}$"; then
    echo "Warning: CRC instance '${CRC_INSTANCE}' is not running. Skipping route configuration."
else
    # Get CRC VM IP
    CRC_IP=$(virsh domifaddr ${CRC_INSTANCE} | grep -oP '192\.168\.122\.\d+' | head -1)
    if [ -n "${CRC_IP}" ]; then
        echo "Configuring routes on CRC VM (${CRC_IP})..."

        # Add routes to Region 2 networks via host gateway
        # These routes allow CRC to reach Microshift networks on the host
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC_IP} \
            "sudo ip route add ${REGION2_INTERNALAPI_NETWORK} via ${REGION1_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC_IP} \
            "sudo ip route add ${REGION2_STORAGE_NETWORK} via ${REGION1_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC_IP} \
            "sudo ip route add ${REGION2_TENANT_NETWORK} via ${REGION1_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC_IP} \
            "sudo ip route add ${REGION2_STORAGEMGMT_NETWORK} via ${REGION1_GATEWAY} || true"
    else
        echo "Warning: Could not determine IP address for ${CRC_INSTANCE}"
    fi
fi

echo ""
echo "=== Region routing setup complete! ==="
echo ""
echo "Note: Region 2 (Microshift) runs on the host and has direct access to all networks."
echo "Region 1 (CRC VM) has been configured with routes to reach Region 2 networks."
