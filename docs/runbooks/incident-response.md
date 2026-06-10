# Incident Response Runbook

## Severity Levels

| Severity | Definition | Response Time | Examples |
| --- | --- | --- | --- |
| SEV1 | Complete outage, data loss risk | 15 min | DB corruption, security breach, all services down |
| SEV2 | Major degradation, partial outage | 30 min | API 5xx > 50%, queue backlog growing, DB failover |
| SEV3 | Minor impact, workaround available | 2 hours | Single worker tier failing, elevated latency |
| SEV4 | No user impact, hygiene | Next business day | DLQ messages, config drift, certificate expiry warning |

## Alerting Chain

```text
CloudWatch Alarm → SNS Topic → Email (dev)
                            → PagerDuty (prod, future)
                            → Slack channel (future)
```

## Incident Workflow

### 1. Detect

- CloudWatch alarm fires (CPU, 5xx, DLQ, queue depth)
- Cost anomaly alert
- Security Hub finding
- Manual report

### 2. Triage

- Check CloudWatch dashboard: `infra-lab-dev-operations`
- Identify affected service and scope
- Assign severity level

### 3. Investigate

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster infra-lab-dev-control \
  --services infra-lab-dev-api \
  --profile infra-lab

# Check recent deployments
aws deploy list-deployments \
  --application-name infra-lab-dev-api \
  --deployment-group-name infra-lab-dev-api-dg \
  --profile infra-lab

# Check CloudWatch logs
aws logs tail /ecs/infra-lab-dev-control/infra-lab-dev-api \
  --since 30m \
  --profile infra-lab

# Check DLQ messages
aws sqs get-queue-attributes \
  --queue-url <dlq-url> \
  --attribute-names ApproximateNumberOfMessages \
  --profile infra-lab
```

### 4. Mitigate

| Issue | Action |
| --- | --- |
| Bad deployment | CodeDeploy auto-rollback (automatic) or manual stop |
| Service crash loop | Scale to 0, fix, redeploy |
| DB connection exhaustion | Check proxy connections, restart ECS tasks |
| Queue poisoning | Purge DLQ, fix consumer, replay good messages |
| Cost runaway | Stop offending resource, investigate root cause |

### 5. Resolve

- Confirm services healthy via dashboard
- Verify alarms return to OK state
- Document root cause in incident log

### 6. Post-Incident

- Write post-mortem (SEV1/SEV2 only)
- Update runbooks if gap found
- Create preventive automation ticket

## Escalation

| Role | Contact | When |
| --- | --- | --- |
| On-call engineer | (infra-lab single-operator) | All incidents |
| AWS Support | Console or CLI | SEV1 if AWS service issue |

## Common Commands

```bash
# Force new deployment (restarts all tasks)
aws ecs update-service \
  --cluster infra-lab-dev-control \
  --service infra-lab-dev-api \
  --force-new-deployment \
  --profile infra-lab

# Rollback CodeDeploy deployment
aws deploy stop-deployment \
  --deployment-id <id> \
  --auto-rollback-enabled \
  --profile infra-lab

# Drain and replace tasks
aws ecs update-service \
  --cluster infra-lab-dev-control \
  --service infra-lab-dev-api \
  --desired-count 0 \
  --profile infra-lab
# Wait, then scale back up
```
