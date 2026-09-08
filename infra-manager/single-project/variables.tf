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
  description = "Secondary region used for warm DR capacity."
  type        = string
  default     = "us-central1"
}

variable "vm_target_size" {
  description = "Primary regional MIG target size."
  type        = number
  default     = 2
}

variable "enable_gke" {
  description = "Deploy a regional GKE cluster and node pool."
  type        = bool
  default     = false
}

variable "enable_dr" {
  description = "Deploy warm VM capacity in the DR region and attach it to the global load balancer."
  type        = bool
  default     = true
}

variable "dr_max_replicas" {
  description = "Maximum number of DR VMs that can be started automatically by the DR autoscaler."
  type        = number
  default     = 3
}

variable "lb_max_rate_per_instance" {
  description = "Backend serving capacity in requests per second per VM. Kept low so autoscaling is easy to demonstrate."
  type        = number
  default     = 5
}

variable "dr_lb_target_utilization" {
  description = "Fraction of load-balancer serving capacity the DR autoscaler tries to maintain."
  type        = number
  default     = 0.6
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
