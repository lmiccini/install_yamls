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

# Generate customServiceConfig snippets for Region 2 services to use Region 1's keystone

# Region 1 keystone URL (exposed via LoadBalancer)
REGION1_KEYSTONE_URL=${REGION1_KEYSTONE_URL:-""}
REGION2_NAME=${REGION2_NAME:-"regionTwo"}

if [ -z "${REGION1_KEYSTONE_URL}" ]; then
    echo "ERROR: REGION1_KEYSTONE_URL must be set"
    echo "Example: export REGION1_KEYSTONE_URL=http://192.168.122.80:5000"
    exit 1
fi

OUTPUT_DIR=${OUTPUT_DIR:-"${PWD}/out/region2-config"}
mkdir -p ${OUTPUT_DIR}

echo "Generating Region 2 service configurations..."
echo "Region 1 Keystone URL: ${REGION1_KEYSTONE_URL}"
echo "Region 2 Name: ${REGION2_NAME}"

# Cinder configuration
cat > ${OUTPUT_DIR}/cinder-config.yaml <<EOF
customServiceConfig: |
  [keystone_authtoken]
  www_authenticate_uri = ${REGION1_KEYSTONE_URL}
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [barbican]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [nova]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [service_user]
  auth_url = ${REGION1_KEYSTONE_URL}
EOF

# Glance configuration
cat > ${OUTPUT_DIR}/glance-config.yaml <<EOF
customServiceConfig: |
  [keystone_authtoken]
  www_authenticate_uri = ${REGION1_KEYSTONE_URL}
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [barbican]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [oslo_limit]
  auth_url = ${REGION1_KEYSTONE_URL}
  endpoint_region_name = ${REGION2_NAME}
EOF

# Neutron configuration
cat > ${OUTPUT_DIR}/neutron-config.yaml <<EOF
customServiceConfig: |
  [keystone_authtoken]
  www_authenticate_uri = ${REGION1_KEYSTONE_URL}
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [nova]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [placement]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
EOF

# Placement configuration
cat > ${OUTPUT_DIR}/placement-config.yaml <<EOF
customServiceConfig: |
  [keystone_authtoken]
  www_authenticate_uri = ${REGION1_KEYSTONE_URL}
  auth_url = ${REGION1_KEYSTONE_URL}
EOF

# Nova API configuration
cat > ${OUTPUT_DIR}/nova-api-config.yaml <<EOF
customServiceConfig: |
  [keystone_authtoken]
  www_authenticate_uri = ${REGION1_KEYSTONE_URL}
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [placement]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [glance]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [neutron]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [cinder]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [barbican]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [service_user]
  auth_url = ${REGION1_KEYSTONE_URL}
  [oslo_limit]
  auth_url = ${REGION1_KEYSTONE_URL}
  endpoint_region_name = ${REGION2_NAME}
EOF

# Nova Metadata configuration
cat > ${OUTPUT_DIR}/nova-metadata-config.yaml <<EOF
customServiceConfig: |
  [keystone_authtoken]
  www_authenticate_uri = ${REGION1_KEYSTONE_URL}
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [placement]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [glance]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [neutron]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [cinder]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [barbican]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [service_user]
  auth_url = ${REGION1_KEYSTONE_URL}
  [oslo_limit]
  auth_url = ${REGION1_KEYSTONE_URL}
  endpoint_region_name = ${REGION2_NAME}
EOF

# Nova Scheduler configuration
cat > ${OUTPUT_DIR}/nova-scheduler-config.yaml <<EOF
customServiceConfig: |
  [keystone_authtoken]
  www_authenticate_uri = ${REGION1_KEYSTONE_URL}
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [placement]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [glance]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [neutron]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [cinder]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [barbican]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [service_user]
  auth_url = ${REGION1_KEYSTONE_URL}
  [oslo_limit]
  auth_url = ${REGION1_KEYSTONE_URL}
  endpoint_region_name = ${REGION2_NAME}
EOF

# Nova Conductor configuration (for cells)
cat > ${OUTPUT_DIR}/nova-conductor-config.yaml <<EOF
customServiceConfig: |
  [keystone_authtoken]
  www_authenticate_uri = ${REGION1_KEYSTONE_URL}
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [placement]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [glance]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [neutron]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [cinder]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [barbican]
  auth_url = ${REGION1_KEYSTONE_URL}
  region_name = ${REGION2_NAME}
  [service_user]
  auth_url = ${REGION1_KEYSTONE_URL}
  [oslo_limit]
  auth_url = ${REGION1_KEYSTONE_URL}
  endpoint_region_name = ${REGION2_NAME}
EOF

# Ceilometer configuration
cat > ${OUTPUT_DIR}/ceilometer-config.yaml <<EOF
customServiceConfig: |
  [service_credentials]
  auth_url=${REGION1_KEYSTONE_URL}
EOF

echo ""
echo "Configuration files generated in ${OUTPUT_DIR}/"
echo ""
echo "To use these in your OpenStackControlPlane CR for Region 2:"
echo "1. For cinder.template, add the content from cinder-config.yaml"
echo "2. For glance.template, add the content from glance-config.yaml"
echo "3. For neutron.template, add the content from neutron-config.yaml"
echo "4. For placement.template, add the content from placement-config.yaml"
echo "5. For nova.template.apiServiceTemplate, add the content from nova-api-config.yaml"
echo "6. For nova.template.metadataServiceTemplate, add the content from nova-metadata-config.yaml"
echo "7. For nova.template.schedulerServiceTemplate, add the content from nova-scheduler-config.yaml"
echo "8. For nova.template.cellTemplates.cell*.conductorServiceTemplate, add the content from nova-conductor-config.yaml"
echo "9. For telemetry.template.ceilometer, add the content from ceilometer-config.yaml"
echo ""
echo "Example snippet for Cinder in your CR:"
echo "---"
cat ${OUTPUT_DIR}/cinder-config.yaml
echo "---"
