# Medicare Portal Infrastructure Modernization Demo on Google Cloud

A deployable demonstration of a Medicare-style infrastructure modernization architecture on Google Cloud using **Cloud Foundation Fabric FAST v58.0.0**, Terraform, Compute Engine, GKE, Cloud Storage, and GitHub Actions with Workload Identity Federation.

## Scenario

The legacy environment has on-premises virtualization at capacity. Applications include VM and container workloads and require local, network, and object storage patterns. The target architecture must support zone separation, geographic redundancy, an RTO under 15 minutes for mission-critical VM applications, and automated/auditable deployments.

## Architecture layers

1. **FAST landing zone** — organization setup, IaC identities/state, networking, security, and project factory.
2. **Workload layer** — regional Compute Engine MIGs, regional GKE, object storage, optional Filestore/Local SSD, and warm DR capacity.
3. **Automation** — Terraform plus GitHub Actions/WIF for keyless, reviewable deployments.

## Repository layout

```text
.
├── landing-zone/
│   ├── README.md
│   └── scripts/
│       ├── 01-discover-fast.sh
│       ├── 02-prepare-stage0.sh
│       ├── 03-grant-bootstrap-roles.sh
│       └── 04-stage0.sh
├── demo-scripts/           # Live HA/DR demonstration scripts and dashboard
│   ├── README.md           # Script instructions & operational handover notes
│   ├── ensure-iap-ssh.sh   # Reusable IAP SSH firewall & IAM setup helper
│   ├── 00-deploy-infrastructure.sh
│   ├── 01-show-migs.sh
│   ├── 02-watch-migs.sh
│   ├── 03-delete-primary-vm.sh
│   ├── 04-fail-primary-region.sh
│   ├── 05-generate-load.sh
│   ├── 06-recover-primary.sh
│   └── 07-destroy-medicare.sh
├── infra-manager/          # Google Cloud Infrastructure Manager Terraform
├── terraform/
├── kubernetes/
├── scripts/
├── docs/
├── .github/workflows/
└── gcp_project.sh
```

## Important

The FAST landing zone is the organization foundation. Do **not** treat the workload Terraform alone as a landing zone. The old project-level bootstrap approach has intentionally been removed from this clean repository.

For the current demo:

- FAST release: `v58.0.0`
- Primary region: `us-east4`
- DR region: `us-central1`
- GitHub repository: `jvnstudio/medicare-demo`

## Start with FAST discovery

From Cloud Shell:

```bash
git clone https://github.com/jvnstudio/medicare-demo.git
cd medicare-demo

export PROJECT_ID="$(gcloud config get-value project)"
bash landing-zone/scripts/01-discover-fast.sh "$PROJECT_ID"
```

If discovery confirms an organization and billing account, export the values it prints, then prepare FAST Stage 0:

```bash
bash landing-zone/scripts/02-prepare-stage0.sh
source landing-zone/.fast.env
bash landing-zone/scripts/03-grant-bootstrap-roles.sh
```

`03-grant-bootstrap-roles.sh` is a **dry run by default**. Review the organization-wide bootstrap grants before using `--apply`.

Then create and review the Stage 0 Terraform plan:

```bash
bash landing-zone/scripts/04-stage0.sh plan
```

Do not apply an organization-level plan without reviewing it.

## Workload proof points

The workload layer demonstrates:

- regional managed instance groups across zones with health checks and autohealing;
- regional GKE Standard with multi-zone nodes and Kubernetes self-healing;
- Cloud Storage with versioning and soft delete;
- optional warm DR compute in `us-central1`;
- optional Local SSD for scratch/cache only;
- optional Filestore for shared NFS requirements.

A second MIG by itself does **not** satisfy a `<15 minute` regional RTO. Production recovery requires pre-created DR infrastructure, replicated state, traffic failover, and recurring DR exercises.

See `docs/architecture.md` and `docs/discovery.md` for architecture rationale and discovery questions.

## Live HA/DR demonstration & handover

A set of production-styled demonstration scripts are located in [`demo-scripts/`](file:///Users/johnvngt/Github-GCP/medicare-demo/demo-scripts) and documented in [`WORKFLOW.md`](file:///Users/johnvngt/Github-GCP/medicare-demo/WORKFLOW.md).

### Quick start (Cloud Shell)

```bash
git clone https://github.com/jvnstudio/medicare-demo.git
cd medicare-demo/demo-scripts
chmod +x *.sh

export PROJECT_ID="medicare-demo-260907-4f00"   # or your active project ID

# 1. Preflight check: ensures IAP SSH firewall (35.235.240.0/20) and IAM permissions
./ensure-iap-ssh.sh

# 2. Run the demo sequence:
# Terminal 1:
./02-watch-migs.sh            # Live unified operations dashboard

# Terminal 2:
./01-show-migs.sh             # Baseline inventory
./03-delete-primary-vm.sh     # Delete VM -> observe MIG recreation
./04-fail-primary-region.sh   # Stop nginx on primary VMs -> observe DR routing
./05-generate-load.sh         # Apply HTTP traffic -> observe DR autoscaling
./06-recover-primary.sh       # Restart nginx -> primary returns to HEALTHY
./07-destroy-medicare.sh      # Clean teardown of Infra Manager deployment
```

### Handover & operational notes
- **Secure VM access via IAP:** No VMs expose SSH (port 22) to the public internet. Failover (`04`) and recovery (`06`) use Cloud IAP TCP forwarding (`35.235.240.0/20`).
- **Idempotent prerequisite script:** [`ensure-iap-ssh.sh`](file:///Users/johnvngt/Github-GCP/medicare-demo/demo-scripts/ensure-iap-ssh.sh) checks and provisions the IAP firewall rule and grants `roles/iap.tunnelResourceAccessor` to the active operator.
- **Auto-healing scripts:** Scripts `04` and `06` automatically call `ensure-iap-ssh.sh --fast` before executing SSH commands to prevent `[4003: 'failed to connect to backend']` errors.
- See [`demo-scripts/README.md`](file:///Users/johnvngt/Github-GCP/medicare-demo/demo-scripts/README.md) for detailed presentation talk tracks and troubleshooting steps.

## VS Code

```bash
git clone https://github.com/jvnstudio/medicare-demo.git
cd medicare-demo
code .
```

> Cost warning: GKE, Compute Engine, Filestore, Local SSD, storage, and egress can incur charges. Keep expensive optional resources disabled unless needed and destroy demo resources when finished.
