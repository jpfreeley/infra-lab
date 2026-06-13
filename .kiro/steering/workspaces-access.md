# Workspaces Account Access (815802018602)

## Authentication Chain

The workspaces account has no direct SSO profile. Access via assume-role from the management account:

```bash
export $(aws sts assume-role \
  --role-arn arn:aws:iam::815802018602:role/OrganizationAccountAccessRole \
  --role-session-name debug \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text \
  --profile infra-lab | awk '{print "AWS_ACCESS_KEY_ID="$1" AWS_SECRET_ACCESS_KEY="$2" AWS_SESSION_TOKEN="$3}')
```

Terraform handles this via the `assume_role` block in `infra/live/workspaces/providers.tf`.

## SSH into Desktop or Ollama Instances

Uses EC2 Instance Connect (ephemeral keys, no permanent SSH key needed):

```bash
# 1. Generate temp key
rm -f /tmp/dcv_temp_key /tmp/dcv_temp_key.pub
ssh-keygen -t rsa -f /tmp/dcv_temp_key -N "" -q

# 2. Push key (valid 60 seconds) — requires assume-role creds active
aws ec2-instance-connect send-ssh-public-key \
  --instance-id <INSTANCE_ID> \
  --instance-os-user ec2-user \
  --ssh-public-key file:///tmp/dcv_temp_key.pub \
  --region us-east-1

# 3. Connect immediately (must be within 60s of push)
ssh -i /tmp/dcv_temp_key -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=15 ec2-user@<PUBLIC_IP>
```

## Important Notes

- **SSH user**: `ec2-user` (both DCV desktop AMI and Deep Learning AMI)
- **IdentitiesOnly=yes**: Required to prevent SSH agent from trying other keys (causes "Too many authentication failures")
- **Security group**: SSH (port 22) must be open from your IP in the instance's SG
- **DCV desktops SG**: `sg-0bd11b248b4ca2f91` — allows SSH from `allowed_ip_cidrs`
- **Ollama SG**: `sg-01b098f198888a1e6` — allows SSH from `allowed_ip_cidrs`
- **Ollama instance**: g4dn.xlarge, fixed private IP `10.0.96.100`
- **Desktop instances**: t3.large, dynamic IPs (check via API or AWS console)

## Finding Instance IPs

```bash
# List all running instances
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output text --region us-east-1

# Get Ollama public IP
aws ec2 describe-instances --instance-ids <OLLAMA_ID> \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text --region us-east-1
```

## Terraform Deployment

```bash
cd infra/live/workspaces
aws sso login --profile infra-lab
terraform apply -var='allowed_ip_cidrs=["YOUR.IP/32"]' -var='api_secret=YOUR_SECRET'
```
