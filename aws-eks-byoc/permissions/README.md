# IAM Permission Policies

IAM policies for the `RyvnAccessRole` used to provision and deprovision BYOC (EKS + Karpenter) environments.

## Policy Files

| File | Mode | Description |
|------|------|-------------|
| `provision-policy.json` | Standard | Full VPC + EKS provisioning |
| `deprovision-policy.json` | Standard | Full VPC + EKS teardown |
| `byo-vpc-provision-policy.json` | BYO-VPC | EKS provisioning within customer-provided VPC |
| `byo-vpc-deprovision-policy.json` | BYO-VPC | EKS teardown within customer-provided VPC |
| `trust-policy.json` | All | Trust relationship for role assumption |

## BYO-VPC Policies

The BYO-VPC policies contain **template placeholders** in the `ec2:Vpc` condition that must be substituted before attaching to a role:

- `${region}` — AWS region (e.g., `us-east-1`)
- `${account_id}` — AWS account ID (e.g., `123456789012`)
- `${vpc_id}` — Customer's VPC ID (e.g., `vpc-0abc123def456`)

The `VpcScopedNetworkCreation` / `VpcScopedTeardown` statements use the `ec2:Vpc` condition key to restrict network-mutating actions to the customer-provided VPC only. The remaining actions use `Resource: *`.

## BYO-VPC vs Standard

BYO-VPC policies exclude VPC-lifecycle actions (`CreateVpc`, `DeleteVpc`, `CreateInternetGateway`, etc.) since the customer owns the VPC. All EKS, IAM, KMS, DNS, and observability permissions are identical.

## Source

Policies were captured via IAM Access Analyzer + CloudTrail during live provisioning/deprovisioning (`eu-west-2`) using `RyvnAccessRole`. Cold-destroy refresh actions (read/list operations needed when Terraform state is stale) were added manually based on provider documentation.
