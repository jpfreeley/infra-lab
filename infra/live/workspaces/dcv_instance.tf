# Shared IAM + AMI for DCV Desktop Instances
# Instances are created by the Lambda API, not Terraform directly.

###############################################################################
# Official AWS DCV AMI (pre-installed DCV + MATE desktop)
###############################################################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["DCV-AmazonLinux2-x86_64-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

###############################################################################
# IAM Role for DCV Instance (SSM access + DCV license)
###############################################################################

module "dcv_instance_role" {
  source = "../../modules/iam_role"

  role_name   = "${local.name_prefix}-dcv-instance"
  description = "IAM role for DCV desktop instance (SSM + DCV licensing)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  attach_policy_arns = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.common_tags
}

# Scoped policy for DCV license, self-stop, secrets, and SSM access
resource "aws_iam_role_policy" "dcv_license" {
  name = "${local.name_prefix}-dcv-license"
  role = module.dcv_instance_role.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = "arn:aws:s3:::dcv-license.${var.aws_region}/*"
      },
      {
        Sid    = "SelfStop"
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = "infra-lab"
          }
        }
      },
      {
        Sid    = "SecretsAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:infra-lab/desktop/*"
      },
      {
        Sid    = "SSMRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/infra-lab/desktop/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "dcv" {
  name = "${local.name_prefix}-dcv-instance"
  role = module.dcv_instance_role.role_name

  tags = local.common_tags
}
