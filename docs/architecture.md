# Architecture Overview

This document describes the high-level architecture of the `infra-lab` project.

## Components

- **Infra**: Terraform-managed AWS resources.
- **App**: Containerized application code.
- **Docs**: Project documentation and diagrams.

## Accounts

| Account | ID | Purpose |
| --- | --- | --- |
| Management | `551452024305` | AWS Organizations, Control Tower, SCPs |
| Workspaces | `815802018602` | Remote dev desktops (EC2 + NICE DCV) |

## Dev Desktop (Workspaces Account)

The workspaces account hosts EC2 Spot instances running NICE DCV for remote
graphical development. Key characteristics:

- Golden AMI (`ami-0f618edd4b848eb44`) with Docker, Supabase CLI, Git
- Persistent 50GB EBS data volume for repos, Docker images, and user state
- Docker-based dev stack: Python 3.11, Node 20, code-server, Supabase local
- Spot instance (t3.large) for cost optimization (~$28/mo vs $140/mo for WorkSpaces)
- Service boundary SCP restricts allowed AWS services
