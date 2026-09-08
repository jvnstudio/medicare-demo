# Infrastructure Manager single-project demo

This root is the quota-safe deployment path for the Medicare modernization demo. It deploys resources into an existing billed GCP project and does not create, delete, or attach billing to any GCP projects.

## Why this root exists

The multi-project landing-zone root under `infra-manager/landing-zone/` demonstrates enterprise project separation and Shared VPC, but it requires billing quota for additional projects. This single-project root keeps the Infrastructure Manager workflow while avoiding project-creation and billing-link quota.

## Infrastructure Manager settings

- Terraform version: `1.5.7`
- Git repository: `https://github.com/jvnstudio/medicare-demo.git`
- Git directory: `infra-manager/single-project`
- Git ref: `main`
- Service account: `medicare-im-deployer@medicare-demo-260907-4f00.iam.gserviceaccount.com`

## First deployment inputs

Only `project_id` is required:

```text
project_id = medicare-demo-260907-4f00
```

Defaults:

```text
primary_region   = us-east4
dr_region        = us-central1
vm_target_size   = 2
enable_gke       = false
enable_dr        = false
enable_filestore = false
```

The first deployment creates:

- Custom global VPC
- Primary subnet in `us-east4`
- DR subnet in `us-central1`
- HTTP demo firewall
- Health check
- Regional self-healing managed instance group across three zones
- Versioned Cloud Storage bucket

Optional later revisions can enable regional GKE, warm DR VM capacity, and Enterprise Filestore.

## Bootstrap IAM

From Cloud Shell:

```bash
cd ~/medicare-demo
git pull origin main
export PROJECT_ID="medicare-demo-260907-4f00"
bash infra-manager/single-project/setup-single-project.sh
```

## Console workflow

Create a new Infrastructure Manager preview first. Use a new deployment ID such as `medicare-single-project`. Point the Git directory to `infra-manager/single-project` and set `project_id` to the existing project. Leave Advanced parameters blank unless a custom worker pool or artifacts bucket is required.

After the preview succeeds and shows no unexpected destroys, create the deployment from the preview.

## Destroy and redeploy

This root is intentionally safe for repeated demo cycles because it does not manage the GCP project itself. Deleting the Infrastructure Manager deployment can destroy the demo workload resources while leaving `medicare-demo-260907-4f00` intact for a later redeployment.
