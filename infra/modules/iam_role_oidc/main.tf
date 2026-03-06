resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = var.description
  max_session_duration = var.max_session_duration

  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = merge(
    var.tags,
    {
      "ManagedBy" = "terraform"
      "Project"   = var.project
    }
  )
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.subject_claims
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}
