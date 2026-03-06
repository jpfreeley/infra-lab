terraform {
  backend "s3" {
    bucket         = "infra-lab-tf-state-551452024305"
    key            = "mgmt/backend/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "infra-lab-tf-state-locks"
    encrypt        = true
    kms_key_id     = "alias/aws/s3"
  }
}
