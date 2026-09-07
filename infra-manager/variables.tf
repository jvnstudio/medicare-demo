variable "project_id" {
  description = "GCP project where Infrastructure Manager deploys the Medicare demo."
  type        = string
}

variable "primary_region" {
  description = "Primary GCP region."
  type        = string
  default     = "us-east4"
}

variable "dr_region" {
  description = "Secondary DR region."
  type        = string
  default     = "us-central1"
}

variable "vm_target_size" {
  description = "Primary regional MIG target size."
  type        = number
  default     = 3
}

variable "enable_gke" {
  description = "Deploy the regional GKE workload."
  type        = bool
  default     = true
}

variable "enable_dr" {
  description = "Deploy warm VM capacity in the DR region."
  type        = bool
  default     = false
}

variable "enable_filestore" {
  description = "Deploy Enterprise Filestore. Disabled by default because of cost."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Common resource labels."
  type        = map(string)
  default = {
    application = "medicare-portal-demo"
    environment = "demo"
    managed_by  = "infra-manager"
  }
}
