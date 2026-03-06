resource "aws_vpc_endpoint" "this" {
  vpc_id            = var.vpc_id
  service_name      = var.service_name
  vpc_endpoint_type = var.endpoint_type

  # Interface specific
  security_group_ids  = var.endpoint_type == "Interface" ? var.security_group_ids : null
  subnet_ids          = var.endpoint_type == "Interface" ? var.subnet_ids : null
  private_dns_enabled = var.endpoint_type == "Interface" ? var.private_dns_enabled : null

  # Gateway specific
  route_table_ids = var.endpoint_type == "Gateway" ? var.route_table_ids : null

  policy = var.policy

  tags = merge(
    var.tags,
    {
      "Name"      = "${var.project}-${var.service_name}-endpoint"
      "ManagedBy" = "terraform"
    }
  )
}
