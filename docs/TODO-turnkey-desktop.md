# TODO: Turnkey Desktop — Items Needed From You

## Goal

Make the self-service desktop fully turnkey: a new developer launches via
the web page and within 5 minutes has ALL endpoints working (DCV, code-server,
frontend, backend, Supabase) without running any commands.

## What I Need From You

### 1. GitHub Personal Access Token (PAT)

Create a fine-grained PAT at: [github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta)

Settings:

- **Token name**: `infra-lab-desktop-provisioner`
- **Expiration**: 90 days (or custom)
- **Repository access**: Only select repositories → pick both MagNet repos
- **Permissions**: Contents → Read-only

Once created, give me the token value (starts with `github_pat_...`).
I'll store it in AWS Secrets Manager — never in source code.

### 2. GitHub Repo URLs

Provide the full org/repo paths for both repositories:

- Backend: `github.com/<org>/MagNet-Agents-Backend`
- Frontend: `github.com/<org>/magnet-app-front`

### 3. API Keys

| Key | Where to get | Format |
| --- | --- | --- |
| `OPENAI_API_KEY` | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) | `sk-...` |
| `TAVILY_API_KEY` | [tavily.com](https://app.tavily.com) | `tvly-...` |
| `APIFY_API_TOKEN` | [console.apify.com/account/integrations](https://console.apify.com/account/integrations) | `apify_api_...` |

Optional (can add later):

| Key | Purpose |
| --- | --- |
| `APOLLO_CLIENT_ID` | Apollo.io OAuth |
| `APOLLO_CLIENT_SECRET` | Apollo.io OAuth |
| `VITE_MICROSOFT_CLIENT_ID` | Microsoft Graph email integration |

### 4. Supabase JWT Secret (optional)

If you want the backend to verify Supabase auth tokens locally, provide
the JWT secret from your Supabase project (Dashboard → Settings → API).
Otherwise the local Supabase default will be used.

## What Happens Next (Once You Provide The Above)

1. I store all secrets in AWS Secrets Manager in account `815802018602`
2. I update the Lambda user_data to:
   - Fetch secrets from Secrets Manager at boot
   - Clone both repos via HTTPS + PAT
   - Create `.env` files with real API keys
   - Create `docker-compose.yml`
   - Pull Docker images (`python:3.11-slim`, `node:20-slim`)
   - Start Supabase
   - Start `docker compose up -d`
3. New desktop launches → ~5 min later ALL endpoints are live
4. Developer connects to DCV, opens browser, starts coding

## Current State

| What | Status |
| --- | --- |
| AWS account (815802018602) | ✅ Provisioned |
| VPC + networking | ✅ Deployed |
| Self-service API | ✅ Working ([endpoint](https://i50blnf638.execute-api.us-east-1.amazonaws.com/v1/desktops)) |
| Web launcher | ✅ Live at ypgmedia.com/magleg/dev-desktop.html |
| Golden AMI (v2) | ✅ `ami-0f618edd4b848eb44` |
| DCV + Docker + tools | ✅ Auto-install via user_data |
| Auto-start (returning users) | ✅ docker compose + supabase start on boot |
| Turnkey first boot | ⏳ Blocked on items above |

## Security Notes

- PAT stored in Secrets Manager (encrypted at rest with AWS-managed KMS)
- API keys stored in Secrets Manager (same)
- Instance IAM role will need `secretsmanager:GetSecretValue` permission (I'll add this)
- PAT is read-only — cannot push code, only clone
- Secrets are fetched at boot time, written to `.env` on the data volume
- `.env` files are never committed to git (in `.gitignore`)
