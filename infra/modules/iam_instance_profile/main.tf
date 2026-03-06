resource "aws_iam_instance_profile" "this" {
  name = var.name
  role = var.role_name

  tags = merge(
    var.tags,
    {
      "Name"      = var.name
      "ManagedBy" = "terraform"
      "Project"   = var.project
    }
  )
}
