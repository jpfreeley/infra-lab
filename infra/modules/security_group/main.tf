resource "aws_security_group" "this" {
  # checkov:skip=CKV2_AWS_5: "Security Group is a library module; attachment occurs in the implementation layer"
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = lookup(ingress.value, "cidr_blocks", [])
      ipv6_cidr_blocks = lookup(ingress.value, "ipv6_cidr_blocks", [])
      security_groups  = lookup(ingress.value, "security_groups", [])
      self             = lookup(ingress.value, "self", false)
    }
  }

  dynamic "egress" {
    for_each = var.egress
    content {
      description      = egress.value.description
      from_port        = egress.value.from_port
      to_port          = egress.value.to_port
      protocol         = egress.value.protocol
      cidr_blocks      = lookup(egress.value, "cidr_blocks", [])
      ipv6_cidr_blocks = lookup(egress.value, "ipv6_cidr_blocks", [])
      security_groups  = lookup(egress.value, "security_groups", [])
      self             = lookup(egress.value, "self", false)
    }
  }

  tags = merge(
    var.tags,
    {
      "Name"      = var.name
      "ManagedBy" = "terraform"
      "Project"   = var.project
    }
  )
}
