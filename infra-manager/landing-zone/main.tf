locals {
  network_project_id = "${var.prefix}-${var.project_suffix}-net"
  security_project_id = "${var.prefix}-${var.project_suffix}-sec"
  app_project_id     = "${var.prefix}-${var.project_suffix}-app"
}

resource "google_folder" "platform" {
  display_name = "${var.prefix}-platform"
  parent       = "organizations/${var.organization_id}"
}

resource "google_folder" "security" {
  display_name = "${var.prefix}-security"
  parent       = "organizations/${var.organization_id}"
}

resource "google_folder" "applications" {
  display_name = "${var.prefix}-applications"
  parent       = "organizations/${var.organization_id}"
}

resource "google_folder" "production" {
  display_name = "production"
  parent       = google_folder.applications.name
}

resource "google_folder" "nonproduction" {
  display_name = "nonproduction"
  parent       = google_folder.applications.name
}

resource "google_project" "network" {
  name            = "Medicare Shared Network"
  project_id      = local.network_project_id
  folder_id       = google_folder.platform.name
  billing_account = var.billing_account
}

resource "google_project" "security" {
  name            = "Medicare Security"
  project_id      = local.security_project_id
  folder_id       = google_folder.security.name
  billing_account = var.billing_account
}

resource "google_project" "app" {
  name            = "Medicare Production App"
  project_id      = local.app_project_id
  folder_id       = google_folder.production.name
  billing_account = var.billing_account
}

resource "google_project_service" "network_compute" {
  project            = google_project.network.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "app_services" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "file.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com"
  ])

  project            = google_project.app.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_shared_vpc_host_project" "host" {
  project = google_project.network.project_id

  depends_on = [google_project_service.network_compute]
}

resource "google_compute_shared_vpc_service_project" "app" {
  host_project    = google_project.network.project_id
  service_project = google_project.app.project_id

  depends_on = [
    google_compute_shared_vpc_host_project.host,
    google_project_service.app_services
  ]
}

resource "google_compute_network" "shared" {
  project                 = google_project.network.project_id
  name                    = "medicare-shared-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"

  depends_on = [google_compute_shared_vpc_host_project.host]
}

resource "google_compute_subnetwork" "primary" {
  project                  = google_project.network.project_id
  name                     = "medicare-primary-app"
  region                   = var.primary_region
  network                  = google_compute_network.shared.id
  ip_cidr_range            = "10.10.0.0/20"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

resource "google_compute_subnetwork" "dr" {
  project                  = google_project.network.project_id
  name                     = "medicare-dr-app"
  region                   = var.dr_region
  network                  = google_compute_network.shared.id
  ip_cidr_range            = "10.40.0.0/20"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.50.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.60.0.0/20"
  }
}
