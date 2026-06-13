# Developer Onboarding — Remote Dev Desktop

Welcome! This guide walks you through setting up your remote development
desktop from scratch. No prior AWS or Docker experience required.

## What You're Getting

A remote Linux desktop in the cloud with:

- A full graphical desktop you access through your browser (DCV)
- VS Code (native, with Continue AI extension — bring your own Claude key)
- A browser-based code editor on port 8080 (OpenVSCode Server)
- Python 3.11 for backend development (via Docker)
- Local Supabase database (PostgreSQL + auth + storage + dashboard)
- All the MagNet Legal code, ready to run

## Prerequisites

You need:

1. A modern web browser (Chrome or Firefox)
1. Your developer username (alphanumeric, e.g. `alice`)
1. The API key (ask your team lead)
1. GitHub account with access to the MagNet Legal repos

## Step 1: Launch Your Desktop

1. Go to the self-service page (ask your team lead for the URL)
1. Enter your username and API key
1. Click "Launch Desktop"
1. Wait for the services to come online (~10 minutes on first boot)

The page shows a countdown and green checkmarks as services become ready.

## Step 2: Connect to Your Desktop (DCV)

1. Click the DCV Desktop link shown on the page: `https://<IP>:8443`
1. You'll see a security warning about the certificate — this is expected.
   Click "Advanced" → "Proceed" (Chrome) or "Accept the Risk" (Firefox)
1. Enter credentials:
   - **Username**: `dcvuser`
   - **Password**: `ChangeMeOnFirstLogin!` (first time — change it immediately)
1. You'll see a Linux desktop (MATE) with a taskbar at the top

## Step 3: Open VS Code

VS Code 1.85 is pre-installed on the desktop with the **Continue** AI extension.

1. Right-click the desktop → "Open Terminal Here"
1. Run: `code ~/development`
1. VS Code opens with your project files
1. The Continue extension (sidebar icon) provides AI chat and autocomplete
   powered by the shared Ollama server

## Step 4: Everything is Already Running

The boot script automatically starts all services:

- Docker + `docker compose up -d` (backend, frontend, OpenVSCode Server)
- Supabase (PostgreSQL, auth, storage, dashboard)
- DCV session

No manual commands needed. Just wait for the self-service page checkmarks
to turn green (~10 minutes on first boot, ~2 minutes on restart).

Verify from a terminal on the desktop:

```bash
docker compose ps
```

You should see all containers running.

## Step 5: Access Services

From your local computer's browser:

| Service | URL | Notes |
| --- | --- | --- |
| DCV Desktop | `https://<IP>:8443` | Full Linux desktop |
| Frontend | `http://<IP>:5173` | React app |
| Backend | `http://<IP>:5000/health` | Flask API |
| OpenVSCode Server | `http://<IP>:8080` | Browser code editor (no password) |
| Supabase Studio | `http://<IP>:54323` | Database dashboard |

## AI-Assisted Coding (Continue + Bring Your Own Key)

Your desktop comes with the **Continue** VS Code extension pre-installed.
To use AI features, bring your own Anthropic (Claude) API key.

**Setup (one time):**

1. Open VS Code on the DCV desktop
1. Open Continue settings: click the gear icon in the Continue sidebar
1. Add your Anthropic API key when prompted
1. Select Claude Sonnet as your model

**What you get with Claude:**

- **Chat**: Ask questions, get code suggestions, explain code
- **Tab autocomplete**: Ghost text suggestions while you type
- **Code edit**: Select code → Cmd+I → describe changes
- **Agent mode**: Autonomous coding, terminal commands, file edits
- **MCP**: Tool server integration

**Note about Ollama (GPU server):**

The infrastructure includes a shared Ollama GPU server (g4dn.xlarge) defined
in Terraform, but it is currently **disabled** (not auto-started). It exists
for future use if you want local/free LLM inference. Contact your team lead
if you want to explore this option.

## Day-to-Day Workflow

### Starting your day

Launch your desktop from the self-service page. Everything starts
automatically — just wait for the checkmarks to go green.

### Editing code

- **Option A (recommended)**: VS Code on the DCV desktop (`code ~/development`)
- **Option B**: OpenVSCode Server at `http://<IP>:8080`
- **Option C**: Any terminal editor on the desktop

### Viewing your changes

The frontend has hot-reload — save a file and the browser refreshes
automatically at `http://<IP>:5173`.

### End of day

Your desktop automatically stops after 30 minutes of inactivity (no DCV
or code-server connections). No action needed — your files are safe on
a persistent disk.

### If the desktop won't connect

- Your instance may have been stopped (auto idle-stop). Relaunch from the
  self-service page.
- Your IP may have changed. The self-service page automatically updates
  the security group with your current IP on each launch.

## Project Structure

```text
~/development/
├── MagNet-Agents-Backend/     ← Python backend (Flask)
│   ├── app.py                 ← Main app file
│   ├── routes.py              ← API endpoints
│   ├── services/              ← Business logic
│   ├── requirements.txt       ← Python dependencies
│   └── .env                   ← API keys (secret!)
│
├── magnet-app-front/          ← React frontend
│   ├── src/                   ← Source code
│   ├── package.json           ← Node dependencies
│   └── .env                   ← Frontend config
│
└── docker-compose.yml         ← Runs backend + frontend + code editor
```

## Useful Commands

| What | Command |
| --- | --- |
| Check running services | `docker compose ps` |
| View backend logs | `cd ~/development && docker compose logs -f backend` |
| View frontend logs | `cd ~/development && docker compose logs -f frontend` |
| Restart backend | `cd ~/development && docker compose restart backend` |
| Restart frontend | `cd ~/development && docker compose restart frontend` |
| Open VS Code | `code ~/development` |
| Check Docker containers | `docker ps` |
| Check disk space | `df -h` |

## API Keys

The `.env` files contain API keys. **Never commit these to git.**

If you need to add or change API keys, edit:

```bash
# Backend keys
vi ~/development/MagNet-Agents-Backend/.env

# Frontend keys
vi ~/development/magnet-app-front/.env
```

Ask your team lead for the actual key values.

## Troubleshooting

| Problem | Solution |
| --- | --- |
| "Permission denied" on docker | Run `newgrp docker` first |
| Can't connect to desktop | Relaunch from self-service page |
| Backend not starting | Check logs: `docker compose logs backend` |
| Frontend npm error | Usually dependency issues — ask team lead |
| "Port in use" error | `docker compose down` then `docker compose up -d` |
| Supabase won't start | `supabase stop` then `supabase start` again |
| Desktop feels slow | Normal for first few minutes. DCV adapts to bandwidth |
| Lost my changes | They're safe on `/data`. Files survive restarts |
| Certificate warning | Normal — click through it. Self-signed cert |
| VS Code says "can't find code" | Run `export PATH=$PATH:/usr/bin` then `code` |

## Architecture (for team leads)

- **Desktop instance**: t3.large, Amazon Linux 2, DCV AMI
- **Ollama GPU** (dormant): g4dn.xlarge defined in Terraform but not auto-started.
  Available for future local LLM use if needed.
- **Provisioning**: Lambda + API Gateway, self-service via web page
- **State**: DynamoDB tracks active desktops
- **Networking**: VPC 10.0.96.0/20, desktops in public subnet, SG restricts by IP
- **LLM**: Bring-your-own Anthropic API key (Continue extension)
- **Idle auto-stop**: Desktop (30 min, DCV + code-server connections)
- **Persistent storage**: 50GB EBS volume at /data, survives stop/start

## Getting Help

1. Check this doc first
1. Ask in the team chat
1. Reach out to your team lead for infrastructure issues
