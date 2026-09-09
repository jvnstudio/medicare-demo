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

For the failover/recovery scripts, SSH is performed through IAP. Run `./ensure-iap-ssh.sh` to automatically verify or create the IAP firewall rule (`35.235.240.0/20` -> TCP/22), ensure IAM access, and test the tunnel. Scripts `04` and `06` also call this automatically.

## Script order

```text
ensure-iap-ssh.sh           Verify/configure IAP SSH firewall & IAM (run anytime)
01-show-migs.sh             Baseline inventory
02-watch-migs.sh            Unified fixed HA/DR operations dashboard
03-delete-primary-vm.sh     Delete one VM to demonstrate MIG recovery
04-fail-primary-region.sh   Stop nginx on all primary VMs to demonstrate DR routing
05-generate-load.sh         Generate traffic to trigger DR scale-out
06-recover-primary.sh       Restore nginx on primary VMs
```

## Unified dashboard

Keep this running for the entire live demo:

```bash
./02-watch-migs.sh
```

The fixed dashboard shows both primary and DR instances with:

- instance name and zone
- VM status
- current MIG action
- MIG health
- global load-balancer health
- DR MIG target size and stability
- DR autoscaler status, recommended size, minimum replicas, and maximum replicas

This replaces the old separate DR autoscaling watcher.

## Demo 1 - VM failure and MIG recovery

Terminal 1:

```bash
./02-watch-migs.sh
```

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

Type `FAILOVER` when prompted. This stops nginx on all primary-region VMs through IAP while leaving the VMs running. Watch the primary `LB HEALTH` values become unhealthy while the DR backend remains healthy.

Manual Console equivalent:

```text
Console
Compute Engine -> VM instances
        |
SSH primary VM #1 -> stop nginx
SSH primary VM #2 -> stop nginx
        |
Load Balancing -> Backend health
        |
us-east4 becomes UNHEALTHY
us-central1 remains HEALTHY
        |
Open same global IP
        |
Page served from us-central1
```

## Demo 3 - DR autoscaling

Keep the same unified dashboard running in Terminal 1:

```bash
./02-watch-migs.sh
```

Generate load in Terminal 2:

```bash
./05-generate-load.sh
```

For stronger load:

```bash
WORKERS=50 DURATION=180 ./05-generate-load.sh
```

The DR MIG is configured with a minimum of 1 and maximum of 3 instances. Watch the `DR CAPACITY / AUTOSCALER` section in `02-watch-migs.sh` as recommended size, target size, and DR instance rows change.

## Reset

```bash
./06-recover-primary.sh
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
        generate load against same IP
                     |
                     v
        DR MIG can autoscale 1 -> 3
```

For production, cross-region compute recovery must be paired with replicated application state, database/storage replication, secrets, observability, and recurring DR tests to meet the full application RTO/RPO.

---

## Handover & Operational Notes

### Identity-Aware Proxy (IAP) SSH Architecture
The failover script (`04-fail-primary-region.sh`) and recovery script (`06-recover-primary.sh`) manage the `nginx` application service on Compute Engine VMs via SSH commands. 

To maintain a zero-trust network posture:
- **No public SSH access:** Ingress TCP port 22 is blocked from the public internet (`0.0.0.0/0`).
- **Encrypted TCP Tunneling:** SSH traffic is routed through Google Cloud Identity-Aware Proxy (IAP) TCP forwarding (`gcloud compute ssh --tunnel-through-iap`).

### Prerequisites & Troubleshooting (Error 4003)
If an operator runs script `04` or `06` and sees:
```text
ERROR: [0] Error during local connection to [stdin]: Error while connecting [4003: 'failed to connect to backend']. (Failed to connect to port 22)
```

This error indicates that Cloud IAP could not establish a TCP handshake on port 22 with the backend VM. This is resolved by two requirements:

1. **VPC Ingress Firewall Rule (`medicare-sp-allow-iap-ssh`):**
   - **Direction:** `INGRESS`
   - **Protocol/Port:** `tcp:22`
   - **Source CIDR:** `35.235.240.0/20` (Google Cloud's designated IAP netblock)
   - **Target:** Applied to `medicare-sp-web` (or all instances in `medicare-sp-vpc`).
   - *Status:* Now defined permanently in Terraform (`infra-manager/single-project/main.tf`, `infra-manager/main.tf`, and `terraform/main.tf`).

2. **IAM Permissions:**
   - The operator's active Google account requires the IAM role `roles/iap.tunnelResourceAccessor` on the GCP project.

### Reusable Preflight Helper (`ensure-iap-ssh.sh`)
To simplify handover and guarantee smooth presentations, run:
```bash
./ensure-iap-ssh.sh
```
What it does automatically:
1. Validates and auto-detects the VPC network (`medicare-sp-vpc`).
2. Checks whether the IAP firewall rule exists; if missing, creates it immediately.
3. Ensures `roles/iap.tunnelResourceAccessor` is bound to the current `gcloud` user.
4. Executes a live IAP SSH handshake against an active primary VM to verify the tunnel.

> [!TIP]
> **Built-in Resilience:** Scripts `04-fail-primary-region.sh` and `06-recover-primary.sh` also invoke `./ensure-iap-ssh.sh --fast` automatically as a preflight check before attempting SSH connections.
