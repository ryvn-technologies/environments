# Ryvn Environments

This repository holds the IAM permissions Ryvn needs to provision and manage environments in your AWS account or GCP project, plus a Terraform module that creates the AWS access role. Each environment type documents the permissions Ryvn needs and the resources it creates.

## Granting Ryvn access

### AWS

The `iam-role` Terraform module creates an IAM role named `RyvnAccessRole` with its trust policy and the provision and deprovision policies for the environment type you choose. See the [IAM role module README](iam-role/README.md).

### GCP

The Ryvn dashboard shows the `gcloud` commands that create the `ryvn-provisioner` service account, grant it the Ryvn Provisioner custom role plus Kubernetes Engine Admin, and let Ryvn impersonate it without any keys. The role definition is served by the Ryvn API, so the commands always match the Ryvn instance you use.

## Environment types

- `aws-eks-byoc`: AWS EKS, bring your own cloud
- `aws-eks-byovpc`: AWS EKS, bring your own VPC
- `gcp-gke-byoc`: GCP GKE, bring your own cloud

The `aws-eks-byoc` and `gcp-gke-byoc` directories each have a `resources/` folder listing what Ryvn creates; `aws-eks-byoc` also has a `permissions/` folder with the IAM policies Ryvn needs. The BYO-VPC policies live alongside the standard ones in `aws-eks-byoc/permissions`.

## Prerequisites

For AWS:
- Terraform 1.0 or later
- AWS CLI signed in to the target account

For GCP:
- gcloud CLI signed in to the target project

## Quick start

Pick your environment type, then follow its README.

AWS, using the Terraform module:

```hcl
module "iam-role" {
  source      = "github.com/ryvn-technologies/environments//iam-role"
  environment = "aws-eks-byovpc"  # or "aws-eks-byoc"
}
```

GCP: open the environment in the Ryvn dashboard and run the `gcloud` commands it shows.

## Repository structure

```
.
├── aws-eks-byoc/          # AWS EKS environment
│   ├── permissions/       # IAM policies for RyvnAccessRole
│   └── resources/         # What Ryvn creates in your account
├── gcp-gke-byoc/          # GCP GKE environment
│   └── resources/         # What Ryvn creates in your project
├── iam-role/              # Terraform module for the AWS role
│   ├── README.md
│   └── *.tf
└── README.md
```

## License

Proprietary - All rights reserved

## Support

For support, please contact the Ryvn Technologies team.
