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

# Scale down keystone in Region 2 to 0 replicas

REGION2_NAMESPACE=${REGION2_NAMESPACE:-"openstack-region2"}

echo "Scaling down keystone in ${REGION2_NAMESPACE}..."

# Get the OpenStackControlPlane name
CONTROLPLANE_NAME=$(oc get openstackcontrolplane -n ${REGION2_NAMESPACE} -o jsonpath='{.items[0].metadata.name}')

if [ -z "${CONTROLPLANE_NAME}" ]; then
    echo "ERROR: No OpenStackControlPlane found in namespace ${REGION2_NAMESPACE}"
    exit 1
fi

echo "Found OpenStackControlPlane: ${CONTROLPLANE_NAME}"

# Patch the OpenStackControlPlane to set keystone replicas to 0
echo "Patching OpenStackControlPlane to set keystone replicas to 0..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=merge -p '
{
  "spec": {
    "keystone": {
      "template": {
        "replicas": 0
      }
    }
  }
}'

echo "Waiting for keystone pods to terminate..."
timeout 300s bash -c "while oc get pods -n ${REGION2_NAMESPACE} -l service=keystone 2>/dev/null | grep -q keystone; do echo 'Waiting for keystone pods to terminate...'; sleep 5; done" || true

echo ""
echo "Keystone in Region 2 has been scaled down to 0 replicas."
echo "All Region 2 services should now be using Region 1's keystone."
echo ""
echo "Verify with:"
echo "  oc get pods -n ${REGION2_NAMESPACE} -l service=keystone"
echo "  (should show no pods running)"
