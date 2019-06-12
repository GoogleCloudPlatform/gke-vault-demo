#! /usr/bin/env bash

# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# "---------------------------------------------------------"
# "-                                                       -"
# "-  Validation script checks if the vault cluster        -"
# "-  deployed successfully.                               -"
# "-                                                       -"
# "---------------------------------------------------------"

# Do not set exit on error, since the rollout status command may fail
set -o nounset
set -o pipefail

# Locate the root directory
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"

# Step 1 - Validate that Vault is up/running # Configure root access to vault

# Ensure the latest Vault ENV vars are present
export_vault_env_vars

# Loop for up to 180 seconds waiting for vault to be ready
VAULTREADY=""
for _ in {1..90}; do
  VAULTREADY=$(curl -s --cacert "${VAULT_CAPATH}" "${VAULT_ADDR}/v1/sys/health" | grep "initialized")
  [ ! -z "$VAULTREADY" ] && break
  sleep 2
done
if [ -z "$VAULTREADY" ]
then
  echo "ERROR - Timed out waiting for Vault to be ready"
  exit 1
fi
echo "Step 1 of the validation passed. Vault deployed successfully."

# Step 2 - Validate that Vault serves up secrets using Kubernetes Pod/SA Authentication
# shellcheck source=scripts/auth-to-vault.sh
source "$ROOT/scripts/auth-to-vault.sh"

# Add the initial secret
vault kv put secret/myapp/config \
  ttl="30s" \
  apikey='MYAPIKEYHERE'

# install the auto-init sidecar
kubectl apply -n default -f "${ROOT}/k8s-manifests/sidecar.yaml" #2> /dev/null 1> /dev/null

# Loop for up to 180 seconds waiting for vault to be ready
SECRETSREADY=""
for _ in {1..90}; do
  SECRETSREADY=$(kubectl exec -it -n default "$(kubectl get pod -n default -l "app=kv-sidecar" -o jsonpath="{.items[0].metadata.name}")" -c app -- cat /etc/secrets/config | grep "apikey")
  [ ! -z "$SECRETSREADY" ] && break
  sleep 2
done
if [ -z "$SECRETSREADY" ]
then
  echo "ERROR - Timed out waiting for Vault secrets to be available from inside a pod"
  exit 1
fi
echo "Step 2 of the validation passed. Client application retrieved Vault secrets successfully."
