# VPC Module
# Creates a VPC with public and private subnets across 2 AZs

data "aws_availability_zones" "available" {
  state = "available"
}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    "Name"        = var.name
    "ManagedBy"   = "terraform"
    "Project"     = var.project
    "Environment" = var.environment
  })
}

###############################################################################
# Public Subnets
###############################################################################

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    "Name"      = "${var.name}-public-${data.aws_availability_zones.available.names[count.index]}"
    "ManagedBy" = "terraform"
    "Project"   = var.project
    "Tier"      = "public"
  })
}

###############################################################################
# Private Subnets
###############################################################################

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, {
    "Name"      = "${var.name}-private-${data.aws_availability_zones.available.names[count.index]}"
    "ManagedBy" = "terraform"
    "Project"   = var.project
    "Tier"      = "private"
  })
}

###############################################################################
# Internet Gateway (for public subnets)
###############################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    "Name"      = "${var.name}-igw"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# Route Tables
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    "Name"      = "${var.name}-public-rt"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    "Name"      = "${var.name}-private-rt"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
