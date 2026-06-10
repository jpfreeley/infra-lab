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
