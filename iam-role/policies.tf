data "http" "environment_provision_policy" {
  url = "${local.permissions_base_url}/provision-policy.json"
}

resource "aws_iam_policy" "provision" {
  name   = "ryvn-${var.environment}-provision"
  policy = data.http.environment_provision_policy.response_body
}

data "http" "environment_deprovision_policy" {
  url = "${local.permissions_base_url}/deprovision-policy.json"
}

resource "aws_iam_policy" "deprovision" {
  name   = "ryvn-${var.environment}-deprovision"
  policy = data.http.environment_deprovision_policy.response_body
}

data "http" "environment_trust_policy" {
  url = "${local.permissions_base_url}/trust-policy.json"
}
