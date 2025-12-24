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
set -e

# Setup kubeconfig for managing both CRC regions

CRC_REGION1_HOME=${CRC_REGION1_HOME:-"${HOME}/.crc-region1"}
CRC_REGION2_HOME=${CRC_REGION2_HOME:-"${HOME}/.crc-region2"}

echo "Setting up multi-region kubeconfig..."

# Check if kubeconfig files exist
if [ ! -f "${CRC_REGION1_HOME}/machines/crc/kubeconfig" ]; then
    echo "ERROR: Region 1 kubeconfig not found at ${CRC_REGION1_HOME}/machines/crc/kubeconfig"
    echo "Make sure CRC region1 is deployed and running"
    exit 1
fi

if [ ! -f "${CRC_REGION2_HOME}/machines/crc/kubeconfig" ]; then
    echo "ERROR: Region 2 kubeconfig not found at ${CRC_REGION2_HOME}/machines/crc/kubeconfig"
    echo "Make sure CRC region2 is deployed and running"
    exit 1
fi

# Backup existing kubeconfig if it exists
if [ -f "${HOME}/.kube/config" ]; then
    cp "${HOME}/.kube/config" "${HOME}/.kube/config.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Create .kube directory if it doesn't exist
mkdir -p "${HOME}/.kube"

# Merge kubeconfigs
echo "Merging kubeconfig files..."
KUBECONFIG="${CRC_REGION1_HOME}/machines/crc/kubeconfig:${CRC_REGION2_HOME}/machines/crc/kubeconfig" \
kubectl config view --flatten > "${HOME}/.kube/config-multiregion"

# Rename contexts for clarity
export KUBECONFIG="${HOME}/.kube/config-multiregion"

# Get current context names
CONTEXT1=$(kubectl config get-contexts -o name | grep -v "region" | head -1 || echo "crc")
CONTEXT2=$(kubectl config get-contexts -o name | grep -v "region" | tail -1 || echo "crc2")

# Rename contexts
kubectl config rename-context "${CONTEXT1}" region1 2>/dev/null || true
kubectl config rename-context "${CONTEXT2}" region2 2>/dev/null || true

# Get IPs for both regions
CRC1_IP=$(virsh domifaddr crc 2>/dev/null | grep -oP '192\.168\.\d+\.\d+' | head -1)
CRC2_IP=$(virsh domifaddr crc2 2>/dev/null | grep -oP '192\.168\.\d+\.\d+' | head -1)

# Update server URLs to use the DNS names from /etc/hosts
if [ -n "${CRC1_IP}" ]; then
    kubectl config set-cluster region1 --server=https://api.crc.testing:6443 --insecure-skip-tls-verify=true
fi

if [ -n "${CRC2_IP}" ]; then
    kubectl config set-cluster region2 --server=https://api.crc2.testing:6443 --insecure-skip-tls-verify=true
fi

# Set default context to region1
kubectl config use-context region1

echo ""
echo "Multi-region kubeconfig created at: ${HOME}/.kube/config-multiregion"
echo ""
echo "To use this kubeconfig:"
echo "  export KUBECONFIG=${HOME}/.kube/config-multiregion"
echo ""
echo "Available contexts:"
kubectl config get-contexts
echo ""
echo "To switch between regions:"
echo "  kubectl config use-context region1"
echo "  kubectl config use-context region2"
echo ""
echo "Or use the short aliases:"
echo "  alias k1='kubectl --context=region1'"
echo "  alias k2='kubectl --context=region2'"
echo "  alias oc1='oc --context=region1'"
echo "  alias oc2='oc --context=region2'"
