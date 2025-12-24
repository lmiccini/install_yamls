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

# Automatically patch Region 2 OpenStackControlPlane CR to use Region 1's keystone

REGION1_KEYSTONE_URL=${REGION1_KEYSTONE_URL:-""}
REGION2_NAMESPACE=${REGION2_NAMESPACE:-"openstack-region2"}
REGION2_NAME=${REGION2_NAME:-"regionTwo"}

if [ -z "${REGION1_KEYSTONE_URL}" ]; then
    echo "ERROR: REGION1_KEYSTONE_URL must be set"
    echo "Example: export REGION1_KEYSTONE_URL=http://192.168.122.80:5000"
    exit 1
fi

echo "Patching Region 2 OpenStackControlPlane to use Region 1's keystone..."
echo "Region 1 Keystone URL: ${REGION1_KEYSTONE_URL}"
echo "Region 2 Namespace: ${REGION2_NAMESPACE}"
echo "Region 2 Name: ${REGION2_NAME}"

# Get the OpenStackControlPlane name
CONTROLPLANE_NAME=$(oc get openstackcontrolplane -n ${REGION2_NAMESPACE} -o jsonpath='{.items[0].metadata.name}')

if [ -z "${CONTROLPLANE_NAME}" ]; then
    echo "ERROR: No OpenStackControlPlane found in namespace ${REGION2_NAMESPACE}"
    exit 1
fi

echo "Found OpenStackControlPlane: ${CONTROLPLANE_NAME}"

# Patch Cinder
echo "Patching Cinder configuration..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=merge -p "
spec:
  cinder:
    template:
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
"

# Patch Glance
echo "Patching Glance configuration..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=merge -p "
spec:
  glance:
    template:
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
"

# Patch Neutron
echo "Patching Neutron configuration..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=merge -p "
spec:
  neutron:
    template:
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
"

# Patch Placement
echo "Patching Placement configuration..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=merge -p "
spec:
  placement:
    template:
      customServiceConfig: |
        [keystone_authtoken]
        www_authenticate_uri = ${REGION1_KEYSTONE_URL}
        auth_url = ${REGION1_KEYSTONE_URL}
"

# Patch Nova API
echo "Patching Nova API configuration..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=merge -p "
spec:
  nova:
    template:
      apiServiceTemplate:
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
"

# Patch Nova Metadata
echo "Patching Nova Metadata configuration..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=merge -p "
spec:
  nova:
    template:
      metadataServiceTemplate:
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
"

# Patch Nova Scheduler
echo "Patching Nova Scheduler configuration..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=merge -p "
spec:
  nova:
    template:
      schedulerServiceTemplate:
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
"

# Patch Nova Conductor for cell0
echo "Patching Nova Conductor (cell0) configuration..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=json -p "[
  {
    \"op\": \"add\",
    \"path\": \"/spec/nova/template/cellTemplates/cell0/conductorServiceTemplate\",
    \"value\": {
      \"customServiceConfig\": \"[keystone_authtoken]\\nwww_authenticate_uri = ${REGION1_KEYSTONE_URL}\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[placement]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[glance]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[neutron]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[cinder]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[barbican]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[service_user]\\nauth_url = ${REGION1_KEYSTONE_URL}\\n[oslo_limit]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nendpoint_region_name = ${REGION2_NAME}\"
    }
  }
]" 2>/dev/null || echo "Note: cell0 conductor config may already exist or structure differs"

# Patch Nova Conductor for cell1
echo "Patching Nova Conductor (cell1) configuration..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=json -p "[
  {
    \"op\": \"add\",
    \"path\": \"/spec/nova/template/cellTemplates/cell1/conductorServiceTemplate\",
    \"value\": {
      \"customServiceConfig\": \"[keystone_authtoken]\\nwww_authenticate_uri = ${REGION1_KEYSTONE_URL}\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[placement]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[glance]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[neutron]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[cinder]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[barbican]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nregion_name = ${REGION2_NAME}\\n[service_user]\\nauth_url = ${REGION1_KEYSTONE_URL}\\n[oslo_limit]\\nauth_url = ${REGION1_KEYSTONE_URL}\\nendpoint_region_name = ${REGION2_NAME}\"
    }
  }
]" 2>/dev/null || echo "Note: cell1 conductor config may already exist or structure differs"

# Patch Telemetry/Ceilometer if enabled
echo "Patching Telemetry/Ceilometer configuration (if enabled)..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=merge -p "
spec:
  telemetry:
    template:
      ceilometer:
        customServiceConfig: |
          [service_credentials]
          auth_url=${REGION1_KEYSTONE_URL}
" 2>/dev/null || echo "Note: Telemetry may not be enabled or structure differs"

# Disable Horizon in Region 2 (it should only be in Region 1)
echo "Disabling Horizon in Region 2..."
oc patch openstackcontrolplane/${CONTROLPLANE_NAME} -n ${REGION2_NAMESPACE} --type=merge -p "
spec:
  horizon:
    enabled: false
"

echo ""
echo "Region 2 OpenStackControlPlane has been patched successfully!"
echo ""
echo "The following services have been configured to use Region 1's keystone:"
echo "  - Cinder"
echo "  - Glance"
echo "  - Neutron"
echo "  - Placement"
echo "  - Nova (API, Metadata, Scheduler, Conductor)"
echo "  - Telemetry/Ceilometer (if enabled)"
echo ""
echo "Horizon has been disabled in Region 2."
echo ""
echo "Next steps:"
echo "1. Wait for Region 2 services to reconcile and restart with new configuration"
echo "2. Run: make configure_region2_endpoints (to register Region 2 endpoints in Region 1)"
echo "3. Run: make scale_down_region2_keystone (to scale down Region 2's keystone)"
echo "4. Run: make gen_region2_edpm_config (to prepare EDPM configuration)"
