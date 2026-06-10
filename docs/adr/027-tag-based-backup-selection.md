# ADR-027: Tag-Based Backup Selection

## Status

Accepted

## Context

AWS Backup can select resources by ARN or by tag. Resources in dev are
frequently stopped/started and may not always be available for backup.

## Decision

Use tag-based backup selection with opt-in:

- Resources tagged `Backup=true` are included in the backup plan
- No backup selection active in dev (clusters frequently stopped)
- Enabled in prod where resources are always running
- Daily (7d retention dev / 35d prod) + Monthly (35d dev / 365d prod)

## Consequences

- No failed backup jobs from stopped Aurora clusters in dev
- Resources opt-in to backup explicitly (no accidental inclusions)
- New resources automatically backed up when tagged appropriately
- Must remember to add `Backup=true` tag when deploying persistent resources
- Dev has Aurora PITR (7-day window) as implicit backup even without AWS Backup
