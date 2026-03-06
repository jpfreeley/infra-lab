
resource "aws_iam_policy" "this" {
  name        = var.policy_name
  description = var.description
  policy      = var.policy

  tags = merge(
    var.tags,
    {
      "ManagedBy" = "terraform"
      "Project"   = var.project
    }
  )
}

resource "aws_iam_policy_attachment" "roles" {
  for_each = { for k, v in var.attach_to : k => v if contains(keys(v), "roles") }

  name       = "${var.policy_name}-attachment-${each.key}"
  policy_arn = aws_iam_policy.this.arn
  roles      = each.value.roles
}

resource "aws_iam_policy_attachment" "groups" {
  for_each = { for k, v in var.attach_to : k => v if contains(keys(v), "groups") }

  name       = "${var.policy_name}-attachment-${each.key}"
  policy_arn = aws_iam_policy.this.arn
  groups     = each.value.groups
}
