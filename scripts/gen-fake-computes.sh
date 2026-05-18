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

ACTION=${1:?Usage: $0 deploy|cleanup NUM_VMS COMPUTES_PER_VM [NOVA_IMAGE]}
NUM_VMS=${2:?Usage: $0 deploy|cleanup NUM_VMS COMPUTES_PER_VM [NOVA_IMAGE]}
COMPUTES_PER_VM=${3:?Usage: $0 deploy|cleanup NUM_VMS COMPUTES_PER_VM [NOVA_IMAGE]}
NOVA_IMAGE=${4:-"quay.io/podified-antelope-centos9/openstack-nova-compute:current-podified"}

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
EDPM_OUTPUT_DIR=${EDPM_OUTPUT_DIR:-"${SCRIPTPATH}/../out/edpm"}
SSH_KEY=${SSH_KEY:-"${EDPM_OUTPUT_DIR}/ansibleee-ssh-key-id_rsa"}
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY}"
NAMESPACE=${NAMESPACE:-openstack}
BASE_IP=${BASE_IP:-"192.168.122"}
IP_OFFSET=${IP_OFFSET:-100}

INTERNALAPI_VLAN_ID=${INTERNALAPI_VLAN_ID:-20}
INTERNALAPI_PREFIX=${INTERNALAPI_PREFIX:-"172.17.0"}
INTERNALAPI_IP_OFFSET=${INTERNALAPI_IP_OFFSET:-100}
INTERNALAPI_INTERFACE=${INTERNALAPI_INTERFACE:-"eth0"}

if [ ! -f "${SSH_KEY}" ]; then
    echo "ERROR: SSH key not found at ${SSH_KEY}"
    echo "Run 'make edpm_fake_compute' in devsetup/ first, or set SSH_KEY to the correct path."
    exit 1
fi

MY_TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$MY_TMP_DIR"' EXIT

function wait_for_ssh {
    local ip=$1
    local retries=30
    local count=0
    echo "Waiting for SSH on ${ip}..."
    while ! ssh ${SSH_OPTS} -o ConnectTimeout=5 root@${ip} true 2>/dev/null; do
        count=$((count + 1))
        if [ ${count} -ge ${retries} ]; then
            echo "ERROR: Timed out waiting for SSH on ${ip}"
            exit 1
        fi
        sleep 10
    done
    echo "SSH available on ${ip}"
}

function extract_nova_config {
    local config_dir=$1
    echo "Extracting nova config from conductor pod..."

    local conductor_pod
    conductor_pod=$(oc get pods -n ${NAMESPACE} -l service=nova-conductor -o name | head -n1)
    if [ -z "${conductor_pod}" ]; then
        echo "ERROR: Cannot find nova-conductor pod in namespace ${NAMESPACE}"
        exit 1
    fi

    oc rsh -n ${NAMESPACE} ${conductor_pod} bash -c 'cat /etc/nova/nova.conf.d/*.conf' > "${config_dir}/nova-base.conf"

    if [ ! -s "${config_dir}/nova-base.conf" ]; then
        echo "ERROR: Failed to extract nova config from ${conductor_pod}"
        exit 1
    fi
    echo "Nova config extracted to ${config_dir}/nova-base.conf"
}

function generate_fake_compute_config {
    local vm_index=$1
    local compute_index=$2
    local config_dir=$3
    local host_name="fake-compute-vm${vm_index}-${compute_index}"

    cat > "${config_dir}/nova-fake-${vm_index}-${compute_index}.conf" <<EOF
[DEFAULT]
compute_driver = fake.FakeDriver
host = ${host_name}
state_path = /var/lib/nova/fake-compute-${compute_index}

[workarounds]
disable_group_policy_check_upcall = true

[vnc]
enabled = false
EOF
}

function configure_vlan_interface {
    local vm_ip=$1
    local vm_index=$2
    local internalapi_ip="${INTERNALAPI_PREFIX}.$((INTERNALAPI_IP_OFFSET + vm_index))"
    local vlan_iface="${INTERNALAPI_INTERFACE}.${INTERNALAPI_VLAN_ID}"

    echo "Configuring VLAN ${INTERNALAPI_VLAN_ID} interface on VM ${vm_index} (${vm_ip}) with IP ${internalapi_ip}..."
    ssh ${SSH_OPTS} root@${vm_ip} bash -s <<REMOTE_EOF
set -ex
if ! ip link show ${vlan_iface} 2>/dev/null; then
    ip link add link ${INTERNALAPI_INTERFACE} name ${vlan_iface} type vlan id ${INTERNALAPI_VLAN_ID}
fi
ip link set ${vlan_iface} up
if ! ip addr show ${vlan_iface} | grep -q "${internalapi_ip}"; then
    ip addr add ${internalapi_ip}/24 dev ${vlan_iface}
fi
REMOTE_EOF
}

function deploy {
    extract_nova_config "${MY_TMP_DIR}"

    for VM_INDEX in $(seq 0 $((NUM_VMS - 1))); do
        local vm_ip="${BASE_IP}.$((IP_OFFSET + VM_INDEX))"
        wait_for_ssh "${vm_ip}"

        configure_vlan_interface "${vm_ip}" "${VM_INDEX}"

        scp ${SSH_OPTS} "${MY_TMP_DIR}/nova-base.conf" root@${vm_ip}:/tmp/nova-base.conf

        for COMPUTE_INDEX in $(seq 0 $((COMPUTES_PER_VM - 1))); do
            local container_name="nova-fake-compute-${COMPUTE_INDEX}"
            local host_name="fake-compute-vm${VM_INDEX}-${COMPUTE_INDEX}"

            generate_fake_compute_config "${VM_INDEX}" "${COMPUTE_INDEX}" "${MY_TMP_DIR}"
            scp ${SSH_OPTS} "${MY_TMP_DIR}/nova-fake-${VM_INDEX}-${COMPUTE_INDEX}.conf" \
                root@${vm_ip}:/tmp/nova-fake-${COMPUTE_INDEX}.conf

            ssh ${SSH_OPTS} root@${vm_ip} bash -s <<REMOTE_EOF
set -ex
mkdir -p /var/lib/nova/fake-compute-${COMPUTE_INDEX}

podman rm -f ${container_name} 2>/dev/null || true
podman run -d --name ${container_name} \
    -v /tmp/nova-base.conf:/etc/nova/nova.conf:ro \
    -v /tmp/nova-fake-${COMPUTE_INDEX}.conf:/etc/nova/nova.conf.d/99-fake-override.conf:ro \
    -v /var/lib/nova/fake-compute-${COMPUTE_INDEX}:/var/lib/nova/fake-compute-${COMPUTE_INDEX} \
    ${NOVA_IMAGE} \
    nova-compute --config-file /etc/nova/nova.conf --config-file /etc/nova/nova.conf.d/99-fake-override.conf
REMOTE_EOF
            echo "Started ${container_name} on VM ${VM_INDEX} (${vm_ip}) with host=${host_name}"
        done
    done

    echo ""
    echo "Deployed $((NUM_VMS * COMPUTES_PER_VM)) fake nova-compute containers across ${NUM_VMS} VMs."
    echo "Run 'make edpm_nova_discover_hosts' to register them with Nova."
}

function cleanup {
    for VM_INDEX in $(seq 0 $((NUM_VMS - 1))); do
        local vm_ip="${BASE_IP}.$((IP_OFFSET + VM_INDEX))"

        if ssh ${SSH_OPTS} -o ConnectTimeout=5 root@${vm_ip} true 2>/dev/null; then
            echo "Cleaning up fake compute containers on VM ${VM_INDEX} (${vm_ip})..."
            ssh ${SSH_OPTS} root@${vm_ip} bash -s <<REMOTE_EOF
set -x
for container in \$(podman ps -a --format '{{.Names}}' | grep '^nova-fake-compute-'); do
    podman rm -f \${container} 2>/dev/null || true
done
rm -f /tmp/nova-base.conf /tmp/nova-fake-*.conf
rm -rf /var/lib/nova/fake-compute-*
REMOTE_EOF
        else
            echo "WARNING: Cannot reach VM ${VM_INDEX} at ${vm_ip}, skipping container cleanup"
        fi

        for COMPUTE_INDEX in $(seq 0 $((COMPUTES_PER_VM - 1))); do
            local host_name="fake-compute-vm${VM_INDEX}-${COMPUTE_INDEX}"
            local service_id
            service_id=$(oc rsh -n ${NAMESPACE} openstackclient openstack compute service list \
                -c ID -c Host --service nova-compute -f value 2>/dev/null \
                | awk "/${host_name}/{ print \$1 }")
            if [ -n "${service_id}" ]; then
                echo "Deleting nova-compute service for ${host_name} (ID: ${service_id})"
                oc rsh -n ${NAMESPACE} openstackclient openstack compute service delete ${service_id}
            fi
        done
    done

    echo "Fake compute cleanup complete."
}

case ${ACTION} in
    deploy)
        deploy
        ;;
    cleanup)
        cleanup
        ;;
    *)
        echo "Unknown action: ${ACTION}"
        echo "Usage: $0 deploy|cleanup NUM_VMS COMPUTES_PER_VM [NOVA_IMAGE]"
        exit 1
        ;;
esac
