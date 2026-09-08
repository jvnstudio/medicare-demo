output "project_id" {
  value       = var.project_id
  description = "Existing project used for the single-project demo."
}

output "vpc_name" {
  value       = google_compute_network.medicare.name
  description = "Single-project Medicare VPC."
}

output "primary_subnet" {
  value       = google_compute_subnetwork.primary.self_link
  description = "Primary-region subnet."
}

output "dr_subnet" {
  value       = google_compute_subnetwork.dr.self_link
  description = "DR-region subnet."
}

output "primary_mig" {
  value       = google_compute_region_instance_group_manager.primary.name
  description = "Primary regional managed instance group."
}

output "object_bucket" {
  value       = google_storage_bucket.portal_objects.name
  description = "Versioned Cloud Storage bucket."
}

output "gke_cluster_name" {
  value       = var.enable_gke ? google_container_cluster.primary[0].name : null
  description = "Optional regional GKE cluster name."
}

output "dr_mig" {
  value       = var.enable_dr ? google_compute_region_instance_group_manager.dr[0].name : null
  description = "Optional warm DR regional MIG."
}

output "filestore_ip" {
  value       = var.enable_filestore ? google_filestore_instance.shared[0].networks[0].ip_addresses[0] : null
  description = "Optional Filestore IP address."
}
