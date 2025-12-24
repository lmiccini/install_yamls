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

# Configure keystone endpoints for Region 2 in Region 1's keystone

REGION1_NAMESPACE=${REGION1_NAMESPACE:-"openstack-region1"}
REGION2_NAMESPACE=${REGION2_NAMESPACE:-"openstack-region2"}
REGION1_NAME=${REGION1_NAME:-"regionOne"}
REGION2_NAME=${REGION2_NAME:-"regionTwo"}

# Get Region 1 keystone URL (should be accessible from both regions via MetalLB)
echo "Getting Region 1 keystone URL..."
REGION1_KEYSTONE_IP=$(oc get svc -n ${REGION1_NAMESPACE} keystone-internal -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "${REGION1_KEYSTONE_IP}" ]; then
    echo "ERROR: Could not get Region 1 keystone LoadBalancer IP"
    echo "Make sure keystone service is deployed with LoadBalancer type in ${REGION1_NAMESPACE}"
    exit 1
fi

REGION1_KEYSTONE_URL="http://${REGION1_KEYSTONE_IP}:5000"
echo "Region 1 Keystone URL: ${REGION1_KEYSTONE_URL}"

# Get Region 2 service endpoints
echo "Getting Region 2 service endpoints..."

# Function to get service endpoint
get_service_endpoint() {
    local service=$1
    local namespace=$2
    local port=$3

    local ip=$(oc get svc -n ${namespace} ${service} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -z "${ip}" ]; then
        echo ""
        return 1
    fi
    echo "http://${ip}:${port}"
}

# Get endpoints for Region 2 services
NOVA_ENDPOINT=$(get_service_endpoint "nova-internal" "${REGION2_NAMESPACE}" "8774")
PLACEMENT_ENDPOINT=$(get_service_endpoint "placement-internal" "${REGION2_NAMESPACE}" "8778")
NEUTRON_ENDPOINT=$(get_service_endpoint "neutron-internal" "${REGION2_NAMESPACE}" "9696")
CINDER_ENDPOINT=$(get_service_endpoint "cinder-internal" "${REGION2_NAMESPACE}" "8776")
GLANCE_ENDPOINT=$(get_service_endpoint "glance-default-internal" "${REGION2_NAMESPACE}" "9292")

# Create a pod to run openstack commands in Region 1
echo "Creating openstack client pod in Region 1..."
cat <<EOF | oc apply -n ${REGION1_NAMESPACE} -f -
apiVersion: v1
kind: Pod
metadata:
  name: region2-endpoint-config
  labels:
    app: region2-endpoint-config
spec:
  containers:
  - name: openstackclient
    image: quay.io/podified-antelope-centos9/openstack-openstackclient:current-podified
    command: ["sleep", "infinity"]
    env:
    - name: OS_AUTH_URL
      value: "${REGION1_KEYSTONE_URL}"
    - name: OS_PROJECT_NAME
      value: "admin"
    - name: OS_USERNAME
      value: "admin"
    - name: OS_PASSWORD
      value: "12345678"
    - name: OS_USER_DOMAIN_NAME
      value: "Default"
    - name: OS_PROJECT_DOMAIN_NAME
      value: "Default"
  restartPolicy: Never
EOF

# Wait for pod to be ready
echo "Waiting for openstack client pod to be ready..."
oc wait --for=condition=Ready pod/region2-endpoint-config -n ${REGION1_NAMESPACE} --timeout=300s

# Create Region 2 keystone endpoints (pointing to Region 1's keystone)
echo "Creating keystone endpoints for Region 2..."
oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} identity public ${REGION1_KEYSTONE_URL} || true
oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} identity internal ${REGION1_KEYSTONE_URL} || true

# Create other service endpoints for Region 2
if [ -n "${NOVA_ENDPOINT}" ]; then
    echo "Creating nova endpoints for Region 2..."
    oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} compute public ${NOVA_ENDPOINT}/v2.1 || true
    oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} compute internal ${NOVA_ENDPOINT}/v2.1 || true
fi

if [ -n "${PLACEMENT_ENDPOINT}" ]; then
    echo "Creating placement endpoints for Region 2..."
    oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} placement public ${PLACEMENT_ENDPOINT} || true
    oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} placement internal ${PLACEMENT_ENDPOINT} || true
fi

if [ -n "${NEUTRON_ENDPOINT}" ]; then
    echo "Creating neutron endpoints for Region 2..."
    oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} network public ${NEUTRON_ENDPOINT} || true
    oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} network internal ${NEUTRON_ENDPOINT} || true
fi

if [ -n "${CINDER_ENDPOINT}" ]; then
    echo "Creating cinder endpoints for Region 2..."
    oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} volumev3 public ${CINDER_ENDPOINT}/v3/'$(project_id)s' || true
    oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} volumev3 internal ${CINDER_ENDPOINT}/v3/'$(project_id)s' || true
fi

if [ -n "${GLANCE_ENDPOINT}" ]; then
    echo "Creating glance endpoints for Region 2..."
    oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} image public ${GLANCE_ENDPOINT} || true
    oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint create --region ${REGION2_NAME} image internal ${GLANCE_ENDPOINT} || true
fi

# List all endpoints to verify
echo "Listing all endpoints in Region 1 keystone:"
oc exec -n ${REGION1_NAMESPACE} region2-endpoint-config -- openstack endpoint list

# Cleanup
echo "Cleaning up temporary pod..."
oc delete pod region2-endpoint-config -n ${REGION1_NAMESPACE} --ignore-not-found=true

echo ""
echo "Region 2 endpoint configuration complete!"
echo "Region 1 Keystone URL: ${REGION1_KEYSTONE_URL}"
echo ""
echo "Next steps:"
echo "1. Update Region 2 OpenStackControlPlane CR to use Region 1's keystone"
echo "2. Run: make scale_down_region2_keystone"
