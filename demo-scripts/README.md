# Medicare HA/DR live demo scripts

These scripts live at the repository root so they are easy to run during the presentation.

## MIG terminology

MIG means **Managed Instance Group**.

- Primary MIG: `medicare-sp-portal-primary` in `us-east4`
- DR MIG: `medicare-sp-portal-dr` in `us-central1`

The primary MIG demonstrates desired-capacity recovery and zonal HA. The DR MIG provides warm cross-region capacity and can autoscale under load.

## Prepare

Because a Cloud Shell checkout can have local commits, refresh only the demo scripts without merging branches:

```bash
cd ~/medicare-demo
git fetch origin main
git restore --source=origin/main -- demo-scripts
cd demo-scripts
chmod +x *.sh

export PROJECT_ID="medicare-demo-260907-4f00"
```

## Script order

```text
01-show-migs.sh             Baseline inventory
02-watch-migs.sh            Fixed combined MIG + load-balancer health dashboard
03-delete-primary-vm.sh     Delete one VM to demonstrate MIG recovery
04-fail-primary-region.sh   Stop nginx on all primary VMs to demonstrate DR routing
05-watch-dr-scale.sh        Fixed DR autoscaling dashboard
06-generate-load.sh         Generate traffic to trigger DR scale-out
07-recover-primary.sh       Restore nginx on primary VMs
```

## Demo 1 - VM failure and MIG recovery

Terminal 1:

```bash
./02-watch-migs.sh
```

The fixed dashboard shows both primary and DR instances with:

- instance name and zone
- VM status
- current MIG action
- MIG health
- global load-balancer health

Terminal 2:

```bash
./03-delete-primary-vm.sh
```

Type `DELETE` when prompted. The script automatically selects one current primary VM and resolves its actual Compute Engine zone.

Watch `VM STATUS`, `MIG ACTION`, and `LB HEALTH` in Terminal 1 as the primary MIG restores desired capacity.

## Demo 2 - regional application failure / DR routing

Keep Terminal 1 running:

```bash
./02-watch-migs.sh
```

In Terminal 2:

```bash
./04-fail-primary-region.sh
```

Type `FAILOVER` when prompted. This stops nginx on all primary-region VMs while leaving the VMs running. Watch the primary `LB HEALTH` values become unhealthy while the DR backend remains healthy.

## Demo 3 - DR autoscaling

Terminal 1:

```bash
./05-watch-dr-scale.sh
```

Terminal 2:

```bash
./06-generate-load.sh
```

For stronger load:

```bash
WORKERS=50 DURATION=180 ./06-generate-load.sh
```

The DR MIG is configured with a minimum of 1 and maximum of 3 instances. The watcher stays fixed while target size, recommended size, and instance rows change.

## Reset

```bash
./07-recover-primary.sh
```

Then keep `02-watch-migs.sh` running until the primary load-balancer health returns to healthy.

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
        global LB uses healthy DR
                     |
                     v
        DR MIG can autoscale 1 -> 3
```

For production, cross-region compute recovery must be paired with replicated application state, database/storage replication, secrets, observability, and recurring DR tests to meet the full application RTO/RPO.
