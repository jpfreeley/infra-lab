# NetBird NLB Security Group
# The task's own security group (inside netbird_server) accepts TCP only
# from this SG. STUN reaches the task with the client's source IP preserved
# (always the case for NLB UDP), so the module opens UDP 3478 by CIDR.

module "sg_nlb" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-nlb"
  description = "NetBird NLB, public HTTPS and STUN, forwards to the ECS task only"
  vpc_id      = module.netbird_vpc.vpc_id

  ingress = concat(
    [
      {
        description = "HTTPS (management, signal, relay, dashboard)"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
      }
    ],
    local.embedded_stun ? [
      {
        description = "STUN"
        from_port   = 3478
        to_port     = 3478
        protocol    = "udp"
        cidr_blocks = ["0.0.0.0/0"]
      }
    ] : [],
  )

  egress = [
    {
      description = "To the ECS task and health checks, inside the VPC only"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [local.vpc_cidr]
    }
  ]

  tags = local.common_tags
}
