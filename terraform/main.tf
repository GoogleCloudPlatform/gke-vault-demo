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

// Provides access to available Google Container Engine versions in a region for a given project.
// https://www.terraform.io/docs/providers/google/d/google_container_engine_versions.html
data "google_container_engine_versions" "gke_version" {
  project = "${var.project}"
  region = "${var.region}"
}

# Create the dedicated GKE service account for the application cluster
resource "google_service_account" "app_cluster" {
  account_id   = "gke-vault-demo-app-cluster"
  display_name = "Application Cluster"
  project      = "${var.project}"
}

# Enable required services on the app cluster project
resource "google_project_service" "app_service" {
  count   = "${length(var.app_project_services)}"
  project = "${var.project}"
  service = "${element(var.app_project_services, count.index)}"

  # Do not disable the service on destroy. On destroy, we are going to
  # destroy the project, but we need the APIs available to destroy the
  # underlying resources.
  disable_on_destroy = false
}

# Create the GKE cluster
resource "google_container_cluster" "app" {
  name    = "${var.application_cluster_name}"
  project = "${var.project}"
  region  = "${var.region}"

  network    = "${google_compute_network.app-network.self_link}"
  subnetwork = "${google_compute_subnetwork.app-subnetwork.self_link}"

  initial_node_count = "${var.num_nodes_per_zone}"

  min_master_version = "${data.google_container_engine_versions.gke_version.latest_master_version}"
  node_version       = "${data.google_container_engine_versions.gke_version.latest_node_version}"

  logging_service    = "logging.googleapis.com"
  monitoring_service = "monitoring.googleapis.com"

  # Disable legacy ACLs explicitly
  enable_legacy_abac = false

  node_config {
    machine_type    = "n1-standard-1"
    service_account = "${google_service_account.app_cluster.email}"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Set metadata on the VM to supply more entropy
    metadata {
      google-compute-enable-virtio-rng = "true"
    }

    labels {
      service = "applications"
    }

    tags = ["applications"]

    # Protect node metadata
    workload_metadata_config {
      node_metadata = "SECURE"
    }
  }

  addons_config {
    # Disable the Kubernetes dashboard, which is often an attack vector. The
    # cluster can still be managed via the GKE UI.
    kubernetes_dashboard {
      disabled = true
    }

    # Enable network policy configurations (like Calico).
    network_policy_config {
      disabled = false
    }
  }

  # Disable basic authentication and cert-based authentication.
  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Enable network policy configurations (like Calico) - for some reason this
  # has to be in here twice.
  network_policy {
    enabled = true
  }

  # Set the maintenance window.
  maintenance_policy {
    daily_maintenance_window {
      start_time = "${var.daily_maintenance_window}"
    }
  }

  # Allocate IPs in our subnetwork
  ip_allocation_policy {
    cluster_secondary_range_name  = "${google_compute_subnetwork.app-subnetwork.secondary_ip_range.0.range_name}"
    services_secondary_range_name = "${google_compute_subnetwork.app-subnetwork.secondary_ip_range.1.range_name}"
  }

   # Specify the list of CIDRs which can access the GKE API Server
  master_authorized_networks_config {
    cidr_blocks = ["${var.kubernetes_master_authorized_networks}"]
  }

   # Configure the cluster to be private (not have public facing IPs)
  private_cluster_config {
    # This field is misleading. This prevents access to the master API from
    # any external IP. While that might represent the most secure
    # configuration, it is not ideal for most setups. As such, we disable the
    # private endpoint (allow the public endpoint) and restrict which CIDRs
    # can talk to that endpoint.
    enable_private_endpoint = false

     enable_private_nodes   = true
    master_ipv4_cidr_block = "${var.kubernetes_masters_ipv4_cidr}"
  }

  depends_on = [
    "google_project_service.app_service",
    "google_service_account.app_cluster",
  ]
}
