variable "organization_id" {
  description = "Google Cloud organization numeric ID."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID used for landing-zone projects."
  type        = string
}

variable "prefix" {
  description = "Short lowercase prefix for folders and projects."
  type        = string
  default     = "medlz"
}

variable "project_suffix" {
  description = "Globally unique suffix used in project IDs, for example 260907."
  type        = string
}

variable "primary_region" {
  type    = string
  default = "us-east4"
}

variable "dr_region" {
  type    = string
  default = "us-central1"
}
