# GCP IAM permissions

Set up the `ryvn-provisioner` service account for your GKE environment.

## Grants

| Grant | Scope | Purpose |
|-------|-------|---------|
| [`projects/<project>/roles/ryvnProvisioner`](provisioner-role.yaml) | project | Provision and manage the environment |
| `roles/container.admin` | project | Install Ryvn in GKE |
| `roles/iam.workloadIdentityUser` | the `ryvn-provisioner` service account | Authenticate Ryvn through Workload Identity Federation |

Use a dedicated project per environment.

## Setup

```bash
PROJECT_ID=<your-project>          # Environment project
WIF_PROJECT_ID=$PROJECT_ID         # Workload Identity pool project
WIF_PROJECT_NUMBER=$(gcloud projects describe "$WIF_PROJECT_ID" --format='value(projectNumber)')
POOL_NAME=ryvn-aws-pool
PROVIDER_NAME=ryvn-aws
RYVN_ROLE_ARN=arn:aws:sts::703671917981:assumed-role/RyvnManagerRole

# 1. Enable APIs
gcloud services enable --project="$PROJECT_ID" \
  iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com compute.googleapis.com container.googleapis.com \
  servicenetworking.googleapis.com dns.googleapis.com cloudkms.googleapis.com \
  sqladmin.googleapis.com redis.googleapis.com

# 2. Create the custom role
gcloud iam roles create ryvnProvisioner --project="$PROJECT_ID" --file=provisioner-role.yaml
# To update an existing role:
# gcloud iam roles update ryvnProvisioner --project="$PROJECT_ID" --file=provisioner-role.yaml

# 3. Create the service account
gcloud iam service-accounts create ryvn-provisioner --project="$PROJECT_ID" \
  --display-name="Ryvn provisioner"
SA=ryvn-provisioner@${PROJECT_ID}.iam.gserviceaccount.com

# 4. Grant project roles
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA" --role="projects/$PROJECT_ID/roles/ryvnProvisioner"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA" --role="roles/container.admin"

# 5. Create the Workload Identity pool and AWS provider (skip existing resources)
gcloud iam workload-identity-pools create "$POOL_NAME" \
  --project="$WIF_PROJECT_ID" --location=global --display-name="Ryvn Pool"
gcloud iam workload-identity-pools providers create-aws "$PROVIDER_NAME" \
  --project="$WIF_PROJECT_ID" --location=global --workload-identity-pool="$POOL_NAME" \
  --account-id=703671917981 \
  --attribute-mapping="google.subject=assertion.arn,attribute.aws_role=assertion.arn.contains('assumed-role') ? assertion.arn.extract('{account_arn}assumed-role/') + 'assumed-role/' + assertion.arn.extract('assumed-role/{role_name}/') : assertion.arn"

# 6. Grant Ryvn access to the service account
gcloud iam service-accounts add-iam-policy-binding "$SA" --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${WIF_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.aws_role/${RYVN_ROLE_ARN}"

# 7. Generate the credential configuration to paste into Ryvn
gcloud iam workload-identity-pools create-cred-config \
  "projects/${WIF_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}" \
  --service-account="$SA" --aws --enable-imdsv2 --output-file=ryvn-cred-config.json
```

If your organization hosts Workload Identity pools in a central project, set `WIF_PROJECT_ID` to
that project and run step 5 there once. Steps 2 to 4, 6 and 7 are per target project. Whoever runs
these commands needs `roles/serviceusage.serviceUsageAdmin`, `roles/iam.serviceAccountAdmin`,
`roles/iam.roleAdmin` and `roles/resourcemanager.projectIamAdmin` in the target project, and
`roles/iam.workloadIdentityPoolAdmin` wherever the pool lives.

## What the permissions are for

| Group | Used for |
|-------|----------|
| `resourcemanager.projects.*` | Read the project and manage the project IAM bindings listed in [provisioned resources](../resources/provisioned-resources.md) |
| `serviceusage.*` | Enable the Service Networking and Cloud KMS APIs if they are off |
| `compute.networks.*`, `compute.subnetworks.*`, `compute.firewalls.*` | VPC, subnet with secondary ranges and flow logs, firewall rules |
| `compute.addresses.*`, `compute.routers.*` | Reserved NAT IP, Cloud Router, Cloud NAT |
| `compute.globalAddresses.*`, `servicenetworking.*`, `compute.networks.*Peering` | Private Services Access range and peering for Cloud SQL and Memorystore |
| `container.*`, `compute.instanceGroupManagers.get` | Private GKE cluster and node pools |
| `iam.serviceAccounts.*` | Node, agent, DNS and certificate service accounts and their Workload Identity bindings |
| `iam.roles.*` | The agent's custom roles |
| `resourcemanager.tagKeys.*`, `resourcemanager.tagValues.*` | Tag that scopes the agent's Cloud SQL permissions |
| `dns.*` | Public zone with a CAA record, private zone bound to the VPC |
| `cloudkms.*` | Key ring and key for GKE secrets encryption |
| `compute.zones.list`, `compute.*Operations.get`, `compute.regions.*`, `compute.projects.get` | Project, region and zone lookups |

## Deprovisioning

Uninstall Ryvn-managed services before deprovisioning the environment. Deprovisioning disables
KMS key rotation and schedules key versions for destruction. Key rings and keys remain in the
project.
