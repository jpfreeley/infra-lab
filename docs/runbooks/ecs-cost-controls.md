# ECS Cost Controls (Dev Environment)

## Strategy

The dev environment runs with minimal idle costs. All worker services scale from zero
and the API runs a single task. Services scale up automatically via autoscaling when
load is applied.

## Idle Cost Breakdown

| Resource | Idle State | Monthly Cost |
| --- | --- | --- |
| ALB | Always-on (hourly charge) | ~$16 |
| API service | 1 task (512 CPU / 1024 MiB) | ~$15 |
| Worker nano | 0 tasks (scale-from-zero) | $0 |
| Worker medium | 0 tasks (scale-from-zero) | $0 |
| Worker xlarge | 0 tasks (scale-from-zero) | $0 |
| CloudWatch log groups | Storage only | ~$0 |
| **Total idle** | | **~$31/mo** |

## Bringing Services Up

### Option 1: Let Autoscaling Handle It (Recommended)

Workers scale automatically when their autoscaling triggers fire:

- **CPU-based**: Send traffic that generates CPU load
- **Queue-based** (future): Push messages to the SQS queue

No manual intervention needed — autoscaling will launch tasks when thresholds are met.

### Option 2: Manual Scale-Up via AWS CLI

To immediately bring a service to a specific task count:

```bash
# Scale API to 2 tasks
aws ecs update-service \
  --cluster infra-lab-dev-control \
  --service infra-lab-dev-api \
  --desired-count 2 \
  --profile infra-lab

# Scale worker-nano to 1 task
aws ecs update-service \
  --cluster infra-lab-dev-execution \
  --service infra-lab-dev-worker-nano \
  --desired-count 1 \
  --profile infra-lab

# Scale worker-medium to 1 task
aws ecs update-service \
  --cluster infra-lab-dev-execution \
  --service infra-lab-dev-worker-medium \
  --desired-count 1 \
  --profile infra-lab

# Scale worker-xlarge to 1 task
aws ecs update-service \
  --cluster infra-lab-dev-execution \
  --service infra-lab-dev-worker-xlarge \
  --desired-count 1 \
  --profile infra-lab
```

### Option 3: Terraform Override (Persistent)

To change the baseline for a longer period, update `desired_count` in `infra/live/dev/ecs.tf`
and the corresponding `min_capacity` in `infra/live/dev/autoscaling.tf`, then apply.

Note: The ECS service has `ignore_changes = [desired_count]` in its lifecycle block,
so Terraform won't revert manual CLI changes on the next apply.

## Scaling Back Down

After testing is complete, scale services back to zero:

```bash
# Scale all workers back to 0
for svc in worker-nano worker-medium worker-xlarge; do
  aws ecs update-service \
    --cluster infra-lab-dev-execution \
    --service "infra-lab-dev-${svc}" \
    --desired-count 0 \
    --profile infra-lab
done

# Scale API back to 1 (minimum for health)
aws ecs update-service \
  --cluster infra-lab-dev-control \
  --service infra-lab-dev-api \
  --desired-count 1 \
  --profile infra-lab
```

## Prod Differences

In production (future):

- API min_capacity = 2 (HA across AZs)
- Worker nano/medium min_capacity = 1 (always warm)
- ALB has deletion protection enabled
- WAF associated (CKV2_AWS_28)
- Flow logs and access logs enabled

## Autoscaling Configuration

| Service | Metric | Target | Min | Max |
| --- | --- | --- | --- | --- |
| API | CPU | 70% | 1 | 10 |
| API | Memory | 80% | 1 | 10 |
| worker-nano | CPU | 60% | 0 | 5 |
| worker-medium | CPU | 60% | 0 | 10 |
| worker-xlarge | CPU | 50% | 0 | 5 |

---

## Aurora Database Cost Controls

### Cost Reduction Approach

Aurora Serverless v2 has a minimum of 0.5 ACU (~$44/mo per cluster) that cannot be
reduced. The only way to eliminate idle Aurora cost is to **stop the clusters** when
not actively developing.

RDS Proxy is omitted from dev entirely — it's only needed when ECS tasks run at scale.
The `rds_proxy` module exists for staging/prod use.

### Idle Cost (Clusters Running)

| Resource | Monthly |
| --- | --- |
| Aurora control (0.5 ACU) | ~$44 |
| Aurora execution (0.5 ACU) | ~$44 |
| KMS key (evidence) | ~$1 |
| **Total** | **~$89/mo** |

### Idle Cost (Clusters Stopped)

| Resource | Monthly |
| --- | --- |
| Aurora storage (both clusters) | ~$2-5 |
| KMS key (evidence) | ~$1 |
| **Total** | **~$3-6/mo** |

### Stopping Clusters

Aurora clusters can be stopped for up to 7 days. After 7 days, AWS auto-restarts them.

```bash
# Stop both clusters
aws rds stop-db-cluster \
  --db-cluster-identifier infra-lab-dev-control-db \
  --profile infra-lab

aws rds stop-db-cluster \
  --db-cluster-identifier infra-lab-dev-execution-db \
  --profile infra-lab
```

### Starting Clusters

```bash
# Start both clusters (takes 1-3 minutes)
aws rds start-db-cluster \
  --db-cluster-identifier infra-lab-dev-control-db \
  --profile infra-lab

aws rds start-db-cluster \
  --db-cluster-identifier infra-lab-dev-execution-db \
  --profile infra-lab

# Wait for available status
aws rds wait db-cluster-available \
  --db-cluster-identifier infra-lab-dev-control-db \
  --profile infra-lab
```

### Adding RDS Proxy (When Needed)

RDS Proxy is omitted from dev to save ~$22/mo. When running load tests or deploying
services that need connection pooling, add proxy configuration to `database.tf`:

```hcl
module "rds_proxy_control" {
  source = "../../modules/rds_proxy"

  proxy_name         = "${local.name_prefix}-control-proxy"
  cluster_identifier = module.aurora_control.cluster_id
  subnet_ids         = module.control_vpc.data_subnet_ids
  security_group_ids = [module.sg_rds_control.id]
  secret_arns        = [module.aurora_control.master_user_secret_arn]
  aws_region         = var.aws_region
  tags               = local.common_tags
}
```

Then `terraform apply`. Remove and apply again when done to stop the charges.

### Terraform Compatibility

Stopping/starting Aurora clusters does NOT cause Terraform drift. The cluster state
is not tracked by Terraform — only the configuration is. `terraform plan` will show
no changes on a stopped cluster.
