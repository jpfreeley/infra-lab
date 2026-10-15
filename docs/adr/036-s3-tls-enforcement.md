# ADR-036: Require HTTPS on Every Managed S3 Bucket

## Status

Accepted

## Context

A review of AWS costs on 2026-10-15 surfaced that the single largest cost
item in the management account wasn't Bedrock or mempalace at all — it was
`jpfbigbox-backup`, a 5.3 TiB / 251,085-object Synology Hyper Backup target
bucket, predating this repo (created 2021), running ~$50/month flat in
One Zone-IA storage. That review also raised a related question: are these
buckets encrypted in transit as well as at rest? At-rest encryption was
confirmed present everywhere (AES256 or KMS), but no bucket had a policy
actually *requiring* HTTPS — S3 allows plain HTTP unless a bucket policy
explicitly denies it, and no client here was known to need that fallback.

## Decision

Two separate, complementary changes:

**1. Storage-class optimization on `jpfbigbox-backup`.** Confirmed via
Synology's own documentation that Hyper Backup supports Standard,
Standard-IA, One Zone-IA, and Intelligent-Tiering as S3 targets, but
explicitly does **not** support Glacier — moving backed-up objects to
Glacier breaks Hyper Backup's retention/consolidation process, which needs
to read back old blocks on demand and can't tolerate a restore-and-wait
delay. Added a lifecycle rule transitioning the bucket to
`INTELLIGENT_TIERING` after 1 day. Its three automatic tiers (Frequent
Access, Infrequent Access, Archive Instant Access) all stay instant-read
with no restore delay, so this is safe for Hyper Backup's access pattern,
unlike Glacier. Expected to cut this bucket's cost from ~$50/month (flat
One Zone-IA) to ~$22/month once cold data settles into Archive Instant
Access ($0.004/GB vs One Zone-IA's flat $0.01/GB), plus a small one-time
transition-request fee (~$2.51 for 251k objects) and an ongoing per-object
monitoring fee (~$0.63/month) — both already netted into the $22 estimate.
This bucket predates Terraform management and isn't managed by it; the
lifecycle rule was applied directly via the AWS CLI.

**2. Require HTTPS (`DenyInsecureTransport`) on every bucket this repo
manages.** Added to the `s3_secure_bucket` module (covering every
environment that uses it: dev/staging/prod flow logs, dev evidence bucket,
dev alpaca-trading bucket), the `mgmt/backend` Terraform state/log
bootstrap buckets, and the mempalace ALB access-log bucket. Every real
client here (Terraform, the AWS CLI, AWS SDKs, AWS service log delivery,
Synology Hyper Backup) already uses HTTPS, so this denies a request
pattern nothing legitimate was sending — it only removes the possibility
of a plain-HTTP request succeeding. Confirmed no affected bucket has
static website hosting configured (the one feature this would break,
since website endpoints need plain HTTP) before applying anything.
Pre-existing, non-Terraform-managed buckets in the management account
(`jpfbigbox-backup`, `kops-state-store-jpf`, `taxi-code`, a `gc-s3-bucket*`
bucket, three `appstream*` buckets, and a legacy `infra-lab-cloudtrail-logs`
bucket) got the same statement applied directly via the AWS CLI, merged
into each bucket's existing policy rather than overwriting it.

**Not applied, by design**: the org's real CloudTrail delivery bucket
(`aws-controltower-logs-172134854767-us-east-1`, log-archive account) is
protected by a Control Tower guardrail SCP that denies `s3:PutBucketPolicy`
on every resource in that account to any principal other than
`AWSControlTowerExecution` — confirmed by reading the SCP directly, not
just from the error message. This blocks every bucket in the log-archive
and security-audit accounts categorically, not just Control-Tower-named
ones. See ADR-006 for the SCP finding itself (a real gap in that ADR's own
documented admin-exemption list). The management account is exempt from
all SCPs (an AWS-wide limitation, also already documented in ADR-006),
which is why every management-account bucket — including the
non-Terraform-managed legacy ones — went through without issue.

**Not applied, nothing to apply**: `prod`/`staging` flow-logs buckets are
commented out (cost optimization, never deployed), and `dev`'s evidence
bucket has a pre-existing, unrelated bug (an invalid KMS alias) blocking it
from ever successfully creating. Both already pick up the module's
`DenyInsecureTransport` policy automatically whenever they're eventually
enabled and applied — no further action needed on this ADR's account when
that happens.

## Consequences

- Every real, reachable bucket in the management and mempalace accounts
  now rejects plain-HTTP requests. Verified live: an authenticated HTTP
  request against a real bucket returned 403; the identical HTTPS request
  succeeded.
- `jpfbigbox-backup`'s expected cost drops roughly in half once cold data
  finishes settling into Archive Instant Access — this takes time (data
  has to go untouched for 90 days to reach that tier), so the savings
  won't be visible in billing immediately.
- `aws_s3_bucket_policy`'s `PutBucketPolicy` call targets the bucket's own
  region, unlike `aws_s3_bucket` itself (whose name is global) — a replica
  bucket in a different region than its stack's default provider needs its
  policy resource split onto that region's provider alias. Found live on
  first apply in `mgmt/backend` (4 replica buckets in us-west-2); fixed by
  splitting into two `aws_s3_bucket_policy` resources, one per provider.
- Any future bucket added via `s3_secure_bucket` inherits HTTPS enforcement
  automatically. Any future bucket added directly (not via the module, not
  via `mgmt/backend`'s pattern) needs its own `DenyInsecureTransport`
  statement — this isn't automatically organization-wide.
- Log-archive and security-audit accounts remain permanently out of reach
  for bucket-policy changes via any normal admin path. This is correct,
  intentional behavior protecting audit/log integrity, not a gap to close.
