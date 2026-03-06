# EC2 Instance Module

Reusable Terraform module for AWS EC2 instances with secure defaults.

## Usage Example

```hcl
module "ec2_example" {
  source              = "../../modules/ec2_instance"
  name                = "example-instance"
  ami                 = "ami-0c02fb55956c7d316"
  instance_type       = "t3.micro"
  iam_instance_profile = "example-instance-profile"
  vpc_security_group_ids = ["sg-12345678"]
  user_data           = file("user_data.sh")

  tags = {
    Environment = "dev"
  }
}
```
