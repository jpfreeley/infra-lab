resource "aws_instance" "this" {
  ami                    = var.ami
  instance_type          = var.instance_type
  iam_instance_profile   = var.iam_instance_profile
  vpc_security_group_ids = var.vpc_security_group_ids
  user_data              = var.user_data
  monitoring             = var.monitoring
  ebs_optimized          = var.ebs_optimized

  root_block_device {
    volume_type           = var.root_block_device_volume_type
    volume_size           = var.root_block_device_volume_size
    delete_on_termination = var.root_block_device_delete_on_termination
    encrypted             = var.root_block_device_encrypted
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  tags = merge(
    var.tags,
    {
      "Name"      = var.name
      "ManagedBy" = "terraform"
      "Project"   = var.project
    }
  )
}
