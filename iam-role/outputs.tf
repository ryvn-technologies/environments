output "iam_role_arn" {
  value = module.iam_role.iam_role_arn
}

output "iam_role_name" {
  value = local.iam_role_name
}
