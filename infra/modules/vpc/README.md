# VPC Module

Reusable module for creating a VPC with public, private, and data subnets across
multiple availability zones, including NAT gateways, VPC flow logs, and optional
VPC peering.

## Usage

```hcl
module "control_vpc" {
  source = "../../modules/vpc"

  name       = "infra-lab-dev-control"
  cidr_block = "10.0.0.0/20"

  enable_internet_gateway = true
  nat_gateway_count       = 1

  public_subnets = [
    { cidr = "10.0.0.0/24", az = "us-east-1a" },
    { cidr = "10.0.1.0/24", az = "us-east-1b" },
    { cidr = "10.0.2.0/24", az = "us-east-1c" },
  ]

  private_subnets = [
    { cidr = "10.0.4.0/22", az = "us-east-1a" },
    { cidr = "10.0.8.0/22", az = "us-east-1b" },
    { cidr = "10.0.12.0/22", az = "us-east-1c" },
  ]

  data_subnets = [
    { cidr = "10.0.3.0/26", az = "us-east-1a" },
    { cidr = "10.0.3.64/26", az = "us-east-1b" },
    { cidr = "10.0.3.128/26", az = "us-east-1c" },
  ]

  enable_flow_logs         = true
  flow_log_destination_arn = "arn:aws:s3:::my-flow-logs-bucket"

  tags = { Environment = "dev" }
}
```

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| name | Name prefix for all resources | string | - | yes |
| cidr_block | VPC CIDR block | string | - | yes |
| enable_internet_gateway | Create IGW | bool | true | no |
| public_subnets | Public subnet definitions | list(object) | [] | no |
| private_subnets | Private subnet definitions | list(object) | [] | no |
| data_subnets | Data/DB subnet definitions | list(object) | [] | no |
| nat_gateway_count | Number of NAT GWs (0,1,2,3) | number | 1 | no |
| enable_flow_logs | Enable VPC flow logs | bool | true | no |
| flow_log_destination_type | s3 or cloud-watch-logs | string | s3 | no |
| flow_log_destination_arn | Destination ARN | string | null | no |
| peer_vpc_id | VPC to peer with | string | null | no |
| peer_vpc_cidr | Peer VPC CIDR | string | null | no |
| project | Project tag | string | infra-lab | no |
| tags | Additional tags | map(string) | {} | no |

## Outputs

| Name | Description |
| --- | --- |
| vpc_id | VPC ID |
| vpc_arn | VPC ARN |
| vpc_cidr_block | VPC CIDR |
| public_subnet_ids | Public subnet IDs |
| private_subnet_ids | Private subnet IDs |
| data_subnet_ids | Data subnet IDs |
| public_route_table_id | Public route table ID |
| private_route_table_ids | Private route table IDs |
| data_route_table_id | Data route table ID |
| nat_gateway_ids | NAT Gateway IDs |
| nat_gateway_public_ips | NAT Gateway EIPs |
| internet_gateway_id | IGW ID |
| peering_connection_id | Peering connection ID |
