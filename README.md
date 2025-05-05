# Ryvn Environments

This repository contains Terraform modules for provisioning and managing Ryvn environments on AWS. It provides infrastructure-as-code solutions for setting up EKS clusters with different configuration options.

## Available Modules

### IAM Role Module
Located in `/iam-role`, this module provisions the necessary IAM roles and policies for creating and managing Ryvn environments. It creates:
- An IAM role named "RyvnAccessRole"
- Associated trust policies
- Provision and deprovision policies

For detailed usage instructions, see the [IAM Role Module README](iam-role/README.md).

### Environment Types

The repository supports the following environment types:
- `aws-eks-byoc` - AWS EKS with Bring Your Own Cloud
- `aws-eks-byovpc` - AWS EKS with Bring Your Own VPC

Each environment type includes specific IAM permissions and configurations required for provisioning and managing the environment.

## Prerequisites

- Terraform >= 1.0
- AWS Provider
- AWS CLI configured with appropriate credentials

## Quick Start

1. Choose the appropriate module for your needs
2. Follow the module-specific README for detailed setup instructions
3. Use Terraform to provision your infrastructure

Example using the IAM Role module:

```hcl
module "iam-role" {
  source      = "github.com/ryvn-technologies/environments//iam-role"
  environment = "aws-eks-byovpc"  # or "aws-eks-byoc"
}
```

## Repository Structure

```
.
├── aws-eks-byoc/          # BYOC environment configuration
│   └── permissions/       # IAM permissions for BYOC
├── iam-role/             # IAM role module
│   ├── README.md         # Module documentation
│   └── *.tf              # Terraform configuration files
└── README.md             # This file
```

## License

Proprietary - All rights reserved

## Support

For support, please contact the Ryvn Technologies team.
