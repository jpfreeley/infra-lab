# Network ACLs
# Epic: E05 - Networking (Dual VPC per env)
# Story: S020 - Execution VPC NACL: deny RFC1918 egress

resource "aws_network_acl" "execution_private" {
  vpc_id     = module.execution_vpc.vpc_id
  subnet_ids = module.execution_vpc.private_subnet_ids

  tags = merge(local.common_tags, {
    "Name"      = "${local.name_prefix}-execution-private-nacl"
    "ManagedBy" = "terraform"
    "Project"   = local.project
  })
}

# --- Ingress Rules ---

resource "aws_network_acl_rule" "execution_private_ingress_ephemeral" {
  # checkov:skip=CKV_AWS_231: "Ephemeral port range (1024-65535) is required for TCP return traffic — does not include port 3389"
  network_acl_id = aws_network_acl.execution_private.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "execution_private_ingress_https_control" {
  network_acl_id = aws_network_acl.execution_private.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.control_vpc_cidr
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "execution_private_ingress_intra_vpc" {
  # checkov:skip=CKV_AWS_352: "Intra-VPC traffic requires all protocols — scoped to Execution VPC CIDR only"
  network_acl_id = aws_network_acl.execution_private.id
  rule_number    = 120
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = local.execution_vpc_cidr
  from_port      = 0
  to_port        = 0
}

# --- Egress Rules ---

resource "aws_network_acl_rule" "execution_private_egress_https_internal" {
  network_acl_id = aws_network_acl.execution_private.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.execution_vpc_cidr
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "execution_private_egress_https_control" {
  network_acl_id = aws_network_acl.execution_private.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.control_vpc_cidr
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "execution_private_egress_ephemeral_internal" {
  network_acl_id = aws_network_acl.execution_private.id
  rule_number    = 120
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.execution_vpc_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "execution_private_egress_deny_rfc1918_10" {
  network_acl_id = aws_network_acl.execution_private.id
  rule_number    = 200
  egress         = true
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = "10.0.0.0/8"
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_rule" "execution_private_egress_deny_rfc1918_172" {
  network_acl_id = aws_network_acl.execution_private.id
  rule_number    = 210
  egress         = true
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = "172.16.0.0/12"
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_rule" "execution_private_egress_deny_rfc1918_192" {
  network_acl_id = aws_network_acl.execution_private.id
  rule_number    = 220
  egress         = true
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = "192.168.0.0/16"
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_rule" "execution_private_egress_allow_internet" {
  network_acl_id = aws_network_acl.execution_private.id
  rule_number    = 900
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}
