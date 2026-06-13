# Developer Onboarding — Remote Dev Desktop

Welcome! This guide walks you through setting up your remote development
desktop from scratch. No prior AWS or Docker experience required.

## What You're Getting

A remote Linux desktop in the cloud with:

- A full graphical desktop you access through your browser (DCV)
- VS Code (native, with Continue AI extension connected to Ollama)
- A browser-based code editor on port 8080 (OpenVSCode Server)
- Python 3.11 for backend development (via Docker)
- Local Supabase database (PostgreSQL + auth + storage + dashboard)
- Shared Ollama GPU server for AI-assisted coding (qwen2.5-coder:14b)
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

## Step 4: Set Up Docker Access

Run this once (needed every time you open a new terminal session):

```bash
newgrp docker
```

Verify it works:

```bash
docker --version
# Should show: Docker version 25.x.x
```

## Step 5: Start Supabase (Local Database)

```bash
supabase start
```

First time takes 3-5 minutes (downloading database images). After that,
it's instant.

When it finishes, you'll see credentials. The important ones:

- **Dashboard**: `http://localhost:54323` (open in Firefox on the desktop)
- **API URL**: `http://localhost:54321`
- **Database**: `postgresql://postgres:postgres@localhost:54322/postgres`

## Step 6: Start the Application

```bash
cd ~/development
docker compose up -d
```

This starts:

- **Backend** (Python/Flask) on port 5000
- **Frontend** (React/Vite) on port 5173
- **OpenVSCode Server** on port 8080

First time takes 2-3 minutes (installing dependencies). After that,
restarts are fast.

Check they're running:

```bash
docker compose ps
```

## Step 7: Access Services

From your local computer's browser:

| Service | URL | Notes |
| --- | --- | --- |
| DCV Desktop | `https://<IP>:8443` | Full Linux desktop |
| Frontend | `http://<IP>:5173` | React app |
| Backend | `http://<IP>:5000/health` | Flask API |
| OpenVSCode Server | `http://<IP>:8080` | Browser code editor (no password) |
| Supabase Studio | `http://<IP>:54323` | Database dashboard |

## AI-Assisted Coding (Continue + Ollama)

Your desktop comes with the **Continue** VS Code extension pre-configured
to use a shared Ollama GPU server running `qwen2.5-coder:14b`.

**What works:**

- **Chat**: Ask questions, get code suggestions, explain code
- **Tab autocomplete**: Ghost text suggestions while you type
- **Code edit**: Select code → Cmd+I → describe changes

**What doesn't work (local model limitation):**

- Agent mode (autonomous coding, running terminal commands)
- MCP tool integration

For agent/MCP features, add a Claude API key to Continue's config
(ask your team lead).

**If Continue isn't responding:** The Ollama server auto-stops after
10 minutes of inactivity. It auto-starts when you launch a desktop,
but takes ~5 minutes to download the model on first boot. Be patient
on the first query.

## Day-to-Day Workflow

### Starting your day

Launch your desktop from the self-service page. If your desktop was
stopped (idle auto-stop after 30 minutes), it restarts in ~2 minutes.
First-time boot takes ~10 minutes.

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

To manually stop:

```bash
cd ~/development && docker compose down
supabase stop
```

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
| Start everything | `newgrp docker && supabase start && cd ~/development && docker compose up -d` |
| Stop everything | `cd ~/development && docker compose down && supabase stop` |
| View backend logs | `cd ~/development && docker compose logs -f backend` |
| View frontend logs | `cd ~/development && docker compose logs -f frontend` |
| Restart backend | `cd ~/development && docker compose restart backend` |
| Restart frontend | `cd ~/development && docker compose restart frontend` |
| Open VS Code | `code ~/development` |
| Test Ollama | `curl http://10.0.96.100:11434/api/tags` |
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
| Continue not responding | Ollama may be starting up — wait 2-3 min, try again |
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
- **Ollama GPU**: g4dn.xlarge (on-demand), Amazon Linux 2023, 10-min idle auto-stop
- **Provisioning**: Lambda + API Gateway, self-service via web page
- **State**: DynamoDB tracks active desktops
- **Networking**: VPC 10.0.96.0/20, desktops in public subnet, SG restricts by IP
- **Ollama IP**: Fixed at 10.0.96.100 (private, within VPC)
- **Idle auto-stop**: Desktop (30 min, DCV + code-server connections), Ollama (10 min, API requests)
- **Persistent storage**: 50GB EBS volume at /data, survives stop/start

## Getting Help

1. Check this doc first
1. Ask in the team chat
1. Reach out to your team lead for infrastructure issues
