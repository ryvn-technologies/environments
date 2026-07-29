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

### `ec2:Vpc` cannot gate resource creation

**Before adding an action to a `ec2:Vpc`-conditioned statement, check that the key is actually supported on that action's resource types.** If it is not, the condition can never match, the statement contributes no Allow, and the call is denied — silently, in the sense that the policy *looks* correct.

The authority is the [AWS Service Reference](https://servicereference.us-east-1.amazonaws.com/v1/ec2/ec2.json), which lists per action every resource type involved and the condition keys each supports:

```bash
curl -s https://servicereference.us-east-1.amazonaws.com/v1/ec2/ec2.json \
  | jq '.Actions[] | select(.Name=="CreateSubnet") | .Resources[]
        | {resource: .Name, vpcKey: (.ConditionKeys | index("ec2:Vpc") != null)}'
```

EC2 authorizes a call against **every** resource in the request, and each needs an Allow. For `CreateSubnet` those are `vpc` (the parent) and `subnet` (the child being created) — and `ec2:Vpc` is supported on *neither*. So creation needs two unconditioned statements:

1. `VpcResourceAccess` — the create actions on the **VPC ARN**. This is what actually confines creation to the customer's VPC: a create aimed at another VPC fails this parent check.
2. `ChildResourceCreation` — the same actions on the **child ARNs** (`subnet/*`, `route-table/*`, `security-group/*`, and for NAT `natgateway/*` + `elastic-ip/*`), which cannot be VPC-bound because the resource does not exist yet.

`ec2:CreateNatGateway` is the one create that *is* partly gateable — `ec2:Vpc` is supported on its `subnet` resource type — so it stays in the conditioned statement as well, which confines it to subnets in the customer VPC.

`ec2:AuthorizeSecurityGroupIngress`/`Egress` take a `security-group-rule` resource whenever tag specifications are supplied, and that type supports only `aws:RequestTag`/`aws:TagKeys`. Hence `SecurityGroupRuleCreation`. The `security-group` resource stays `ec2:Vpc`-gated, so this does not widen which security groups may be modified.

Actions on resources that already exist (`DeleteSubnet`, `DeleteRouteTable`, `CreateRoute`, `Revoke*`, …) resolve `ec2:Vpc` normally and need only the conditioned statement.

Verify any change with a non-mutating authorization probe rather than by reading the policy:

```bash
aws ec2 create-subnet --vpc-id <vpc_id> --cidr-block <unused-cidr> --dry-run
# DryRunOperation       => authorized
# UnauthorizedOperation => denied
```

### Known gap

`byo-vpc-deprovision-policy.json` still lists `ec2:DeleteNatGateway` in its `ec2:Vpc`-conditioned `VpcScopedTeardown` statement. `ec2:Vpc` is not supported on the `natgateway` resource type, so that grant is inert and NAT gateway teardown will be denied. Fixing it means granting `ec2:DeleteNatGateway` on `natgateway/*`, which cannot be VPC-scoped by any condition.

## BYO-VPC vs Standard

BYO-VPC policies exclude VPC-lifecycle actions (`CreateVpc`, `DeleteVpc`, `CreateInternetGateway`, etc.) since the customer owns the VPC. All EKS, IAM, KMS, DNS, and observability permissions are identical.

## Source

Policies were captured via IAM Access Analyzer + CloudTrail during live provisioning/deprovisioning (`eu-west-2`) using `RyvnAccessRole`. Cold-destroy refresh actions (read/list operations needed when Terraform state is stale) were added manually based on provider documentation.

Two consequences worth knowing when editing these files:

- Access Analyzer infers conditions from observed calls **without checking they are satisfiable** — it produced the unsatisfiable `ec2:Vpc`-on-create grants described above. Treat generated conditions as a starting point and probe them.
- Capture also picks up grants with no consumer in the Terraform. IAM user/group writes, `ec2:RunInstances`, `ec2:AuthorizeClientVpnIngress` and ECR/ELB actions were all present without any resource of that type being declared by `infra/aws-provision-karpenter`; they have since been removed. Before adding an action, confirm something actually calls it.
