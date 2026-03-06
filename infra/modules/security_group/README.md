# Security Group Module

Reusable Terraform module for AWS Security Groups with enforced descriptions on rules.

## Usage Example

```hcl
module "sg_example" {
  source      = "../../modules/security_group"
  name        = "example-sg"
  description = "Example security group"
  vpc_id      = "vpc-12345678"

  ingress = [
    {
      description = "Allow HTTP"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  egress = [
    {
      description = "Allow all outbound"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}
```
