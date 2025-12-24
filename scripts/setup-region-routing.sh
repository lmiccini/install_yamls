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

# Setup L3 routing between two CRC regions

# Default values
REGION1_CTLPLANE_NETWORK=${REGION1_CTLPLANE_NETWORK:-"192.168.122.0/24"}
REGION2_CTLPLANE_NETWORK=${REGION2_CTLPLANE_NETWORK:-"192.168.123.0/24"}
CRC1_INSTANCE=${CRC_REGION1_INSTANCE_NAME:-"crc"}
CRC2_INSTANCE=${CRC_REGION2_INSTANCE_NAME:-"crc2"}

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
echo "Region 1: ${REGION1_CTLPLANE_NETWORK} (instance: ${CRC1_INSTANCE})"
echo "Region 2: ${REGION2_CTLPLANE_NETWORK} (instance: ${CRC2_INSTANCE})"

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

# Configure iptables FORWARD rules to allow inter-region traffic
echo "Configuring iptables FORWARD rules..."

# Allow traffic from Region 1 to Region 2
sudo iptables -C FORWARD -s ${REGION1_CTLPLANE_NETWORK} -d ${REGION2_CTLPLANE_NETWORK} -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -s ${REGION1_CTLPLANE_NETWORK} -d ${REGION2_CTLPLANE_NETWORK} -j ACCEPT

# Allow traffic from Region 2 to Region 1
sudo iptables -C FORWARD -s ${REGION2_CTLPLANE_NETWORK} -d ${REGION1_CTLPLANE_NETWORK} -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -s ${REGION2_CTLPLANE_NETWORK} -d ${REGION1_CTLPLANE_NETWORK} -j ACCEPT

# Allow traffic between isolated networks
for NET1 in ${REGION1_INTERNALAPI_NETWORK} ${REGION1_STORAGE_NETWORK} ${REGION1_TENANT_NETWORK} ${REGION1_STORAGEMGMT_NETWORK}; do
    for NET2 in ${REGION2_INTERNALAPI_NETWORK} ${REGION2_STORAGE_NETWORK} ${REGION2_TENANT_NETWORK} ${REGION2_STORAGEMGMT_NETWORK}; do
        sudo iptables -C FORWARD -s ${NET1} -d ${NET2} -j ACCEPT 2>/dev/null || \
            sudo iptables -A FORWARD -s ${NET1} -d ${NET2} -j ACCEPT
        sudo iptables -C FORWARD -s ${NET2} -d ${NET1} -j ACCEPT 2>/dev/null || \
            sudo iptables -A FORWARD -s ${NET2} -d ${NET1} -j ACCEPT
    done
done

# Add static routes on CRC instances
echo "Adding static routes on CRC instances..."

# Check if we can SSH to CRC instances
if ! virsh list --name | grep -q "^${CRC1_INSTANCE}$"; then
    echo "Warning: CRC instance '${CRC1_INSTANCE}' is not running. Skipping route configuration for Region 1."
else
    # Get Region 1 CRC IP
    CRC1_IP=$(virsh domifaddr ${CRC1_INSTANCE} | grep -oP '192\.168\.122\.\d+' | head -1)
    if [ -n "${CRC1_IP}" ]; then
        echo "Configuring routes on Region 1 CRC (${CRC1_IP})..."

        # Add routes to Region 2 networks via host gateway
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC1_IP} \
            "sudo ip route add ${REGION2_CTLPLANE_NETWORK} via ${REGION1_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC1_IP} \
            "sudo ip route add ${REGION2_INTERNALAPI_NETWORK} via ${REGION1_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC1_IP} \
            "sudo ip route add ${REGION2_STORAGE_NETWORK} via ${REGION1_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC1_IP} \
            "sudo ip route add ${REGION2_TENANT_NETWORK} via ${REGION1_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC1_IP} \
            "sudo ip route add ${REGION2_STORAGEMGMT_NETWORK} via ${REGION1_GATEWAY} || true"
    else
        echo "Warning: Could not determine IP address for ${CRC1_INSTANCE}"
    fi
fi

if ! virsh list --name | grep -q "^${CRC2_INSTANCE}$"; then
    echo "Warning: CRC instance '${CRC2_INSTANCE}' is not running. Skipping route configuration for Region 2."
else
    # Get Region 2 CRC IP
    CRC2_IP=$(virsh domifaddr ${CRC2_INSTANCE} | grep -oP '192\.168\.123\.\d+' | head -1)
    if [ -n "${CRC2_IP}" ]; then
        echo "Configuring routes on Region 2 CRC (${CRC2_IP})..."

        # Add routes to Region 1 networks via host gateway
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC2_IP} \
            "sudo ip route add ${REGION1_CTLPLANE_NETWORK} via ${REGION2_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC2_IP} \
            "sudo ip route add ${REGION1_INTERNALAPI_NETWORK} via ${REGION2_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC2_IP} \
            "sudo ip route add ${REGION1_STORAGE_NETWORK} via ${REGION2_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC2_IP} \
            "sudo ip route add ${REGION1_TENANT_NETWORK} via ${REGION2_GATEWAY} || true"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${CRC2_IP} \
            "sudo ip route add ${REGION1_STORAGEMGMT_NETWORK} via ${REGION2_GATEWAY} || true"
    else
        echo "Warning: Could not determine IP address for ${CRC2_INSTANCE}"
    fi
fi

echo "Region routing setup complete!"
echo ""
echo "To test connectivity:"
echo "  - From Region 1: ping ${CRC2_IP}"
echo "  - From Region 2: ping ${CRC1_IP}"
