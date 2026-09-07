terraform {
  required_version = ">= 1.12.2"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.40.0, < 8.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.40.0, < 8.0.0"
    }
  }

  # Infrastructure Manager owns Terraform state for this workload deployment.
  # Do not define a backend block here; Infra Manager rejects root modules that
  # configure their own backend.
}

provider "google" {
  project = var.project_id
  region  = var.primary_region
}

provider "google-beta" {
  project = var.project_id
  region  = var.primary_region
}
