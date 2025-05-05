variable "environment" {
  type        = string
  description = "environment to use"
  validation {
    condition = contains([
      "aws-eks-byoc",
      "aws-eks-byovpc",
    ], var.environment)
    error_message = "${var.environment} is not a valid environment"
  }
}

variable "branch" {
  type        = string
  default     = "main"
  description = "branch to load permissions from"
}
