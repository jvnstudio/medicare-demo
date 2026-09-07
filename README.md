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

## VS Code

```bash
git clone https://github.com/jvnstudio/medicare-demo.git
cd medicare-demo
code .
```

> Cost warning: GKE, Compute Engine, Filestore, Local SSD, storage, and egress can incur charges. Keep expensive optional resources disabled unless needed and destroy demo resources when finished.
