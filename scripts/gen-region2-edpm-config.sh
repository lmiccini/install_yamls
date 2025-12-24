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

# Generate custom OpenStackDataPlaneService for Region 2 EDPM nodes
# This configures nova-compute to use Region 1's keystone

REGION1_KEYSTONE_URL=${REGION1_KEYSTONE_URL:-""}
REGION2_NAMESPACE=${REGION2_NAMESPACE:-"openstack-region2"}
REGION1_NAME=${REGION1_NAME:-"regionOne"}
REGION2_NAME=${REGION2_NAME:-"regionTwo"}
OUTPUT_DIR=${OUTPUT_DIR:-"${PWD}/out/region2-edpm"}

if [ -z "${REGION1_KEYSTONE_URL}" ]; then
    echo "ERROR: REGION1_KEYSTONE_URL must be set"
    echo "Example: export REGION1_KEYSTONE_URL=http://192.168.122.80:5000"
    exit 1
fi

mkdir -p ${OUTPUT_DIR}

echo "Generating Region 2 EDPM configuration..."
echo "Region 1 Keystone URL: ${REGION1_KEYSTONE_URL}"
echo "Region 2 Namespace: ${REGION2_NAMESPACE}"

# Create a custom nova compute configuration for Region 2
cat > ${OUTPUT_DIR}/nova-compute-region2-config.conf <<EOF
[DEFAULT]

[keystone_authtoken]
auth_url = ${REGION1_KEYSTONE_URL}
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = 12345678
region_name = ${REGION1_NAME}
service_token_roles_required = true

[placement]
auth_url = ${REGION1_KEYSTONE_URL}
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = 12345678
region_name = ${REGION1_NAME}
valid_interfaces = internal

[glance]
auth_url = ${REGION1_KEYSTONE_URL}
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = 12345678
region_name = ${REGION1_NAME}
valid_interfaces = internal

[neutron]
auth_url = ${REGION1_KEYSTONE_URL}
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = 12345678
region_name = ${REGION1_NAME}
valid_interfaces = internal
service_metadata_proxy = true

[cinder]
auth_url = ${REGION1_KEYSTONE_URL}
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = 12345678
region_name = ${REGION1_NAME}
valid_interfaces = internal
EOF

# Create a ConfigMap with the nova compute configuration
echo "Creating ConfigMap with nova-compute configuration for Region 2..."
oc create configmap nova-compute-region2-config \
    --from-file=02-nova-region2.conf=${OUTPUT_DIR}/nova-compute-region2-config.conf \
    -n ${REGION2_NAMESPACE} \
    --dry-run=client -o yaml > ${OUTPUT_DIR}/nova-compute-region2-configmap.yaml

echo "Applying ConfigMap..."
oc apply -f ${OUTPUT_DIR}/nova-compute-region2-configmap.yaml

# Create a custom OpenStackDataPlaneService that uses this ConfigMap
cat > ${OUTPUT_DIR}/region2-nova-custom-service.yaml <<EOF
apiVersion: dataplane.openstack.org/v1beta1
kind: OpenStackDataPlaneService
metadata:
  name: nova-region2
  namespace: ${REGION2_NAMESPACE}
spec:
  label: dataplane-deployment-nova-region2
  playbookContents: |
    - hosts: all
      tasks:
        - name: Deploy nova compute config for Region 2
          ansible.builtin.copy:
            content: |
              {{ lookup('file', '/var/lib/openstack-k8s-operators/nova-compute-region2-config/02-nova-region2.conf') }}
            dest: /var/lib/config-data/nova/etc/nova/nova.conf.d/02-nova-region2.conf
            mode: '0644'
          become: true

        - name: Restart nova-compute container
          ansible.builtin.shell: |
            podman restart nova-compute
          become: true
  configMaps:
    - nova-compute-region2-config
EOF

echo "Applying custom OpenStackDataPlaneService..."
oc apply -f ${OUTPUT_DIR}/region2-nova-custom-service.yaml

echo ""
echo "Region 2 EDPM configuration generated successfully!"
echo ""
echo "Files created:"
echo "  - ${OUTPUT_DIR}/nova-compute-region2-config.conf"
echo "  - ${OUTPUT_DIR}/nova-compute-region2-configmap.yaml"
echo "  - ${OUTPUT_DIR}/region2-nova-custom-service.yaml"
echo ""
echo "ConfigMap 'nova-compute-region2-config' created in namespace ${REGION2_NAMESPACE}"
echo "OpenStackDataPlaneService 'nova-region2' created in namespace ${REGION2_NAMESPACE}"
echo ""
echo "To use this service in your OpenStackDataPlaneNodeSet:"
echo "  Add 'nova-region2' to the spec.services list"
echo "  Example:"
echo "    spec:"
echo "      services:"
echo "        - configure-network"
echo "        - validate-network"
echo "        - install-os"
echo "        - configure-os"
echo "        - run-os"
echo "        - ovn"
echo "        - neutron-metadata"
echo "        - libvirt"
echo "        - nova"
echo "        - nova-region2  # <-- Add this"
