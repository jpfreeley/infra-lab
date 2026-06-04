####
# Organization Tag Policies - E03-S020
#
# Enforces mandatory tagging standards across the organization.
# Tag policies define allowed tag keys and values, enabling consistent
# resource identification for cost allocation, ownership, and governance.
#
# Note: rds:db is not supported for tag policy enforcement.
# RDS tagging compliance is achieved via AWS Config rules instead.
####

resource "aws_organizations_policy" "tag_policy" {
  name        = "${local.project_name}-${local.environment}-mandatory-tags"
  description = "Enforce mandatory tag keys and value conventions across the organization."
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {
      project = {
        tag_key = {
          "@@assign" = "Project"
        }
        tag_value = {
          "@@assign" = [local.project_name]
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "ec2:volume",
            "s3:bucket",
            "lambda:function",
            "dynamodb:table",
            "secretsmanager:secret"
          ]
        }
      }
      managedby = {
        tag_key = {
          "@@assign" = "ManagedBy"
        }
        tag_value = {
          "@@assign" = ["terraform", "manual", "cloudformation"]
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "ec2:volume",
            "s3:bucket",
            "lambda:function",
            "dynamodb:table",
            "secretsmanager:secret"
          ]
        }
      }
      environment = {
        tag_key = {
          "@@assign" = "Environment"
        }
        tag_value = {
          "@@assign" = ["mgmt", "shared", "dev", "staging", "prod", "sandbox"]
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "ec2:volume",
            "s3:bucket",
            "lambda:function",
            "dynamodb:table",
            "secretsmanager:secret"
          ]
        }
      }
      owner = {
        tag_key = {
          "@@assign" = "Owner"
        }
      }
    }
  })

  tags = merge(local.common_tags, { Story = "E03-S020" })
}

# Attach tag policy at the Organization root to apply to all accounts
resource "aws_organizations_policy_attachment" "tag_policy_root" {
  policy_id = aws_organizations_policy.tag_policy.id
  target_id = data.aws_organizations_organization.org.roots[0].id
}
