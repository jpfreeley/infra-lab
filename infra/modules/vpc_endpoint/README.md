# VPC Endpoint Module

Standardized module for creating AWS VPC Endpoints (Interface and Gateway).

## Usage (Gateway - S3)

```hcl
module "s3_endpoint" {
  source        = "../../modules/vpc_endpoint"
  vpc_id        = "vpc-12345"
  service_name  = "com.amazonaws.us-east-1.s3"
  endpoint_type = "Gateway"
  route_table_ids = ["rtb-12345"]
}
```

## Usage (Interface - KMS)

```hcl
module "kms_endpoint" {
  source             = "../../modules/vpc_endpoint"
  vpc_id             = "vpc-12345"
  service_name       = "com.amazonaws.us-east-1.kms"
  endpoint_type      = "Interface"
  subnet_ids         = ["subnet-123", "subnet-456"]
  security_group_ids = ["sg-12345"]
}
```
