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

ACTION=${1:?Usage: $0 deploy|cleanup [NUM_VMS COMPUTES_PER_VM]}
NUM_VMS=${2:-1}
COMPUTES_PER_VM=${3:-10}

NAMESPACE=${NAMESPACE:-openstack}
INSTANCEHA_NAME=${INSTANCEHA_NAME:-instanceha-0}
FENCING_SECRET=${FENCING_SECRET:-fencing-secret}

MY_TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$MY_TMP_DIR"' EXIT

function deploy {
    cat > "${MY_TMP_DIR}/fencing-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${FENCING_SECRET}
  namespace: ${NAMESPACE}
stringData:
  fencing.yaml: |
    FencingConfig:
EOF

    for VM_INDEX in $(seq 0 $((NUM_VMS - 1))); do
        for COMPUTE_INDEX in $(seq 0 $((COMPUTES_PER_VM - 1))); do
            local host_name="fake-compute-vm${VM_INDEX}-${COMPUTE_INDEX}"
            cat >> "${MY_TMP_DIR}/fencing-secret.yaml" <<EOF
      ${host_name}:
        agent: noop
EOF
        done
    done

    echo "Creating fencing secret with noop driver for $((NUM_VMS * COMPUTES_PER_VM)) fake computes..."
    oc apply -n ${NAMESPACE} -f "${MY_TMP_DIR}/fencing-secret.yaml"

    cat > "${MY_TMP_DIR}/instanceha.yaml" <<EOF
apiVersion: instanceha.openstack.org/v1beta1
kind: InstanceHa
metadata:
  name: ${INSTANCEHA_NAME}
  namespace: ${NAMESPACE}
spec:
  caBundleSecretName: combined-ca-bundle
  fencingSecret: ${FENCING_SECRET}
EOF

    echo "Creating InstanceHa CR..."
    oc apply -n ${NAMESPACE} -f "${MY_TMP_DIR}/instanceha.yaml"

    echo "InstanceHA deployed with noop fencing for $((NUM_VMS * COMPUTES_PER_VM)) fake computes."
}

function cleanup {
    echo "Removing InstanceHa CR..."
    oc delete instanceha -n ${NAMESPACE} ${INSTANCEHA_NAME} --ignore-not-found

    echo "Removing fencing secret..."
    oc delete secret -n ${NAMESPACE} ${FENCING_SECRET} --ignore-not-found

    echo "InstanceHA cleanup complete."
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
        echo "Usage: $0 deploy|cleanup [NUM_VMS COMPUTES_PER_VM]"
        exit 1
        ;;
esac
