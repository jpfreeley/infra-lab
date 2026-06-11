# ADR-031: Dedicated AWS Account for Remote Dev Desktops

## Status

Accepted (revised)

## Context

The platform needs remote graphical desktops for development. Options
evaluated:

| Option | Monthly Cost | Pros | Cons |
| --- | --- | --- | --- |
| AWS WorkSpaces | ~$140 | Managed, simple | Requires directory ($36+), expensive |
| EC2 + NICE DCV (on-demand) | ~$28 | Full control, cheaper | Manual setup |
| EC2 + NICE DCV (spot) | ~$28 | Same as above, spot savings | Can be interrupted |

AWS WorkSpaces requires a directory service ($36/mo minimum) even for a
single desktop. This was deemed excessive for a lab/dev environment.

## Decision

Use a dedicated AWS account (`815802018602`) with EC2 Spot + NICE DCV:

- **Spot instance** (t3.large, 8GB RAM) for cost optimization
- **Persistent EBS volume** (50GB, `/data`) survives spot interruptions
- **Golden AMI** (`ami-0f618edd4b848eb44`) with Docker, Supabase CLI, Git pre-installed
- **Docker-based tooling**: Python 3.11, Node 20, Claude CLI run in containers
  (Amazon Linux 2 host lacks glibc 2.28 for modern Node/VS Code binaries)
- **Supabase local** runs via Docker for full-stack development
- **code-server** provides browser-based VS Code with Node 20 and Claude CLI
- **Service boundary SCP** restricts the account to relevant AWS services only
- Inherits existing OU-level guardrails from the Workloads OU

## Architecture

- Instance in public subnet with IGW (direct internet, no NAT needed)
- Security group restricts inbound to developer's IP only
- DCV streams desktop via port 8443 (HTTPS + QUIC)
- Development ports (5000, 5173, 8080, 54321, 54323) exposed for local browser access
- Docker data-root on persistent volume for image/container survival
- User home symlinked to persistent volume for repo persistence

## Consequences

- Cost ~$28/mo running, ~$10/mo stopped (vs $140/mo for WorkSpaces)
- Spot interruption risk mitigated by persistent EBS + golden AMI (rebuild ~2min)
- Docker adds a layer vs native, but ensures consistency and survives instance replacement
- glibc limitation on Amazon Linux 2 means modern CLIs must run in containers
- Security relies on IP-restricted security group (acceptable for single-user lab)
- Golden AMI must be re-baked when tooling changes
