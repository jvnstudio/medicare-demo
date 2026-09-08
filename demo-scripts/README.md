# Medicare HA/DR live demo scripts

These scripts are designed for a live presentation of the Infrastructure Manager single-project deployment.

## MIG terminology

MIG means **Managed Instance Group**.

- Primary MIG: `medicare-sp-portal-primary` in `us-east4`
- DR MIG: `medicare-sp-portal-dr` in `us-central1`

The primary MIG demonstrates zonal high availability and autohealing. The DR MIG provides warm cross-region capacity and can autoscale under load.

## Prepare

```bash
cd ~/medicare-demo
git pull origin main
cd infra-manager/single-project/demo-scripts

export PROJECT_ID="medicare-demo-260907-4f00"
```

You can execute every script with `bash`, so executable file mode is not required:

```bash
bash 01-show-migs.sh
```

Optionally:

```bash
chmod +x *.sh
```

## Recommended live-demo layout

### Terminal 1 - traffic

```bash
bash 02-watch-traffic.sh
```

This continually calls the global load-balancer IP and prints the serving instance, zone, and region.

### Terminal 2 - backend health

```bash
bash 03-watch-health.sh
```

This continually displays the health reported by the global backend service.

### Terminal 3 - demo control

Start with:

```bash
bash 01-show-migs.sh
```

Then inject an application failure across the primary MIG:

```bash
bash 04-fail-primary.sh
```

Type `FAILOVER` when prompted.

The expected sequence is:

1. nginx stops on all primary VMs.
2. `/health` fails in `us-east4`.
3. The global backend marks the primary unhealthy.
4. The same global IP continues serving through `us-central1`.
5. The primary MIG independently repairs or recreates unhealthy VMs.
6. The primary backend becomes healthy again.

## Demonstrate DR autoscaling

In another terminal:

```bash
bash 05-watch-dr-scale.sh
```

Generate traffic:

```bash
bash 06-generate-load.sh
```

Defaults are 30 parallel workers for 120 seconds. Override them if needed:

```bash
WORKERS=50 DURATION=180 bash 06-generate-load.sh
```

The DR MIG is configured with a minimum of 1 and maximum of 3 instances.

## Reset between demos

If you want a deterministic reset instead of waiting for autohealing:

```bash
bash 07-recover-primary.sh
```

Then wait for the backend health check to report the primary healthy again.

## Presentation talk track

- VM/application failure: health check + MIG autohealing.
- Zone failure: regional MIG maintains capacity across zones.
- Region/application failure: global health-based load balancing keeps one public endpoint and routes to healthy DR capacity.
- DR demand increase: autoscaler adds DR VMs automatically.
- Infrastructure definition and revisions: GitHub -> Infrastructure Manager -> Terraform preview/apply.

For production, cross-region compute recovery must be paired with replicated application state, database/storage replication, secrets, observability, and recurring DR tests to meet the full application RTO/RPO.
