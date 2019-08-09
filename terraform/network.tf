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

# Create an external NAT IP
resource "google_compute_address" "app-nat" {
  count   = 2
  name    = "app-nat-external-${count.index}"
  project = var.project
  region  = var.region

  depends_on = [
    "google_project_service.app_service",
  ]
}

# Create a network for GKE
resource "google_compute_network" "app-network" {
  name                    = "app-network"
  project                 = var.project
  auto_create_subnetworks = false

  depends_on = [
    "google_project_service.app_service",
  ]
}

# Create subnets
resource "google_compute_subnetwork" "app-subnetwork" {
  name          = "app-subnetwork"
  project       = var.project
  network       = google_compute_network.app-network.self_link
  region        = var.region
  ip_cidr_range = var.kubernetes_network_ipv4_cidr

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "app-pods"
    ip_cidr_range = var.kubernetes_pods_ipv4_cidr
  }

  secondary_ip_range {
    range_name    = "app-svcs"
    ip_cidr_range = var.kubernetes_services_ipv4_cidr
  }
}

# Create a NAT router so the nodes can reach DockerHub, etc
resource "google_compute_router" "app-router" {
  name    = "app-router"
  project = var.project
  region  = var.region
  network = google_compute_network.app-network.self_link

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "app-nat" {
  name    = "app-nat-1"
  project = var.project
  router  = google_compute_router.app-router.name
  region  = var.region

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = google_compute_address.app-nat.*.self_link

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.app-subnetwork.self_link
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE", "LIST_OF_SECONDARY_IP_RANGES"]

    secondary_ip_range_names = [
      google_compute_subnetwork.app-subnetwork.secondary_ip_range.0.range_name,
      google_compute_subnetwork.app-subnetwork.secondary_ip_range.1.range_name,
    ]
  }
}
