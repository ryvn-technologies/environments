# IAM Permission Policies

IAM policies for the `RyvnAccessRole` used to provision and deprovision BYOC (EKS + Karpenter) environments.

## Policy Files

| File | Mode | Description |
|------|------|-------------|
| `provision-policy.json` | Standard | Full VPC + EKS provisioning |
| `deprovision-policy.json` | Standard | Full VPC + EKS teardown |
| `byo-vpc-provision-policy.json` | BYO-VPC (carve) | EKS provisioning within customer-provided VPC, Ryvn carving its own subnets |
| `byo-vpc-deprovision-policy.json` | BYO-VPC (carve) | EKS teardown within customer-provided VPC |
| `byo-subnets-provision-policy.json` | BYO-subnets | EKS provisioning into pre-existing customer subnets, creating no network topology |
| `byo-subnets-deprovision-policy.json` | BYO-subnets | EKS teardown that leaves the customer's network untouched |
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

### Scoping what `ec2:Vpc` cannot reach

`natgateway` and `elastic-ip` support no `ec2:Vpc` condition key at all, so NAT and EIP actions cannot be confined to the customer VPC. They do support tag conditions, which is the alternative lever:

- `ec2:DeleteNatGateway` — `aws:ResourceTag/${TagKey}`, `ec2:ResourceTag/${TagKey}`
- `ec2:ReleaseAddress`, `ec2:DisassociateAddress` — the same, plus `ec2:AllocationId`, `ec2:Domain`, `ec2:PublicIpAddress`
- `ec2:CreateNatGateway`, `ec2:AllocateAddress` — `aws:RequestTag/${TagKey}`, `aws:TagKeys` on the resource being created

`byo-vpc-deprovision-policy.json` uses this for `NatGatewayTeardown`, conditioned on `aws:ResourceTag/Cluster` matching `ryvn-*` — the `Cluster` tag that `infra/aws-provision-karpenter/main.tf` applies to everything it creates.

**The pattern must be `ryvn-*`, not `ryvn-eks-*`.** `local.cluster_name` (`main.tf:99-104`) is `ryvn-eks-${environment_name}` only while that is 36 characters or fewer; beyond that the prefix is rewritten to `ryvn-` and the value truncated to 36. A `ryvn-eks-*` pattern silently excludes every long-named environment, leaving an undeletable — and billed — NAT gateway behind.

This is an interim measure on two counts. `Cluster` is a tag a customer could also set, so it bounds blast radius rather than proving ownership; and a prefix match is inherently looser than an ownership assertion. The durable fix is a dedicated constant-valued tag (`ryvn.app/managed = "true"`) enforced at create time via `aws:RequestTag` and required at destroy time via `aws:ResourceTag`, which permits `StringEquals` instead of `StringLike` and closes the loop for NAT, EIPs *and* the wildcard child-resource grants. Tracked in ENG-1468.

### Known gaps

- `ec2:ReleaseAddress` and `ec2:DisassociateAddress` are still granted on `Resource: *` in `DeprovisionInfrastructure`. They are tag-scopable in principle, but `DisassociateAddress` also takes a `network-interface` resource, so narrowing it needs two coordinated statements and a verified teardown — deferred to ENG-1468 rather than risking a stuck deprovision.
- The `ryvn-eks-*` prefix match assumes the NAT gateway actually carries the `Cluster` tag. If a teardown is ever denied on `ec2:DeleteNatGateway`, check the tag first; the previous behaviour was an unconditional denial, so this can only be an improvement, but it is not yet verified against a real create-NAT teardown.

## BYO-subnets policies

Use these when the environment sets `existing_workload_subnet_ids` — Ryvn consumes subnets the
customer already created and creates **no** network topology. They are the same as the BYO-VPC
policies with every network-mutating action removed:

- No `ec2:CreateSubnet`, `ec2:CreateRouteTable`, `ec2:CreateRoute`, `ec2:AssociateRouteTable`,
  `ec2:CreateNatGateway`, `ec2:AllocateAddress`, `ec2:ModifySubnetAttribute`.
- No `ec2:DeleteSubnet`, `ec2:DeleteRoute`, `ec2:DeleteRouteTable`, `ec2:DisassociateRouteTable`,
  `ec2:DeleteNatGateway`, `ec2:ReleaseAddress`, `ec2:DisassociateAddress` on teardown.
- Security group create/authorize/revoke stay, VPC-scoped: Ryvn still owns the cluster and node
  security groups. `ec2:CreateTags` stays, because Ryvn tags the resources it does create (EKS
  cluster, launch templates, security groups, KMS keys) — it does not tag the customer's subnets.

This is not merely least privilege. In a centrally-managed landing zone the network-mutating
actions are often denied by an **SCP in the organization's management account**, which no policy
or permissions boundary on `RyvnAccessRole` can override. In that situation carve mode cannot
work at all and BYO-subnets mode is the only option; these files are the action set that is
actually grantable there.

### `${partition}` placeholder

Unlike the BYO-VPC files, these use `${partition}` instead of a literal `aws` in every ARN.
Substitute `aws` in commercial regions, `aws-us-gov` in GovCloud, `aws-cn` in China. A literal
`arn:aws:` in a GovCloud policy matches nothing, and the statement then contributes no Allow —
the same silent-denial failure mode as the `ec2:Vpc` issue above.

### Confirm the deny is an SCP and not this policy

An identity-policy gap and an SCP deny look identical from the caller's side
(`UnauthorizedOperation`). Distinguish them without mutating anything:

```bash
# Authorized by identity policy AND allowed by SCP => DryRunOperation
aws ec2 create-subnet --vpc-id <vpc_id> --cidr-block <unused-cidr> --dry-run
aws ec2 create-route-table --vpc-id <vpc_id> --dry-run
aws ec2 create-security-group --vpc-id <vpc_id> --group-name probe --description probe --dry-run
```

If `create-security-group` dry-runs successfully while `create-subnet` and `create-route-table` do
not, the identity policy is fine and the denial is above the account — BYO-subnets mode is the
answer, not a policy edit. `aws organizations describe-policy` from the management account (if you
have that access) names the SCP; from the workload account, the dry-run contrast is the evidence.

Note that dry-run coverage is uneven: `eks:CreateCluster` has no dry-run, so "can EKS itself be
created here?" cannot be answered this way and is confirmed only by provisioning.

## BYO-VPC vs Standard

BYO-VPC policies exclude VPC-lifecycle actions (`CreateVpc`, `DeleteVpc`, `CreateInternetGateway`, etc.) since the customer owns the VPC. All EKS, IAM, KMS, DNS, and observability permissions are identical.

## Source

Policies were captured via IAM Access Analyzer + CloudTrail during live provisioning/deprovisioning (`eu-west-2`) using `RyvnAccessRole`. Cold-destroy refresh actions (read/list operations needed when Terraform state is stale) were added manually based on provider documentation.

Two consequences worth knowing when editing these files:

- Access Analyzer infers conditions from observed calls **without checking they are satisfiable** — it produced the unsatisfiable `ec2:Vpc`-on-create grants described above. Treat generated conditions as a starting point and probe them.
- Capture also picks up grants with no consumer in the Terraform. IAM user/group **writes**, `ec2:RunInstances`, `ec2:AuthorizeClientVpnIngress` and ECR/ELB actions were present in all four policy files without any resource of that type being declared by `infra/aws-provision-karpenter` or `infra/aws-provision`; they have since been removed. Before adding an action, confirm something actually calls it.

The read-only IAM user/group actions (`GetUser`, `GetUserPolicy`, `GetGroupPolicy`, `ListAttachedUserPolicies`, `ListUserPolicies`, `ListUserTags`, `ListAttachedGroupPolicies`) are deliberately kept: they appear in the capture, cannot escalate privilege, and ruling out every provider-internal read is not worth a 403 mid-provision.
