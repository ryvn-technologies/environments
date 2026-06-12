# Provisioned Resources

Resources created by the Ryvn platform blueprint during environment provisioning (AWS EKS BYOC).

> **Source of truth** — generated from Terraform state output. Categories are cloud-agnostic to allow reuse across AWS, Azure, and GCP environment types.

## Networking

| Resource | Count | Description |
|----------|-------|-------------|
| Virtual Network (VPC) | 1 | Primary network (`10.0.0.0/16`), DNS support and DNS hostnames enabled |
| Private Subnets | 3 | One per availability zone (`/20` each) — workload and internal load balancer traffic. Tagged for Karpenter discovery and internal ELB routing |
| Public Subnets | 3 | One per availability zone (`/24` each) — external load balancer traffic. Tagged for external ELB routing |
| Intra Subnets | 3 | One per availability zone (`/24` each) — control plane ENIs and internal-only resources (no internet route) |
| NAT Gateway | 1 | Single NAT gateway for private subnet egress |
| Internet Gateway | 1 | Public internet ingress/egress for public subnets |
| Elastic IP | 1 | Static IP bound to the NAT gateway |
| Route Tables | 3 | Public (IGW route), private (NAT route), intra (local only) |
| Route Table Associations | 9 | One per subnet (3 public + 3 private + 3 intra) |
| Routes | 2 | Public → IGW, private → NAT |
| Default Network ACL | 1 | VPC default NACL (managed to prevent drift) |
| Default Route Table | 1 | VPC default route table (managed to prevent drift) |

### Security Groups

| Security Group | Rules | Purpose |
|----------------|-------|---------|
| Cluster | 2 | Control plane network access — ingress from nodes on 443, egress to nodes on ephemeral ports |
| Node (shared) | 13 | Node-to-node and cluster-to-node communication — CoreDNS (53 TCP/UDP), kubelet (10250), webhooks (4443, 6443, 8443, 9443, 10251), ephemeral ports, all-traffic between cluster API and nodes |
| Default | 1 | VPC default SG (managed to prevent drift, all rules removed) |

## Cluster

| Resource | Count | Description |
|----------|-------|-------------|
| Kubernetes Cluster (EKS) | 1 | Kubernetes v1.34, public endpoint enabled (CIDR-restricted to management plane), secrets envelope encryption via KMS |
| System Node Group | 1 | Managed node group for system workloads — ARM64 (AL2023), `t4g.large`, 2–3 nodes on-demand |
| Launch Template | 1 | Node launch config — 50 GB gp3 encrypted root volume, IMDSv2 required |

### Cluster Add-ons

| Add-on | Version | Description |
|--------|---------|-------------|
| VPC CNI | v1.21.1 | Pod networking (VPC-native) |
| CoreDNS | v1.13.2 | Cluster DNS |
| kube-proxy | v1.34.6 | Service networking |
| EBS CSI Driver | v1.59.0 | Persistent block storage volumes |
| EFS CSI Driver | v3.1.0 | Shared file storage volumes |
| Pod Identity Agent | v1.3.10 | Workload-to-cloud IAM credential injection |

### Cluster Access

| Entry | Type | Description |
|-------|------|-------------|
| Provisioner role | `STANDARD` | Ryvn provisioner access (RyvnAccessRole) with `AmazonEKSClusterAdminPolicy` |
| Karpenter node role | `EC2_LINUX` | Karpenter-managed nodes join the cluster automatically |
| Cluster admin access | Policy | `AmazonEKSClusterAdminPolicy` bound to provisioner for bootstrapping, demoted post-provisioning |
| Worker node policies | Policy | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy` bound to Karpenter nodes |

## Autoscaling

| Resource | Count | Description |
|----------|-------|-------------|
| Autoscaler Controller Role | 1 | IAM role for the Karpenter controller (manages node lifecycle) |
| Autoscaler Node Role | 1 | IAM role assumed by Karpenter-provisioned EC2 instances |
| Interruption Queue (SQS) | 1 | Receives EC2 interruption events for graceful node draining |
| Queue Policy | 1 | Allows EventBridge to publish to the interruption queue |
| Pod Identity Association | 1 | Maps `kube-system/karpenter` service account → controller role |

### Interruption Event Rules

| Rule | Description |
|------|-------------|
| Spot Interrupt | EC2 spot instance interruption warning |
| Instance State Change | EC2 instance state-change notification |
| Instance Rebalance | EC2 instance rebalance recommendation |
| Health Event | AWS health event |
| Capacity Reservation Interrupt | EC2 capacity reservation instance interruption warning |

Each rule forwards matching events to the interruption SQS queue.

## Identity & Access

### Cluster Roles

| Role | Trust | Purpose |
|------|-------|---------|
| Cluster Role | AWS EKS service | EKS control plane operations (`AmazonEKSClusterPolicy`) |
| System Node Group Role | AWS EC2 service | System node group instances (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`) |

### Workload Identity Roles

| Role | Namespace / Service Account | Purpose |
|------|----------------------------|---------|
| EBS CSI Driver | `kube-system/ebs-csi-*` | Manage EBS volumes (create, attach, snapshot) via IRSA |
| EFS CSI Driver | `kube-system/efs-csi-*` | Manage EFS mount targets via IRSA |
| Ryvn Agent | platform namespace | In-cluster agent for Helm/Terraform task execution |
| Cert Manager | `cert-manager/cert-manager` | DNS-01 challenge solving for TLS certificates via Pod Identity |
| External DNS | platform namespace | Route53 record management for service discovery via IRSA |
| Load Balancer Controller | platform namespace | AWS Load Balancer provisioning for Kubernetes services/ingresses via IRSA |

### Policies

| Policy | Attached To | Purpose |
|--------|------------|---------|
| EBS CSI Policy | EBS CSI Driver role | Volume and snapshot operations scoped to EBS |
| EFS CSI Policy | EFS CSI Driver role | Mount target and file system operations scoped to EFS |
| Cluster Encryption Policy | Cluster role | KMS encrypt/decrypt for secrets envelope encryption |
| Agent Self-Management | Ryvn Agent role | Agent's permissions for managing its own workloads |
| Karpenter Controller (inline) | Karpenter Controller role | EC2 fleet management, pricing, SSM for AMI discovery |

## DNS

| Resource | Count | Description |
|----------|-------|-------------|
| Private Hosted Zone | 1 | Internal DNS (`<env>.<org-hash>.ryvn.internal`) — cluster-internal service discovery, associated with the VPC |
| Public Hosted Zone | 1 | External DNS (`<env>.<org-hash>.ryvn.run`) — customer-facing endpoints |
| NS Record | 1 | Delegation record for the public zone |

## Encryption

| Resource | Count | Description |
|----------|-------|-------------|
| KMS Key | 1 | Envelope encryption key for Kubernetes secrets at rest, automatic annual rotation enabled |
| KMS Alias | 1 | Human-readable alias for the cluster encryption key |

## Resource Summary

| Category | Managed Resources |
|----------|-------------------|
| Networking | 28 (VPC, subnets, gateways, routes, NACLs) |
| Security Groups + Rules | 18 (2 SGs + 15 rules + 1 default) |
| Cluster | 3 (EKS cluster, node group, launch template) |
| Cluster Add-ons | 6 |
| Cluster Access | 5 (2 access entries + 3 policy associations) |
| Autoscaling | 14 (roles, queue, event rules, targets, pod identity) |
| Identity & Access | 31 (10 roles + 4 policies + 5 inline policies + 12 attachments) |
| DNS | 4 (2 zones + 1 record + tags) |
| Encryption | 2 (key + alias) |
| Other | 6 (EC2 tags, time_sleep, null_resource) |
| **Total** | **117** |
