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

# Compose the short and full cluster names
if ! GKE_NAME="$(terraform output -state=terraform/terraform.tfstate application-cluster-name)"
then
  echo "There was an error obtaining the application-cluster-name output from Terraform. Exiting."
  exit 1;
fi
FULL_GKE_NAME="gke_${PROJECT}_${REGION}_${GKE_NAME}"

# Validate access to Vault externally
vault status || (echo "Error contacting vault"; exit 1)

# Enable audit logging to StackDriver
vault audit enable file file_path=stdout

# Configure the current kubectl context to the application cluster
gcloud container clusters get-credentials --region "${REGION}" "${GKE_NAME}"

# Create the vault-auth service account
kubectl create serviceaccount vault-auth -n default

# Create the RBAC rolebinding for token review for the vault-auth service account
kubectl apply -n default -f - <<EOH
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: default
EOH

# set the variable DIR to access the TLS keypair info
DIR="$(pwd)/tls"

# Get the name of the secret corresponding to the service account
SECRET_NAME="$(kubectl get serviceaccount vault-auth -n default \
  -o go-template='{{ (index .secrets 0).name }}')"

# Get the actual token reviewer account
TR_ACCOUNT_TOKEN="$(kubectl get secret "${SECRET_NAME}" -n default \
  -o go-template='{{ .data.token }}' | base64 --decode)"

# Get the host for the cluster (IP address)
K8S_HOST="$(kubectl config view --raw \
  -o go-template="{{ range .clusters }}{{ if eq .name \"${FULL_GKE_NAME}\" }}{{ index .cluster \"server\" }}{{ end }}{{ end }}")"

# Get the CA for the cluster
K8S_CACERT="$(kubectl config view --raw \
  -o go-template="{{ range .clusters }}{{ if eq .name \"${FULL_GKE_NAME}\" }}{{ index .cluster \"certificate-authority-data\" }}{{ end }}{{ end }}" | base64 --decode)"

# Enable the Kubernetes auth method
vault auth enable kubernetes

# Configure Vault to talk to our Kubernetes host with the cluster's CA and the
# correct token reviewer JWT token
vault write auth/kubernetes/config \
  kubernetes_host="${K8S_HOST}" \
  kubernetes_ca_cert="${K8S_CACERT}" \
  token_reviewer_jwt="${TR_ACCOUNT_TOKEN}"

# Create a policy to be referenced by a role to access the kv location secret/myapp/*
vault policy write myapp-kv-rw - <<EOF
path "secret/myapp/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

# Bind the default sa in the default ns the ability to use the myapp-kv-rw policy to access secrets
vault write auth/kubernetes/role/myapp-role \
  bound_service_account_names=default \
  bound_service_account_namespaces=default \
  policies=default,myapp-kv-rw \
  ttl=15m

# Enable our workloads to find vault
# Create a config map to store the vault address
kubectl create configmap vault -n default \
  --from-literal "vault_addr=${VAULT_ADDR}"

# Create a secret for our CA
kubectl create secret generic vault-tls -n default \
  --from-file "${DIR}/ca.pem"
