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

# Setup DNS resolution for multiple CRC instances via /etc/hosts

CRC_REGION1_INSTANCE=${CRC_REGION1_INSTANCE_NAME:-"crc"}
CRC_REGION2_INSTANCE=${CRC_REGION2_INSTANCE_NAME:-"crc2"}

echo "Setting up DNS resolution for multi-CRC instances..."

# Get IP addresses of both CRC VMs
echo "Getting CRC VM IP addresses..."

# Try to get IPs from virsh domifaddr (preferred method)
CRC1_IP=$(virsh domifaddr ${CRC_REGION1_INSTANCE} 2>/dev/null | grep -oP '192\.168\.130\.\d+' | head -1)
CRC2_IP=$(virsh domifaddr ${CRC_REGION2_INSTANCE} 2>/dev/null | grep -oP '192\.168\.130\.\d+' | head -1)

# If that fails, try to get from virsh net-dhcp-leases
if [ -z "$CRC1_IP" ]; then
    CRC1_IP=$(virsh net-dhcp-leases crc 2>/dev/null | grep ${CRC_REGION1_INSTANCE} | grep -oP '192\.168\.130\.\d+' | head -1)
fi

if [ -z "$CRC2_IP" ]; then
    CRC2_IP=$(virsh net-dhcp-leases crc 2>/dev/null | grep ${CRC_REGION2_INSTANCE} | grep -oP '192\.168\.130\.\d+' | head -1)
fi

# If still empty, try alternative network ranges
if [ -z "$CRC1_IP" ]; then
    CRC1_IP=$(virsh domifaddr ${CRC_REGION1_INSTANCE} 2>/dev/null | grep -oP '192\.168\.\d+\.\d+' | head -1)
fi

if [ -z "$CRC2_IP" ]; then
    CRC2_IP=$(virsh domifaddr ${CRC_REGION2_INSTANCE} 2>/dev/null | grep -oP '192\.168\.\d+\.\d+' | head -1)
fi

if [ -z "$CRC1_IP" ]; then
    echo "ERROR: Could not get IP for ${CRC_REGION1_INSTANCE}"
    echo "Make sure the CRC VM is running: virsh list --all"
    exit 1
fi

if [ -z "$CRC2_IP" ]; then
    echo "ERROR: Could not get IP for ${CRC_REGION2_INSTANCE}"
    echo "Make sure the CRC VM is running: virsh list --all"
    exit 1
fi

echo "Region 1 CRC (${CRC_REGION1_INSTANCE}): ${CRC1_IP}"
echo "Region 2 CRC (${CRC_REGION2_INSTANCE}): ${CRC2_IP}"

# Backup /etc/hosts
sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

# Remove any existing CRC entries to avoid duplicates
sudo sed -i '/# CRC Multi-Region/d' /etc/hosts
sudo sed -i '/api\.crc.*testing/d' /etc/hosts
sudo sed -i '/apps.*crc.*testing/d' /etc/hosts
sudo sed -i '/console-openshift-console/d' /etc/hosts
sudo sed -i '/oauth-openshift/d' /etc/hosts

# Add entries for Region 1 (using standard crc.testing domain)
cat <<EOF | sudo tee -a /etc/hosts
# CRC Multi-Region - Region 1 (${CRC_REGION1_INSTANCE})
${CRC1_IP} api.crc.testing
${CRC1_IP} api-int.crc.testing
${CRC1_IP} console-openshift-console.apps.crc.testing
${CRC1_IP} oauth-openshift.apps.crc.testing
${CRC1_IP} downloads-openshift-console.apps.crc.testing
${CRC1_IP} canary-openshift-ingress-canary.apps.crc.testing
${CRC1_IP} default-route-openshift-image-registry.apps.crc.testing

# CRC Multi-Region - Region 2 (${CRC_REGION2_INSTANCE})
${CRC2_IP} api.crc2.testing
${CRC2_IP} api-int.crc2.testing
${CRC2_IP} console-openshift-console.apps.crc2.testing
${CRC2_IP} oauth-openshift.apps.crc2.testing
${CRC2_IP} downloads-openshift-console.apps.crc2.testing
${CRC2_IP} canary-openshift-ingress-canary.apps.crc2.testing
${CRC2_IP} default-route-openshift-image-registry.apps.crc2.testing
EOF

echo ""
echo "/etc/hosts has been updated with CRC DNS entries"
echo ""
echo "You can now access:"
echo "  Region 1: https://api.crc.testing:6443 (IP: ${CRC1_IP})"
echo "  Region 2: https://api.crc2.testing:6443 (IP: ${CRC2_IP})"
echo ""
echo "To test DNS resolution:"
echo "  ping -c1 api.crc.testing"
echo "  ping -c1 api.crc2.testing"
echo ""
echo "To login to each region:"
echo "  oc login -u kubeadmin -p 12345678 https://api.crc.testing:6443"
echo "  oc login -u kubeadmin -p 12345678 https://api.crc2.testing:6443"
echo ""
echo "Note: Both clusters use crc.testing certificates internally."
echo "For region2, you may need to use --insecure-skip-tls-verify if cert issues occur."
echo ""
echo "To manage both clusters, use separate kubeconfig contexts:"
echo "  export KUBECONFIG1=~/.crc-region1/machines/crc/kubeconfig"
echo "  export KUBECONFIG2=~/.crc-region2/machines/crc/kubeconfig"
echo "  or merge them: KUBECONFIG=\$KUBECONFIG1:\$KUBECONFIG2 kubectl config view --flatten > ~/.kube/config-multiregion"
