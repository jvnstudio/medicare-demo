# Infrastructure Manager single-project HA/DR demo

This root is the quota-safe deployment path for the Medicare modernization demo. It deploys resources into the existing billed project and does not create, delete, or attach billing to any GCP projects.

## Presentation focus

The demo centers on infrastructure automation and resilience:

```text
GitHub
  -> Infrastructure Manager
  -> Terraform preview / revision
  -> Primary regional MIG in us-east4
  -> Warm DR regional MIG in us-central1
  -> Global external Application Load Balancer
  -> Health-based cross-region traffic failover
  -> DR autoscaling from 1 to 3 VMs as load increases
```

The global load balancer uses the same application health check as the MIGs. For an East Coast client, the healthy `us-east4` backend is normally preferred by proximity. If all primary backends become unhealthy, the load balancer automatically sends requests to the healthy DR backend in `us-central1`.

The DR group keeps one warm VM so the demo does not depend on scaling from zero. Its autoscaler uses load-balancer serving capacity and can add VMs automatically when failover traffic rises.

## Infrastructure Manager settings

- Terraform version: `1.5.7`
- Git repository: `https://github.com/jvnstudio/medicare-demo.git`
- Git directory: `infra-manager/single-project`
- Git ref: `main`
- Service account: `medicare-im-deployer@medicare-demo-260907-4f00.iam.gserviceaccount.com`

## Inputs

Only `project_id` is required:

```text
project_id = medicare-demo-260907-4f00
```

Defaults for the HA/DR revision:

```text
primary_region                = us-east4
dr_region                     = us-central1
vm_target_size                = 2
enable_dr                     = true
dr_max_replicas               = 3
lb_max_rate_per_instance      = 5
dr_lb_target_utilization      = 0.6
enable_gke                    = false
enable_filestore              = false
```

## Resources

The deployment manages:

- Custom global VPC
- Primary subnet in `us-east4`
- DR subnet in `us-central1`
- Demo HTTP firewall
- Shared HTTP health check
- Primary regional self-healing MIG across three zones
- Warm DR regional self-healing MIG across three zones
- DR regional autoscaler, minimum 1 and maximum 3 VMs
- Global external Application Load Balancer with both MIGs as backends
- Global public IPv4 address
- Versioned Cloud Storage bucket

Optional later revisions can enable regional GKE and Enterprise Filestore.

## Update the existing Infrastructure Manager deployment

For the current deployment named `medicare-project`, choose **Edit**, keep the same Git source and input values, and create a preview first. The new plan should add DR compute, an autoscaler, and global load-balancing resources. It can also replace the primary instance template so the demo web page displays its instance, zone, and serving region.

After reviewing the preview, apply the revision.

## Verify after apply

Get the public load-balancer IP:

```bash
gcloud compute addresses describe medicare-sp-global-ip \
  --global \
  --project=medicare-demo-260907-4f00 \
  --format='value(address)'
```

Then browse or curl it:

```bash
LB_IP="$(gcloud compute addresses describe medicare-sp-global-ip --global --project=medicare-demo-260907-4f00 --format='value(address)')"
curl -s "http://${LB_IP}/"
```

The response displays the VM instance, zone, and region that served the request.

## HA / DR demonstration

Run:

```bash
cd ~/medicare-demo
git pull origin main
bash infra-manager/single-project/demo-ha-dr.sh
```

The script shows both MIGs and the load-balancer endpoint and can intentionally stop nginx on all primary-region VMs. That makes both the load balancer and the primary MIG see the application as unhealthy.

Expected behavior:

1. Normal requests from the East Coast are served by `us-east4`.
2. nginx is stopped on all primary VMs.
3. Health checks mark the primary backend unhealthy.
4. Requests automatically move to `us-central1`.
5. The primary MIG repairs/recreates unhealthy VMs.
6. When primary health returns, proximity-based traffic returns to `us-east4`.
7. During DR service, sustained load can cause the DR autoscaler to add VMs up to `dr_max_replicas`.

To create enough requests to demonstrate DR scale-out after failover:

```bash
LB_IP="$(gcloud compute addresses describe medicare-sp-global-ip --global --project=medicare-demo-260907-4f00 --format='value(address)')"
seq 1 3000 | xargs -P 40 -I{} curl -s --max-time 5 "http://${LB_IP}/" >/dev/null
```

Watch DR capacity:

```bash
watch -n 5 'gcloud compute instance-groups managed list-instances medicare-sp-portal-dr --region=us-central1 --project=medicare-demo-260907-4f00'
```

## Architecture statement

A VM failure is handled by MIG reconciliation and autohealing. A zone failure is handled by the regional MIG maintaining capacity across zones. A regional application outage is handled by global health-based load balancing to warm DR capacity, after which the DR MIG can add VM capacity automatically.

For a production `<15 minute RTO`, compute failover alone is not sufficient. Stateful data, databases, secrets, storage replication, dependencies, and end-to-end DR testing must also meet the application's RPO/RTO requirements.

## Destroy and redeploy

This root is safe for repeated demo cycles because it does not manage the GCP project itself. Deleting the Infrastructure Manager deployment can destroy the demo workload resources while leaving `medicare-demo-260907-4f00` intact for a later redeployment.
