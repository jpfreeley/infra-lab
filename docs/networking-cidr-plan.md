# Networking CIDR Plan

## Overview

Each environment gets two VPCs (Control + Execution) to enforce network segmentation.
The Control VPC hosts management/orchestration workloads. The Execution VPC hosts
tenant workloads with restricted egress.

## CIDR Allocation

| Environment | VPC | CIDR | Usable IPs |
| --- | --- | --- | --- |
| dev | Control | 10.0.0.0/20 | 4,094 |
| dev | Execution | 10.0.16.0/20 | 4,094 |
| staging | Control | 10.0.32.0/20 | 4,094 |
| staging | Execution | 10.0.48.0/20 | 4,094 |
| prod | Control | 10.0.64.0/20 | 4,094 |
| prod | Execution | 10.0.80.0/20 | 4,094 |
| workspaces | WorkSpaces | 10.0.96.0/20 | 4,094 |
| reserved | future | 10.0.112.0/20 | 4,094 |

## Subnet Layout (per VPC, 3 AZs)

Each /20 VPC is divided into subnet tiers across 3 AZs:

| Tier | Purpose | Size | AZ-a | AZ-b | AZ-c |
| --- | --- | --- | --- | --- | --- |
| public | NAT GW, ALB | /24 | .0.0/24 | .1.0/24 | .2.0/24 |
| private | Compute (ECS/Lambda) | /22 | .4.0/22 | .8.0/22 | .12.0/22 |
| data | RDS, ElastiCache | /26 | .3.0/26 | .3.64/26 | .3.128/26 |

### Dev Control VPC (10.0.0.0/20)

| Tier | AZ | CIDR |
| --- | --- | --- |
| public | us-east-1a | 10.0.0.0/24 |
| public | us-east-1b | 10.0.1.0/24 |
| public | us-east-1c | 10.0.2.0/24 |
| data | us-east-1a | 10.0.3.0/26 |
| data | us-east-1b | 10.0.3.64/26 |
| data | us-east-1c | 10.0.3.128/26 |
| private | us-east-1a | 10.0.4.0/22 |
| private | us-east-1b | 10.0.8.0/22 |
| private | us-east-1c | 10.0.12.0/22 |

### Dev Execution VPC (10.0.16.0/20)

| Tier | AZ | CIDR |
| --- | --- | --- |
| public | us-east-1a | 10.0.16.0/24 |
| public | us-east-1b | 10.0.17.0/24 |
| public | us-east-1c | 10.0.18.0/24 |
| data | us-east-1a | 10.0.19.0/26 |
| data | us-east-1b | 10.0.19.64/26 |
| data | us-east-1c | 10.0.19.128/26 |
| private | us-east-1a | 10.0.20.0/22 |
| private | us-east-1b | 10.0.24.0/22 |
| private | us-east-1c | 10.0.28.0/22 |

### Staging Control VPC (10.0.32.0/20)

| Tier | AZ | CIDR |
| --- | --- | --- |
| public | us-east-1a | 10.0.32.0/24 |
| public | us-east-1b | 10.0.33.0/24 |
| public | us-east-1c | 10.0.34.0/24 |
| data | us-east-1a | 10.0.35.0/26 |
| data | us-east-1b | 10.0.35.64/26 |
| data | us-east-1c | 10.0.35.128/26 |
| private | us-east-1a | 10.0.36.0/22 |
| private | us-east-1b | 10.0.40.0/22 |
| private | us-east-1c | 10.0.44.0/22 |

### Staging Execution VPC (10.0.48.0/20)

| Tier | AZ | CIDR |
| --- | --- | --- |
| public | us-east-1a | 10.0.48.0/24 |
| public | us-east-1b | 10.0.49.0/24 |
| public | us-east-1c | 10.0.50.0/24 |
| data | us-east-1a | 10.0.51.0/26 |
| data | us-east-1b | 10.0.51.64/26 |
| data | us-east-1c | 10.0.51.128/26 |
| private | us-east-1a | 10.0.52.0/22 |
| private | us-east-1b | 10.0.56.0/22 |
| private | us-east-1c | 10.0.60.0/22 |

### Prod Control VPC (10.0.64.0/20)

| Tier | AZ | CIDR |
| --- | --- | --- |
| public | us-east-1a | 10.0.64.0/24 |
| public | us-east-1b | 10.0.65.0/24 |
| public | us-east-1c | 10.0.66.0/24 |
| data | us-east-1a | 10.0.67.0/26 |
| data | us-east-1b | 10.0.67.64/26 |
| data | us-east-1c | 10.0.67.128/26 |
| private | us-east-1a | 10.0.68.0/22 |
| private | us-east-1b | 10.0.72.0/22 |
| private | us-east-1c | 10.0.76.0/22 |

### Prod Execution VPC (10.0.80.0/20)

| Tier | AZ | CIDR |
| --- | --- | --- |
| public | us-east-1a | 10.0.80.0/24 |
| public | us-east-1b | 10.0.81.0/24 |
| public | us-east-1c | 10.0.82.0/24 |
| data | us-east-1a | 10.0.83.0/26 |
| data | us-east-1b | 10.0.83.64/26 |
| data | us-east-1c | 10.0.83.128/26 |
| private | us-east-1a | 10.0.84.0/22 |
| private | us-east-1b | 10.0.88.0/22 |
| private | us-east-1c | 10.0.92.0/22 |

### WorkSpaces VPC (10.0.96.0/20)

| Tier | AZ | CIDR |
| --- | --- | --- |
| public | us-east-1a | 10.0.96.0/24 |
| public | us-east-1b | 10.0.97.0/24 |
| data | us-east-1a | 10.0.99.0/26 |
| data | us-east-1b | 10.0.99.64/26 |
| private | us-east-1a | 10.0.100.0/22 |
| private | us-east-1b | 10.0.104.0/22 |

## VPC Endpoint Strategy

Control VPCs get Interface endpoints for private AWS API access:

- S3 (Gateway) - all VPCs
- ECR API + DKR (Interface) - Control VPC
- CloudWatch Logs (Interface) - both VPCs
- Monitoring (Interface) - Control VPC
- Secrets Manager (Interface) - Control VPC
- SQS (Interface) - Control VPC
- SSM (Interface) - Control VPC
- KMS (Interface) - Control VPC
- STS (Interface) - Control VPC

## NAT Gateway Strategy

| Environment | NAT GWs | Rationale |
| --- | --- | --- |
| dev | 1 (single AZ) | Cost optimization |
| staging | 1 (single AZ) | Cost optimization |
| prod | 3 (per AZ) | High availability |
| workspaces | 1 (single AZ) | Cost optimization |

## VPC Peering

Control ↔ Execution VPCs within the same environment are peered to allow:

- PrivateLink consumer endpoints in Execution VPC to reach services in Control VPC
- Controlled cross-VPC traffic via security groups (no open routing)

## Design Principles

1. No internet-routable traffic in Execution VPCs
2. All AWS API calls route through VPC endpoints
3. NACLs enforce RFC1918 egress denial on Execution private subnets
4. Security groups use reference-based rules (no CIDR-based SG rules between tiers)
5. Flow logs enabled on all VPCs, shipped to central log bucket
