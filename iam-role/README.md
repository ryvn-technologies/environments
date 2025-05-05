# IAM Role Module

This Terraform module provisions an IAM role for granting access to create Ryvn Environments.

## Prerequisites

- Terraform >= 1.0
- AWS Provider
- AWS CLI configured with appropriate credentials

## Usage

### Option 1: Add to Existing Project

Add the following module block to your existing Terraform configuration:

```hcl
module "iam-role" {
  source      = "github.com/ryvn-technologies/environments//iam-role"
  environment = "aws-eks-byovpc"
}
```

### Option 2: Create New Project

1. Create a new directory and navigate to it:

```bash
mkdir ryvn-role && cd ryvn-role
```

2. Create a `main.tf` file:

```hcl
provider "aws" {
  region = "us-east-1" # or your preferred region
}

module "iam-role" {
  source      = "github.com/ryvn-technologies/environments//iam-role"
  environment = "aws-eks-byovpc"
}
```

## Deployment

1. Sign into AWS:

```bash
aws configure sso
# OR
aws configure
```

2. Initialize Terraform:

```bash
terraform init
```

3. Apply the configuration:

```bash
terraform apply
```

## Required Variables

- `environment` (string): Environment to use. Valid values:
  - `aws-eks`
  - `aws-eks-byovpc`

## Optional Variables

- `branch` (string): Branch to load permissions from. Defaults to "main"

## Outputs

The module will create:

- An IAM role named "RyvnAccessRole"
- Associated trust policy
- Provision and deprovision policies
