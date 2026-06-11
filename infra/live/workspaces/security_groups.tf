# DCV Desktop Security Groups
# Epic: E13 - AWS WorkSpaces Account

###############################################################################
# DCV Desktop Security Group
###############################################################################

module "dcv_sg" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-dcv"
  description = "Security group for NICE DCV desktop instances"
  vpc_id      = module.workspaces_vpc.vpc_id

  ingress = [
    {
      description = "NICE DCV (HTTPS/QUIC) from allowed IPs"
      from_port   = 8443
      to_port     = 8443
      protocol    = "tcp"
      cidr_blocks = var.allowed_ip_cidrs
    },
    {
      description = "NICE DCV UDP (QUIC) from allowed IPs"
      from_port   = 8443
      to_port     = 8443
      protocol    = "udp"
      cidr_blocks = var.allowed_ip_cidrs
    },
    {
      description = "SSH from allowed IPs"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ip_cidrs
    },
    {
      description = "Vite dev server (frontend) from allowed IPs"
      from_port   = 5173
      to_port     = 5173
      protocol    = "tcp"
      cidr_blocks = var.allowed_ip_cidrs
    },
    {
      description = "Flask dev server (backend) from allowed IPs"
      from_port   = 5000
      to_port     = 5000
      protocol    = "tcp"
      cidr_blocks = var.allowed_ip_cidrs
    },
    {
      description = "Supabase Studio (dashboard) from allowed IPs"
      from_port   = 54323
      to_port     = 54323
      protocol    = "tcp"
      cidr_blocks = var.allowed_ip_cidrs
    },
    {
      description = "Supabase API (local) from allowed IPs"
      from_port   = 54321
      to_port     = 54321
      protocol    = "tcp"
      cidr_blocks = var.allowed_ip_cidrs
    },
    {
      description = "code-server (browser VS Code) from allowed IPs"
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = var.allowed_ip_cidrs
    },
  ]

  egress = [
    {
      description = "All outbound"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    },
  ]

  tags = local.common_tags
}
