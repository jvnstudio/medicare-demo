output "platform_folder" {
  value = google_folder.platform.name
}

output "security_folder" {
  value = google_folder.security.name
}

output "applications_folder" {
  value = google_folder.applications.name
}

output "network_project_id" {
  value = google_project.network.project_id
}

output "security_project_id" {
  value = google_project.security.project_id
}

output "app_project_id" {
  value = google_project.app.project_id
}

output "shared_vpc_name" {
  value = google_compute_network.shared.name
}

output "primary_subnet" {
  value = google_compute_subnetwork.primary.self_link
}

output "dr_subnet" {
  value = google_compute_subnetwork.dr.self_link
}
