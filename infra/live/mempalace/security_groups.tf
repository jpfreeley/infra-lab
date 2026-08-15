# MemPalace ALB Security Group
# The task's own security group (created inside the mempalace_server module)
# only accepts ingress from this SG's ID — never directly from the internet.

module "sg_alb" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-alb"
  description = "MemPalace ALB, public ingress, forwards to the ECS task only"
  vpc_id      = module.mempalace_vpc.vpc_id

  ingress = concat(
    [
      {
        description = "HTTP, redirects to HTTPS once enable_https is true, see ADR-034"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
      }
    ],
    var.enable_https ? [
      {
        description = "HTTPS"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
      }
    ] : []
  )

  egress = [
    {
      description = "To the ECS task"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = local.common_tags
}
