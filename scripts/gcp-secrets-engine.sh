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
# "-  Connect the app cluster to the Vault cluster.        -"
# "-                                                       -"
# "---------------------------------------------------------"

# Do not set exit on error, since the rollout status command may fail
set -o nounset
set -o pipefail

# Locate the root directory
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# shellcheck source=scripts/common.sh
source "$ROOT"/scripts/common.sh

# Ensure the latest Vault ENV vars are present
export_vault_env_vars

# Validate access to Vault externally
vault status || (echo "Error contacting vault"; exit 1)

# Enable the GCP secrets engine
vault secrets enable gcp

# Ensure the default TTL for secrets from this engine are by default 10m and max 60m
vault write gcp/config ttl=600 max_ttl=3600

# SA Keys and gsutil
vault write gcp/roleset/gcs-sa-role-set \
    project="$PROJECT" \
    secret_type="service_account_key" \
    bindings=-<<EOF
      resource "//cloudresourcemanager.googleapis.com/projects/$PROJECT" {
        roles = [
          "roles/storage.objectAdmin",
        ]
      }
EOF

# Create the policy that allows "reading" SA credentials
vault policy write myapp-gcs-rw - <<EOF
path "gcp/key/gcs-sa-role-set" {
  capabilities = ["read"]
}
EOF

# Create the role that allows the default/default SA to leverage that policy
vault write auth/kubernetes/role/my-gcs-role \
  bound_service_account_names=default \
  bound_service_account_namespaces=default \
  policies=default,myapp-gcs-rw \
  ttl=15m
