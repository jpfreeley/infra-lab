# infra

Infrastructure as Code (Terraform) lives here.

## Structure

```text
infra/
├── live/              # Environment roots (per-account deployments)
│   ├── dev/           # Dev application environment
│   ├── staging/       # Staging application environment
│   ├── prod/          # Production application environment
│   ├── shared/        # Shared/cross-env resources
│   └── workspaces/   # Remote dev desktop (EC2 + DCV, account 815802018602)
├── mgmt/              # Management account resources
│   ├── backend/       # Terraform state S3 + DynamoDB
│   └── org/           # AWS Organizations, OUs, SCPs, accounts
├── modules/           # Reusable Terraform modules
├── policy/            # Policy-as-code
└── test/              # Infrastructure tests
```

## Live Roots

| Root | Account | Purpose |
| --- | --- | --- |
| `live/dev` | 551452024305 | Dev application workloads |
| `live/staging` | 551452024305 | Staging application workloads |
| `live/prod` | 551452024305 | Production application workloads |
| `live/shared` | 551452024305 | Cross-environment shared resources |
| `live/workspaces` | 815802018602 | Remote dev desktops (EC2 Spot + NICE DCV) |

## Boundaries

- Terraform roots/modules go here.
- App code must not be placed in /infra.

## Ownership

See CODEOWNERS.
