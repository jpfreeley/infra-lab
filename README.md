# infra-lab

Monorepo with clear boundaries:

- `infra/` — Terraform/IaC (multi-account, multi-environment)
- `app/` — application code
- `docs/` — documentation, ADRs, runbooks
- `scripts/` — automation scripts
- `web/` — Jira-ready agile backlog (HTML)

## AWS Accounts

| Account | ID | Purpose |
| --- | --- | --- |
| Management | `551452024305` | Organizations, Control Tower, state backend |
| Workspaces | `815802018602` | Remote dev desktops (EC2 + NICE DCV) |

## Quick Start — Dev Desktop

The workspaces account provides a remote graphical desktop for development:

```bash
# Get the current IP
cd infra/live/workspaces
terraform output dcv_connect_url
```

Connect via browser, then start the dev stack:

```bash
newgrp docker
supabase start
cd ~/development && docker compose up -d
```

See [docs/runbooks/workspaces-operations.md](docs/runbooks/workspaces-operations.md) for full details.

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Networking CIDR Plan](docs/networking-cidr-plan.md)
- [ADRs](docs/adr/)
- [Runbooks](docs/runbooks/)

More information: [http://ypgmedia.com/infra-lab/](http://ypgmedia.com/infra-lab/)
