# Medicare HA/DR live demo scripts

These scripts live at the repository root so they are easy to run during the presentation.

## MIG terminology

MIG means **Managed Instance Group**.

- Primary MIG: `medicare-sp-portal-primary` in `us-east4`
- DR MIG: `medicare-sp-portal-dr` in `us-central1`

The primary MIG demonstrates desired-capacity recovery and zonal HA. The DR MIG provides warm cross-region capacity and can autoscale under load.

## Prepare

```bash
cd ~/medicare-demo
git pull origin main
cd demo-scripts

export PROJECT_ID="medicare-demo-260907-4f00"
chmod +x *.sh
```

## Demo 1 - VM failure and MIG recovery

Terminal 1:

```bash
./02-watch-migs.sh
```

This is the main visual watcher. It shows both primary and DR managed instances with:

- instance name
- zone
- VM status
- current MIG action
- health state

Terminal 2:

```bash
./03-delete-primary-vm.sh
```

Type `DELETE` when prompted. The script selects one current primary VM automatically, so the demo does not depend on a hard-coded instance name.

Equivalent manual command:

```bash
gcloud compute instances delete INSTANCE_NAME \
  --zone=INSTANCE_ZONE \
  --project=medicare-demo-260907-4f00
```

Watch Terminal 1 as the primary MIG restores its desired capacity. The managed-instance name can be reused, so focus on `STATUS`, `ACTION`, and `HEALTH` during the transition.

## Demo 2 - regional application failure / DR routing

Terminal 1:

```bash
./02-watch-migs.sh
```

Terminal 2:

```bash
./04-watch-health.sh
```

Terminal 3:

```bash
./05-fail-primary-region.sh
```

Type `FAILOVER` when prompted. This stops nginx on all primary-region VMs while leaving the VMs running. The load balancer health check should mark the primary backend unhealthy while the DR MIG remains available.

## Demo 3 - DR autoscaling

Watch DR capacity:

```bash
./06-watch-dr-scale.sh
```

Generate HTTP load:

```bash
./07-generate-load.sh
```

For stronger load:

```bash
WORKERS=50 DURATION=180 ./07-generate-load.sh
```

The DR MIG is configured with a minimum of 1 and maximum of 3 instances.

## Reset

```bash
./08-recover-primary.sh
```

Then allow the load-balancer health check a short time to mark the primary backend healthy again.

## Recommended presentation order

```text
GitHub -> Infrastructure Manager -> Terraform-managed infrastructure
                     |
                     v
           Primary regional MIG
                     |
          delete one VM live
                     |
                     v
         MIG restores capacity
                     |
        fail primary application
                     |
                     v
          DR backend stays healthy
                     |
                     v
        DR MIG can autoscale 1 -> 3
```

For production, cross-region compute recovery must be paired with replicated application state, database/storage replication, secrets, observability, and recurring DR tests to meet the full application RTO/RPO.
