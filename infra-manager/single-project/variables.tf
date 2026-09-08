variable "project_id" {
  description = "Existing GCP project where Infrastructure Manager deploys the demo resources."
  type        = string
}

variable "primary_region" {
  description = "Primary region for the Medicare workload."
  type        = string
  default     = "us-east4"
}

variable "dr_region" {
  description = "Secondary region used for DR network and optional warm capacity."
  type        = string
  default     = "us-central1"
}

variable "vm_target_size" {
  description = "Primary regional MIG target size."
  type        = number
  default     = 2
}

variable "enable_gke" {
  description = "Deploy a regional GKE cluster and node pool. Disabled for the first quota-safe deployment."
  type        = bool
  default     = false
}

variable "enable_dr" {
  description = "Deploy warm VM capacity in the DR region."
  type        = bool
  default     = false
}

variable "enable_filestore" {
  description = "Deploy Enterprise Filestore. Disabled by default because of cost and quota."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Common labels for resources that support labels."
  type        = map(string)
  default = {
    application = "medicare-portal-demo"
    environment = "demo"
    managed_by  = "infra-manager"
  }
}
