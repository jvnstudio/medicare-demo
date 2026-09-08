locals {
  primary_zones = [
    "${var.primary_region}-a",
    "${var.primary_region}-b",
    "${var.primary_region}-c"
  ]

  dr_zones = [
    "${var.dr_region}-a",
    "${var.dr_region}-b",
    "${var.dr_region}-c"
  ]

  required_services = toset(concat(
    [
      "compute.googleapis.com",
      "storage.googleapis.com"
    ],
    var.enable_gke ? ["container.googleapis.com"] : [],
    var.enable_filestore ? ["file.googleapis.com"] : []
  ))

  vm_startup = <<-EOT
    #!/usr/bin/env bash
    set -euxo pipefail
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx curl

    INSTANCE_NAME="$(curl -fsS -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/name)"
    ZONE_PATH="$(curl -fsS -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone)"
    ZONE="$(basename "$ZONE_PATH")"
    REGION="$(echo "$ZONE" | sed -E 's/-[a-z]$//')"

    cat >/var/www/html/index.html <<HTML
    <!doctype html>
    <html>
      <head><title>Medicare Portal Demo</title></head>
      <body style="font-family:Arial;margin:40px">
        <h1>Medicare Portal - VM Workload</h1>
        <p>Managed by Google Cloud Infrastructure Manager.</p>
        <p>Instance: $INSTANCE_NAME</p>
        <p>Zone: $ZONE</p>
        <p>Region: $REGION</p>
        <p>HA/DR: regional MIG + global health-based load balancing.</p>
      </body>
    </html>
    HTML

    echo ok >/var/www/html/health
    systemctl enable --now nginx
  EOT
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "medicare" {
  name                    = "medicare-sp-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "primary" {
  name                     = "medicare-sp-primary"
  region                   = var.primary_region
  network                  = google_compute_network.medicare.id
  ip_cidr_range            = "10.110.0.0/20"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "sp-pods"
    ip_cidr_range = "10.120.0.0/16"
  }

  secondary_ip_range {
    range_name    = "sp-services"
    ip_cidr_range = "10.130.0.0/20"
  }
}

resource "google_compute_subnetwork" "dr" {
  name                     = "medicare-sp-dr"
  region                   = var.dr_region
  network                  = google_compute_network.medicare.id
  ip_cidr_range            = "10.140.0.0/20"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "sp-dr-pods"
    ip_cidr_range = "10.150.0.0/16"
  }

  secondary_ip_range {
    range_name    = "sp-dr-services"
    ip_cidr_range = "10.160.0.0/20"
  }
}

resource "google_compute_firewall" "demo_http" {
  name          = "medicare-sp-allow-http"
  network       = google_compute_network.medicare.name
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["medicare-sp-web"]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_health_check" "portal" {
  name                = "medicare-sp-portal-health"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

resource "google_compute_instance_template" "primary" {
  name_prefix  = "medicare-sp-primary-"
  machine_type = "e2-standard-2"
  tags         = ["medicare-sp-web"]
  labels       = merge(var.labels, { role = "primary" })

  disk {
    source_image = "projects/debian-cloud/global/images/family/debian-12"
    auto_delete  = true
    boot         = true
    disk_type    = "pd-balanced"
    disk_size_gb = 20
  }

  network_interface {
    network    = google_compute_network.medicare.id
    subnetwork = google_compute_subnetwork.primary.id

    access_config {}
  }

  metadata_startup_script = local.vm_startup

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "primary" {
  name               = "medicare-sp-portal-primary"
  region             = var.primary_region
  base_instance_name = "medicare-sp-portal"
  target_size        = var.vm_target_size

  version {
    instance_template = google_compute_instance_template.primary.id
  }

  distribution_policy_zones = local.primary_zones

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.portal.id
    initial_delay_sec = 120
  }
}

resource "google_compute_instance_template" "dr" {
  count = var.enable_dr ? 1 : 0

  name_prefix  = "medicare-sp-dr-"
  machine_type = "e2-standard-2"
  tags         = ["medicare-sp-web"]
  labels       = merge(var.labels, { role = "dr" })

  disk {
    source_image = "projects/debian-cloud/global/images/family/debian-12"
    auto_delete  = true
    boot         = true
    disk_type    = "pd-balanced"
    disk_size_gb = 20
  }

  network_interface {
    network    = google_compute_network.medicare.id
    subnetwork = google_compute_subnetwork.dr.id

    access_config {}
  }

  metadata_startup_script = local.vm_startup

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "dr" {
  count = var.enable_dr ? 1 : 0

  name               = "medicare-sp-portal-dr"
  region             = var.dr_region
  base_instance_name = "medicare-sp-dr"
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.dr[0].id
  }

  distribution_policy_zones = local.dr_zones

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.portal.id
    initial_delay_sec = 120
  }

  lifecycle {
    ignore_changes = [target_size]
  }
}

resource "google_compute_region_autoscaler" "dr" {
  count = var.enable_dr ? 1 : 0

  name   = "medicare-sp-dr-autoscaler"
  region = var.dr_region
  target = google_compute_region_instance_group_manager.dr[0].self_link

  autoscaling_policy {
    min_replicas    = 1
    max_replicas    = var.dr_max_replicas
    cooldown_period = 60

    load_balancing_utilization {
      target = var.dr_lb_target_utilization
    }
  }
}

resource "google_compute_global_address" "portal" {
  name = "medicare-sp-global-ip"
}

resource "google_compute_backend_service" "portal" {
  name                  = "medicare-sp-portal-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.portal.id]

  backend {
    group                 = google_compute_region_instance_group_manager.primary.instance_group
    balancing_mode        = "RATE"
    max_rate_per_instance = var.lb_max_rate_per_instance
    capacity_scaler       = 1.0
  }

  dynamic "backend" {
    for_each = var.enable_dr ? [1] : []

    content {
      group                 = google_compute_region_instance_group_manager.dr[0].instance_group
      balancing_mode        = "RATE"
      max_rate_per_instance = var.lb_max_rate_per_instance
      capacity_scaler       = 1.0
    }
  }
}

resource "google_compute_url_map" "portal" {
  name            = "medicare-sp-portal-map"
  default_service = google_compute_backend_service.portal.id
}

resource "google_compute_target_http_proxy" "portal" {
  name    = "medicare-sp-http-proxy"
  url_map = google_compute_url_map.portal.id
}

resource "google_compute_global_forwarding_rule" "portal" {
  name                  = "medicare-sp-http-forwarding-rule"
  ip_address            = google_compute_global_address.portal.address
  port_range            = "80"
  target                = google_compute_target_http_proxy.portal.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_container_cluster" "primary" {
  count = var.enable_gke ? 1 : 0

  name     = "medicare-sp-gke-primary"
  location = var.primary_region

  network    = google_compute_network.medicare.name
  subnetwork = google_compute_subnetwork.primary.name

  networking_mode          = "VPC_NATIVE"
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false
  datapath_provider        = "ADVANCED_DATAPATH"

  ip_allocation_policy {
    cluster_secondary_range_name  = "sp-pods"
    services_secondary_range_name = "sp-services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  depends_on = [google_project_service.required]
}

resource "google_container_node_pool" "primary" {
  count = var.enable_gke ? 1 : 0

  name       = "portal-pool"
  location   = var.primary_region
  cluster    = google_container_cluster.primary[0].name
  node_count = 1

  node_locations = local.primary_zones

  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = "e2-standard-2"
    disk_type    = "pd-balanced"
    disk_size_gb = 50

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      application = "medicare-portal"
      environment = "demo"
    }
  }
}

resource "google_storage_bucket" "portal_objects" {
  name                        = "${var.project_id}-sp-portal-objects"
  location                    = "US"
  uniform_bucket_level_access = true
  force_destroy               = true
  labels                      = var.labels

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.required]
}

resource "google_filestore_instance" "shared" {
  count = var.enable_filestore ? 1 : 0

  name     = "medicare-sp-shared-files"
  location = var.primary_region
  tier     = "ENTERPRISE"

  file_shares {
    capacity_gb = 1024
    name        = "shared"
  }

  networks {
    network = google_compute_network.medicare.name
    modes   = ["MODE_IPV4"]
  }

  labels = var.labels

  depends_on = [google_project_service.required]
}
