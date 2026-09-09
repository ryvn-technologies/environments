# GCP IAM permissions

Set up the `ryvn-provisioner` service account for your GKE environment.

## Grants

| Grant | Scope | Purpose |
|-------|-------|---------|
| [`projects/<project>/roles/ryvnProvisioner`](provisioner-role.yaml) | project | Provision and manage the environment |
| `roles/container.admin` | project | Install Ryvn in GKE |
| `roles/iam.workloadIdentityUser` | the `ryvn-provisioner` service account | Authenticate Ryvn instances hosted on AWS through Workload Identity Federation |
| `roles/iam.serviceAccountTokenCreator` | the `ryvn-provisioner` service account | Authenticate Ryvn instances hosted on GCP through service account impersonation |

Use a dedicated project per environment.

## Setup

Open your environment in the Ryvn dashboard and run the setup commands it provides.
Sign in to gcloud as an owner of the target project. The commands create the service
account and grant the roles for your Ryvn instance.

You can also get the setup commands with the Ryvn CLI. Replace `my-project` with your project ID:

```bash
ryvn get gcp-setup-script --project my-project
```

## What the permissions are for

| Group | Used for |
|-------|----------|
| `resourcemanager.projects.*` | Read the project and manage the project IAM bindings listed in [provisioned resources](../resources/provisioned-resources.md) |
| `serviceusage.*` | Enable the Service Networking and Cloud KMS APIs if they are off |
| `compute.networks.*`, `compute.subnetworks.*`, `compute.firewalls.*` | VPC, subnet with secondary ranges and flow logs, firewall rules |
| `compute.addresses.*`, `compute.routers.*` | Reserved NAT IP, Cloud Router, Cloud NAT |
| `compute.globalAddresses.*`, `servicenetworking.*`, `compute.networks.*Peering` | Private Services Access range and peering for Cloud SQL and Memorystore |
| `container.*`, `compute.instanceGroupManagers.get`, `compute.instanceGroupManagers.list` | Private GKE cluster and node pools |
| `iam.serviceAccounts.*` | Node, agent, DNS and certificate service accounts and their Workload Identity bindings |
| `iam.roles.*` | The agent's custom roles |
| `resourcemanager.tagKeys.*`, `resourcemanager.tagValues.*` | Tag that scopes the agent's Cloud SQL permissions |
| `dns.*` | Public zone with a CAA record, private zone bound to the VPC |
| `cloudkms.*` | Key ring and key for GKE secrets encryption |
| `compute.zones.list`, `compute.*Operations.get`, `compute.regions.*`, `compute.projects.get` | Project, region and zone lookups |

## Deprovisioning

Uninstall Ryvn-managed services before deprovisioning the environment. For KMS keys
Ryvn creates, deprovisioning disables rotation and schedules key versions for destruction.
Key rings and keys remain in the project. Deprovisioning leaves keys you supply unchanged.
