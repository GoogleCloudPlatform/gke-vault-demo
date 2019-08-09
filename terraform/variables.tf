/*
Copyright 2018 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Required variables
variable "project" {
  description = "The name of the project in which to create the Application Kubernetes cluster."
  type        = "string"
}

variable "billing_account" {
  description = "The billing_account ID to attach to the project for attributing costs."
  type        = "string"
}

variable "org_id" {
  description = "The organization to hold the newly created project."
  type        = "string"
}

// If specified, this project ID is passed to the vault-on-gke module
// to use an existing project name for the vault cluster.  If omitted,
// the vault-on-gke module generates one for you in the format of
// vault-XXXXXXX by default.
variable "vault_project" {
  description = "The name of the project in which to create the Vault Demo App Kubernetes cluster."
  type        = "string"

  default = ""
}

// Optional variables
variable "region" {
  description = "The region in which the GKE clusters will run."
  default     = "us-west1"
}

variable "gke_master_version" {
  description = "The minimum version to use for the GKE control plane."
  default     = "latest"
}

variable "application_cluster_name" {
  default     = "gke-vault-demo-app-cluster"
  description = "The name of the cluster to deploy the applications into that use the Vault cluster for secrets."
  type        = "string"
}

variable "vault_cluster_name" {
  default     = "gke-vault-demo-vault-cluster"
  description = "The name of the dedicated GKE vault cluster."
  type        = "string"
}

variable "app_project_services" {
  type = "list"

  default = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]

  description = "The APIs that will be enabled in the application cluster project."
}

variable "num_nodes_per_zone" {
  type    = "string"
  default = "1"

  description = <<EOF
Number of nodes to deploy in each zone of the regional Kubernetes cluster.
One per zone will provide 3 total nodes.  2 per zone provides 6 total nodes.
EOF
}

variable "daily_maintenance_window" {
  type = "string"
  default = "06:00"
  description = "The 4 hr block each day when we want GKE to perform maintenance if needed."
}

variable "kubernetes_network_ipv4_cidr" {
  type = "string"
  default = "10.0.96.0/22"

  description = <<EOF
IP CIDR block for the subnetwork. This must be at least /22 and cannot overlap
with any other IP CIDR ranges.
EOF
}

variable "kubernetes_pods_ipv4_cidr" {
  type    = "string"
  default = "10.0.92.0/22"

  description = <<EOF
IP CIDR block for pods. This must be at least /22 and cannot overlap with any
other IP CIDR ranges.
EOF
}

variable "kubernetes_services_ipv4_cidr" {
  type = "string"
  default = "10.0.88.0/22"

  description = <<EOF
IP CIDR block for services. This must be at least /22 and cannot overlap with
any other IP CIDR ranges.
EOF
}

variable "kubernetes_masters_ipv4_cidr" {
  type    = "string"
  default = "10.0.82.0/28"

  description = <<EOF
IP CIDR block for the Kubernetes master nodes. This must be exactly /28 and
cannot overlap with any other IP CIDR ranges.
EOF
}

variable "kubernetes_master_authorized_networks" {
  type = "list"

  default = [
    {
      display_name = "Anyone"
      cidr_block = "0.0.0.0/0"
    },
  ]

  description = <<EOF
List of CIDR blocks to allow access to the master's API endpoint. This is
specified as a slice of objects, where each object has a display_name and
cidr_block attribute:
[
  {
    display_name = "My range"
    cidr_block   = "1.2.3.4/32"
  },
  {
    display_name = "My other range"
    cidr_block   = "5.6.7.0/24"
  }
]
The default behavior is to allow anyone (0.0.0.0/0) access to the endpoint.
You should restrict access to external IPs that need to access the cluster.
EOF
}

variable "service_account_roles" {
  type = "list"

  default = [
    "roles/iam.serviceAccountKeyAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin",
  ]

  description = <<EOF
List of roles to be granted to the vault-server SA in this application cluster
project for managing SAs and SA Keys.
EOF
}
