# Networking Cost Controls

## Current State: Minimal Cost Mode ($0/mo)

All paid networking resources are disabled while no workloads are deployed.
The VPC infrastructure (subnets, route tables, peering, NACLs, security groups)
remains in place at zero cost, ready to activate when needed.

## What Is Disabled

| Resource | Files Affected | Saved |
|---|---|---|
| NAT Gateways | `infra/live/{dev,staging,prod}/vpc.tf` | $259.20/mo |
| Interface VPC Endpoints | `infra/live/{dev,staging,prod}/endpoints.tf` | $216.00/mo |
| VPC Flow Logs | `infra/live/{dev,staging,prod}/vpc.tf` | $0 (no data) |
| Flow Log KMS Keys | `infra/live/{dev,staging,prod}/flow_logs.tf` | $3.00/mo |
| Flow Log S3 Buckets | `infra/live/{dev,staging,prod}/flow_logs.tf` | $0 (empty) |
| **Total saved** | | **$478.20/mo** |

## What Remains Active (Free)

- VPCs (6 total: Control + Execution per env)
- Subnets (54 total: 9 per VPC × 6 VPCs)
- Route tables and associations
- Internet Gateways
- VPC Peering connections (Control ↔ Execution per env)
- Network ACLs (RFC1918 egress denial)
- Security Groups (ALB, ECS, RDS, Endpoint SGs)
- S3 Gateway VPC Endpoints (free tier)

## How to Resume Full Operation

### Step 1: Enable NAT Gateways

Edit `vpc.tf` in each environment you want to activate:

```hcl
# infra/live/dev/vpc.tf and infra/live/staging/vpc.tf
nat_gateway_count = 1   # Single NAT (cost-optimized)

# infra/live/prod/vpc.tf
nat_gateway_count = 3   # Per-AZ HA
```

**Cost impact**: $32.40/mo per NAT Gateway + $0.045/GB data processing

### Step 2: Enable Interface VPC Endpoints

Uncomment in `endpoints.tf` for each environment:

```hcl
# Uncomment the interface_endpoints_control module block
module "interface_endpoints_control" {
  source   = "../../modules/vpc_endpoint"
  for_each = toset(local.interface_endpoints)
  # ... (full block is preserved as comments in the file)
}

# Uncomment the endpoint_logs_execution module block
module "endpoint_logs_execution" {
  source = "../../modules/vpc_endpoint"
  # ... (full block is preserved as comments in the file)
}
```

**Cost impact**: ~$7.20/mo per endpoint (10 endpoints per env = ~$72/env)

### Step 3: Enable VPC Flow Logs

1. Uncomment the KMS key and S3 bucket in `flow_logs.tf`:

```hcl
module "flow_logs_kms" {
  source = "../../modules/kms_key"
  # ...
}

module "flow_logs_bucket" {
  source = "../../modules/s3_secure_bucket"
  # ...
}
```

2. Update `vpc.tf` in both VPC modules:

```hcl
enable_flow_logs         = true
flow_log_destination_arn = module.flow_logs_bucket.bucket_arn
```

**Cost impact**: $1/mo per KMS key + S3 storage costs (variable)

### Step 4: Apply

```bash
cd infra/live/dev
terraform init
terraform plan    # Review changes
terraform apply
```

Repeat for staging and prod as needed.

## Phased Re-Enablement (Recommended)

When starting E06 (Compute), re-enable only what is needed for dev:

| Phase | Resources | Monthly Cost |
|---|---|---|
| Minimal dev | 1 NAT + ECR/Logs/S3 endpoints only | ~$54/mo |
| Full dev | 1 NAT + all endpoints + flow logs | ~$106/mo |
| Add staging | Same as dev | +$106/mo |
| Full prod | 3 NATs + all endpoints + flow logs | +$313/mo |

### Minimal Dev (Recommended for E06 Start)

Only enable what ECS Fargate needs:

```hcl
# vpc.tf — Control VPC only
nat_gateway_count = 1

# endpoints.tf — uncomment only these 3:
# - com.amazonaws.us-east-1.ecr.api
# - com.amazonaws.us-east-1.ecr.dkr
# - com.amazonaws.us-east-1.logs
```

This gives ECS tasks the ability to pull images and ship logs for ~$54/mo.

## Cost Reference (us-east-1)

| Resource | Hourly | Monthly (730h) |
|---|---|---|
| NAT Gateway | $0.045 | $32.40 |
| NAT Data Processing | $0.045/GB | variable |
| Interface Endpoint (per AZ) | $0.01 | $7.20 |
| S3 Gateway Endpoint | FREE | $0 |
| KMS Key | - | $1.00 |
| VPC / Subnet / RT / SG / NACL / IGW / Peering | FREE | $0 |
