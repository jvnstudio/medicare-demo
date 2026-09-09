# Medicare HA/DR Demo Workflow

This workflow matches the current scripts in `demo-scripts/` and is intended to be followed in order during the presentation.

## Architecture being demonstrated

```text
GitHub / Terraform
        ↓
Infrastructure Manager
        ↓
Primary regional MIG - us-east4
        ↓
Global external load balancer
        ↓
Warm DR regional MIG - us-central1
        ↓
DR autoscaler
```

The primary MIG demonstrates VM and zonal resilience. The DR MIG provides warm cross-region capacity. The global load balancer uses backend health to continue service from healthy capacity.

> The DR test simulates a primary-region **application failure** by stopping nginx on all primary VMs. It is not a literal Google Cloud regional outage. The load balancer is health-based multi-region routing, not strict active/passive DNS failover.

## Prepare

Refresh only the demo scripts so local branch divergence does not interfere with the presentation:

```bash
cd ~/medicare-demo
git fetch origin main
git restore --source=origin/main -- demo-scripts
cd demo-scripts
chmod +x *.sh
export PROJECT_ID="medicare-demo-260907-4f00"
```

IAP SSH is used by the failover and recovery scripts. The VPC must allow TCP/22 from the IAP range `35.235.240.0/20`.

## Workflow

```text
01-show-migs.sh
      ↓
02-watch-migs.sh   ← keep running for the rest of the demo
      ↓
03-delete-primary-vm.sh
      ↓
04-fail-primary-region.sh
      ↓
05-generate-load.sh
      ↓
06-recover-primary.sh
```

## 01 - Show baseline

```bash
./01-show-migs.sh
```

**What it does**

- Lists the current primary MIG instances in `us-east4`.
- Lists the current DR MIG instances in `us-central1`.
- Shows instance name, zone, VM status, current MIG action, and MIG health.

**What it proves**

The environment starts with regional managed capacity in the primary region and warm capacity already available in the DR region.

---

## 02 - Start the live dashboard

```bash
./02-watch-migs.sh
```

Keep this script running in **Terminal 1** for the rest of the demonstration.

**What it does**

- Refreshes in place without scrolling.
- Shows primary and DR instance state.
- Shows `VM STATUS`, `MIG ACTION`, `MIG HEALTH`, and global load-balancer `LB HEALTH`.
- Shows DR MIG target size and stability.
- Shows DR autoscaler status, recommended size, minimum replicas, and maximum replicas.

**What to watch**

```text
HA:   VM STATUS + MIG ACTION
DR:   LB HEALTH
Scale: DR target size + recommended size
```

This is the single operations dashboard used for steps 03 through 06.

---

## 03 - Demonstrate VM HA / MIG recovery

Run in **Terminal 2**:

```bash
./03-delete-primary-vm.sh
```

Type:

```text
DELETE
```

**What it does**

- Selects one current VM from the primary regional MIG.
- Resolves its Compute Engine zone.
- Deletes that VM.

**What to watch in 02**

```text
VM disappears / changes state
        ↓
MIG ACTION = RECREATING / CREATING
        ↓
replacement VM reaches RUNNING
        ↓
health returns to HEALTHY
```

**What it proves**

The regional Managed Instance Group maintains desired capacity automatically. An operator does not manually provision the replacement VM.

> This demonstrates desired-capacity reconciliation. A separate health-check-driven autohealing test would stop or break the application on a single VM rather than delete the VM itself.

---

## 04 - Demonstrate cross-region DR routing

Keep `02-watch-migs.sh` running in Terminal 1, then run in Terminal 2:

```bash
./04-fail-primary-region.sh
```

Type:

```text
FAILOVER
```

**What it does**

- Reads the current primary VM names and zones directly from the MIG.
- Waits for any in-progress MIG recreation to finish.
- Uses IAP SSH rather than public internet SSH.
- Safely refreshes stale Compute Engine SSH host-key entries caused by recreated MIG VMs.
- Stops nginx on **all** primary VMs while leaving the VMs themselves running.

Equivalent Console workflow:

```text
Compute Engine → VM instances
        ↓
SSH primary VM #1 → stop nginx
SSH primary VM #2 → stop nginx
        ↓
Load Balancing → Backend health
        ↓
us-east4 becomes UNHEALTHY
us-central1 remains HEALTHY
        ↓
Open the same global IP
        ↓
Page is served from us-central1
```

**What to watch in 02**

```text
Primary VM STATUS: RUNNING
Primary LB HEALTH: UNHEALTHY
DR LB HEALTH:      HEALTHY
```

Then verify the same global endpoint still serves traffic:

```bash
curl -s http://8.233.6.65 | grep -E "Instance:|Zone:|Region:"
```

Expected DR result:

```text
Region: us-central1
```

**What it proves**

The application can continue through healthy warm capacity in the secondary region without changing the public endpoint.

---

## 05 - Demonstrate DR autoscaling

Keep `02-watch-migs.sh` running in Terminal 1 and run in Terminal 2:

```bash
./05-generate-load.sh
```

Default load:

```text
30 workers
120 seconds
```

For a stronger test:

```bash
WORKERS=50 DURATION=180 ./05-generate-load.sh
```

**What it does**

- Resolves the global load-balancer IP.
- Sends concurrent HTTP requests to the same public endpoint.
- Creates enough request pressure for the DR load-balancing-based autoscaler to evaluate additional capacity.

**What to watch in 02**

```text
Recommended: 1 → 2 → 3
MIG target:  1 → 2 → 3
DR instance rows increase
```

Autoscaling is not instantaneous; allow several minutes for recommendations and new VM capacity to appear.

**What it proves**

The warm DR region can add Compute Engine capacity automatically when demand increases.

---

## 06 - Recover the primary application

Run in Terminal 2:

```bash
./06-recover-primary.sh
```

**What it does**

- Reads the current primary VM names and zones from the MIG.
- Waits for the current VMs to be `RUNNING`.
- Refreshes stale per-instance SSH host-key entries when necessary.
- Connects through IAP.
- Starts nginx on every primary VM.

**What to watch in 02**

```text
Primary LB HEALTH
UNHEALTHY → HEALTHY
```

**What it proves**

The primary application can be restored while the same global endpoint remains in service.

---

## Presentation flow in one sentence

> The infrastructure is version-controlled in GitHub and deployed with Terraform through Infrastructure Manager; the primary regional MIG automatically restores failed VM capacity, the global load balancer continues service through healthy DR capacity when the primary application fails, and the DR MIG can automatically scale as demand increases.

## What this demo does not claim

This demo proves compute recovery, health-based routing, and automated scaling. A production `<15 minute` application RTO also requires replicated application state, database and storage replication, secrets, network readiness, observability, tested traffic-failover procedures, and recurring DR exercises.
