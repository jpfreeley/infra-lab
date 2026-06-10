# VPC Module
# Epic: E05 - Networking (Dual VPC per env)
# Stories: S001-S009 - VPC creation with per-AZ subnets and route tables

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    "Name"      = var.name
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# Internet Gateway (optional - only for VPCs with public subnets)
###############################################################################

resource "aws_internet_gateway" "this" {
  count  = var.enable_internet_gateway ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    "Name"      = "${var.name}-igw"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# Public Subnets
###############################################################################

resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index].cidr
  availability_zone       = var.public_subnets[count.index].az
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    "Name"      = "${var.name}-public-${var.public_subnets[count.index].az}"
    "Tier"      = "public"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_route_table" "public" {
  count  = length(var.public_subnets) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    "Name"      = "${var.name}-public-rt"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_route" "public_internet" {
  count = var.enable_internet_gateway && length(var.public_subnets) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnets)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

###############################################################################
# Private Subnets
###############################################################################

resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index].cidr
  availability_zone = var.private_subnets[count.index].az

  tags = merge(var.tags, {
    "Name"      = "${var.name}-private-${var.private_subnets[count.index].az}"
    "Tier"      = "private"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_route_table" "private" {
  count  = var.nat_gateway_count > 0 ? var.nat_gateway_count : (length(var.private_subnets) > 0 ? 1 : 0)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    "Name"      = var.nat_gateway_count > 1 ? "${var.name}-private-rt-${count.index}" : "${var.name}-private-rt"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnets)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.nat_gateway_count > 1 ? count.index % var.nat_gateway_count : 0].id
}

###############################################################################
# Data Subnets (DB tier)
###############################################################################

resource "aws_subnet" "data" {
  count = length(var.data_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.data_subnets[count.index].cidr
  availability_zone = var.data_subnets[count.index].az

  tags = merge(var.tags, {
    "Name"      = "${var.name}-data-${var.data_subnets[count.index].az}"
    "Tier"      = "data"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_route_table" "data" {
  count  = length(var.data_subnets) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    "Name"      = "${var.name}-data-rt"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_route_table_association" "data" {
  count = length(var.data_subnets)

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data[0].id
}

###############################################################################
# NAT Gateway(s)
###############################################################################

resource "aws_eip" "nat" {
  count  = var.nat_gateway_count
  domain = "vpc"

  tags = merge(var.tags, {
    "Name"      = var.nat_gateway_count > 1 ? "${var.name}-nat-eip-${count.index}" : "${var.name}-nat-eip"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_nat_gateway" "this" {
  count = var.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    "Name"      = var.nat_gateway_count > 1 ? "${var.name}-nat-${count.index}" : "${var.name}-nat"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat" {
  count = var.nat_gateway_count > 0 ? var.nat_gateway_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

###############################################################################
# VPC Flow Logs
###############################################################################

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = var.flow_log_destination_type
  log_destination      = var.flow_log_destination_arn
  log_format           = var.flow_log_format

  tags = merge(var.tags, {
    "Name"      = "${var.name}-flow-logs"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# VPC Peering (optional)
###############################################################################

resource "aws_vpc_peering_connection" "this" {
  count = var.peer_vpc_id != null ? 1 : 0

  vpc_id      = aws_vpc.this.id
  peer_vpc_id = var.peer_vpc_id
  auto_accept = true

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  tags = merge(var.tags, {
    "Name"      = "${var.name}-peering"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

# Route from private subnets to peer VPC
resource "aws_route" "private_to_peer" {
  count = var.peer_vpc_id != null && var.peer_vpc_cidr != null ? length(aws_route_table.private) : 0

  route_table_id            = aws_route_table.private[count.index].id
  destination_cidr_block    = var.peer_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this[0].id
}

# Route from data subnets to peer VPC
resource "aws_route" "data_to_peer" {
  count = var.peer_vpc_id != null && var.peer_vpc_cidr != null && length(var.data_subnets) > 0 ? 1 : 0

  route_table_id            = aws_route_table.data[0].id
  destination_cidr_block    = var.peer_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this[0].id
}
