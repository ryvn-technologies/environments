# Provisioned Resources

Resources Ryvn creates in your project when it provisions a GKE environment. Everything is created
by the `ryvn-provisioner` service account, and names carry the environment name as a suffix.

## APIs

| API | Description |
|-----|-------------|
| `servicenetworking.googleapis.com` | Enabled during provisioning if not already on (Private Services Access) |
| `cloudkms.googleapis.com` | Enabled during provisioning if not already on (secrets encryption) |

## Networking

| Resource | Count | Description |
|----------|-------|-------------|
| VPC (`gke-network-<env>`) | 1 | Custom-mode network |
| Subnet (`gke-subnet-<env>`) | 1 | Regional subnet with Private Google Access, VPC flow logs, and two secondary ranges (`pod-ranges-<env>`, `services-ranges-<env>`) for the VPC-native cluster |
| Firewall rules | 2 | `allow-internal-<env>` (ingress within the node, pod and service CIDRs) and `allow-egress-<env>` |
| External IP (`nat-ip-<env>`) | 1 | Static regional address for Cloud NAT |
| Cloud Router (`nat-router-<env>`) | 1 | Hosts the NAT config |
| Cloud NAT | 1 | Egress for private nodes, using the reserved address |
| Global internal address (`private-services-<env>`) | 1 | Private Services Access range |
| Service Networking connection | 1 | VPC peering to `servicenetworking.googleapis.com` for Cloud SQL and Memorystore |

## Cluster

| Resource | Count | Description |
|----------|-------|-------------|
| GKE cluster (`ryvn-gke-<env>`) | 1 | Regional, private nodes, private control plane endpoint (Ryvn bootstraps through the DNS-based endpoint, gated by IAM), VPC-native, Workload Identity enabled, Dataplane V2 (optional), secrets encrypted with the Cloud KMS key below, HTTP load balancing add-on off, Cloud Logging and Monitoring off |
| Node pool `system` | 1 | `e2-standard-2`, autoscaling 1 to 2 nodes, 50 GB pd-standard disks, Secure Boot and integrity monitoring, tainted `CriticalAddonsOnly=true:NoSchedule` |
| Node pool `application` | 1 | `e2-standard-4`, autoscaling 2 to 5 nodes, 50 GB pd-standard disks, Secure Boot and integrity monitoring |
| Node service account | 1 | Attached to all node pools, with `roles/container.defaultNodeServiceAccount`, `roles/monitoring.metricWriter` and `roles/stackdriver.resourceMetadata.writer` |

## Secrets encryption

| Resource | Count | Description |
|----------|-------|-------------|
| Cloud KMS key ring (`ryvn-gke-<env>-<hex>`) | 1 | Regional |
| Cloud KMS key (`ryvn-gke-<env>-secrets`) | 1 | Symmetric, rotation enabled, with `roles/cloudkms.cryptoKeyEncrypterDecrypter` granted to the GKE service agent. Rings and keys cannot be deleted, so deprovisioning disables rotation and schedules the key versions for destruction |

## Identity and access

| Resource | Count | Description |
|----------|-------|-------------|
| Service account `ryvn-agent-<hex>` | 1 | Identity of the in-cluster Ryvn agent, bound to the Kubernetes service account `ryvn-system/ryvn-agent` through `roles/iam.workloadIdentityUser` |
| Custom role `ryvn_agent_role_<env>` | 1 | Project-level permissions the agent needs to install Ryvn-managed services (Cloud SQL, Memorystore, Cloud Storage, service accounts, custom roles) |
| Custom role `ryvn_agent_cloudsql_role_<env>` | 1 | Cloud SQL permissions, bound with an IAM condition on the tag below so the agent only manages instances it created |
| Tag key and value (`ryvn-managed`) | 1 each | Scopes the conditional Cloud SQL binding |
| Service account `external-dns-<hex>` | 1 | Bound through Workload Identity, with `roles/dns.admin` for managing DNS records |
| Service account `cert-manager-<hex>` | 1 | Bound through Workload Identity, with `roles/dns.admin` for DNS-01 certificate challenges |
| Project binding for the provisioner | 1 | `roles/container.admin` granted to the provisioning service account (the same binding the setup commands create; Ryvn removes this one again when the environment is deprovisioned) |

## DNS

| Resource | Count | Description |
|----------|-------|-------------|
| Public managed zone | 1 | Environment domain, with a CAA record restricting certificate issuance to Let's Encrypt |
| Private managed zone | 1 | Internal names, bound to the VPC |

## Not created by the provisioner

Cloud SQL instances, Memorystore instances, Cloud Storage buckets, Artifact Registry repositories and
other service dependencies are created later by the in-cluster agent, under its own identity, when
you install Ryvn-managed services. Load balancers, forwarding rules and health check firewall rules
for Kubernetes `Service` and `Ingress` objects are created by the GKE service agent.
