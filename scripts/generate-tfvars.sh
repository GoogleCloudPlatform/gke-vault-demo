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
# "-  Helper script to generate terraform variables        -"
# "-  file based on glcoud defaults.                       -"
# "-                                                       -"
# "---------------------------------------------------------"
# Stop immediately if something goes wrong
set -euo pipefail

# This script will write the terraform.tfvars file into the current working directory.
# The purpose is to populate defaults for subsequent terraform commands.

# Locate the root directory
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# shellcheck source=scripts/common.sh
source "${ROOT}/scripts/common.sh"

TFVARS_FILE="$ROOT/terraform/terraform.tfvars"

if [[ -f "${TFVARS_FILE}" ]]
then
    echo "${TFVARS_FILE} already exists." 1>&2
    echo "Please remove or rename before regenerating." 1>&2
    exit 1;
else
    cat <<EOF > "${TFVARS_FILE}"
project="${PROJECT}"
region="${REGION}"
billing_account="${BILLING_ACCOUNT}"
org_id="${ORG_ID}"
kubernetes_master_authorized_networks = [
  {
    display_name = "Any"
    cidr_block   = "0.0.0.0/0"
  },
]
EOF
    if [[ ! -z "${VAULT_PROJECT_ID}" ]]
    then
    cat <<EOF >> "${TFVARS_FILE}"
vault_project="${VAULT_PROJECT_ID}"
EOF
    fi
fi
