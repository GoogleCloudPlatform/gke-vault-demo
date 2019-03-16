#!/usr/bin/env bash

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
# "-  Common commands for all scripts                      -"
# "-                                                       -"
# "---------------------------------------------------------"

# Locate the root directory
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# git is required for this tutorial
# https://git-scm.com/book/en/v2/Getting-Started-Installing-Git
command -v git >/dev/null 2>&1 || { \
 echo >&2 "I require git but it's not installed.  Aborting."
 echo >&2 "Refer to: https://git-scm.com/book/en/v2/Getting-Started-Installing-Git"
 exit 1
}

# glcoud is required for this tutorial
# https://cloud.google.com/sdk/install
command -v gcloud >/dev/null 2>&1 || { \
 echo >&2 "I require gcloud but it's not installed.  Aborting."
 echo >&2 "Refer to: https://cloud.google.com/sdk/install"
 exit 1
}

# Make sure kubectl is installed.  If not, refer to:
# https://kubernetes.io/docs/tasks/tools/install-kubectl/
command -v kubectl >/dev/null 2>&1 || { \
 echo >&2 "I require kubectl but it's not installed.  Aborting."
 echo >&2 "Refer to: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
 exit 1
}

# Set false if the ENV var isn't already set/present
IS_CI_ENV=${IS_CI_ENV:-false}
# Set empty if the ENV var isn't already set/present
VAULT_PROJECT_ID=${VAULT_PROJECT_ID:-}
# Release ID of the desired version of vault
VAULT_VERSION=${VAULT_VERSION:-"1.0.2"}

# Ensures vault is installed during CI builds
if [[ "${IS_CI_ENV}" == "true" ]]; then

  # Download a known version of vault
  VAULT_PATH="${ROOT}/bin/vault"

  # If vault is not already installed and executable
  if ! [ -x "${VAULT_PATH}" ]; then

    # Install a version of vault to ${ROOT}/bin/vault
    # CI runs in a Linux environment
    echo "Downloading and placing Hashicorp Vault ${VAULT_VERSION} in ${VAULT_PATH}"
    curl -sLO "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
    unzip "vault_${VAULT_VERSION}_linux_amd64.zip" >/dev/null
    rm "vault_${VAULT_VERSION}_linux_amd64.zip"

    # Move to the local bin directory and make executable
    mv "${ROOT}/vault" "${ROOT}/bin/vault"
    chmod +x "${ROOT}/bin/vault"

  fi
  # Add the local bin directory to the CI $PATH
  export PATH="${ROOT}/bin:$PATH"
fi

# Make sure vault is installed.  If not, refer to:
# https://learn.hashicorp.com/vault/getting-started/install
command -v vault >/dev/null 2>&1 || { \
 echo >&2 "I require vault but it's not installed.  Aborting."
 echo >&2 "Refer to: https://learn.hashicorp.com/vault/getting-started/install"
 exit 1
}

# Set specific ENV variables used by the Google Gloud SDK
PROJECT="$(gcloud config get-value core/project)"
if [[ -z "${PROJECT}" ]]; then
    echo "gcloud cli must be configured with a default project."
    echo "run 'gcloud config set core/project PROJECT'."
    echo "replace 'PROJECT' with the project name."
    exit 1;
fi

REGION="$(gcloud config get-value compute/region)"
if [[ -z "${REGION}" ]]; then
    echo "https://cloud.google.com/compute/docs/regions-zones/changing-default-zone-region"
    echo "gcloud cli must be configured with a default region."
    echo "run 'gcloud config set compute/region REGION'."
    echo "replace 'REGION' with the region name like us-west1."
    exit 1;
fi

# The vault-on-gke module requires these to be set to be able to create
# new GCP projects, but we are also passing an existing project ID from
# our env VAULT_PROJECT_ID variable which bypasses the project creation
# step.
BILLING_ACCOUNT=""
ORG_ID=""
# If this is not running in CI, obtain the needed env VARS for vault-on-gke
if [[ "${IS_CI_ENV}" != "true" ]]; then

  # Ensures the two env VARS needed by vault-on-gke to create projects are set
  BILLING_ACCOUNT="$(gcloud beta billing accounts list --format='value(name.basename())')"
  if [[ -z "${BILLING_ACCOUNT}" ]]; then
      echo "Your gcloud project must have a billing account set up."
      echo "Visit https://cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project."
      exit 1;
  fi

  ORG_ID="$(gcloud organizations list --format='value(name.basename())')"
  if [[ -z "${ORG_ID}" ]]; then
      echo "There was an error obtaining the organization ID for the current configuration."
      exit 1;
  fi
fi

# Exports vault-specific items to the current shell's ENV to aid in vault cli usage.
# Globals:
#   VAULT_ADDR
#   VAULT_TOKEN
#   VAULT_CAPATH
# Arguments:
#   None
# Returns:
#   0

function export_vault_env_vars {
  # Extract the vault-address output from the terraform output
  if ! VAULT_IP="$(terraform output -state=terraform/terraform.tfstate vault-address)"
  then
    echo "There was an error obtaining the vault-address output from Terraform. Exiting."
    exit 1;
  fi

  # The VAULT_ADDR environment variable expects a full URL to the Vault server endpoint
  VAULT_ADDR="https://${VAULT_IP}"

  # Extract the vault-root-token from the terraform output
  if ! VAULT_TOKEN="$(terraform output -state=terraform/terraform.tfstate vault-root-token)"
  then
    echo "There was an error obtaining the vault-root-token output from Terraform. Exiting."
    exit 1;
  fi

  # Set the full path to the Vault server's public CA certificate
  VAULT_CAPATH="${ROOT}/tls/ca.pem"

  # These need to be exported for the vault binary to pick them up in scripts and by the user
  # running the vault commands in the README.
  export VAULT_ADDR
  export VAULT_TOKEN
  export VAULT_CAPATH
}
