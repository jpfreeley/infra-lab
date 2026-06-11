# Developer Onboarding — Remote Dev Desktop

Welcome! This guide walks you through setting up your remote development
desktop from scratch. No prior AWS or Docker experience required.

## What You're Getting

A remote Linux desktop in the cloud with:

- A full graphical desktop you access through your browser
- VS Code (browser-based) with Node.js 20 and Claude AI assistant
- Python 3.11 for backend development (via Docker)
- Local Supabase database (PostgreSQL + auth + storage + dashboard)
- All the MagNet Legal code, ready to run

## Prerequisites

You need:

1. A modern web browser (Chrome, Firefox, or Safari)
1. Your developer IP address (ask your team lead — needed for security)
1. GitHub account with access to the MagNet Legal repos

## Step 1: Get Your Desktop URL

Your team lead will provide you with:

- **Desktop URL**: `https://<IP>:8443`
- **Username**: `dcvuser`
- **Password**: (will be set for you or you'll set it on first login)

## Step 2: Connect to Your Desktop

1. Open your browser and go to `https://<YOUR-IP>:8443`
1. You'll see a security warning about the certificate — this is expected.
   Click "Advanced" → "Proceed" (Chrome) or "Accept the Risk" (Firefox)
1. Enter your username and password
1. You'll see a Linux desktop (MATE) with a taskbar at the top

## Step 3: Open a Terminal

1. Right-click anywhere on the desktop
1. Click "Open Terminal Here"
1. You now have a command-line terminal

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

First time takes 2-3 minutes (installing dependencies). After that,
restarts are fast.

Check they're running:

```bash
docker compose ps
```

You should see `backend` and `frontend` both "Up".

## Step 7: Open the App

From your local computer's browser (not the desktop's browser):

- **Frontend**: `http://<YOUR-DESKTOP-IP>:5173`
- **Backend health check**: `http://<YOUR-DESKTOP-IP>:5000/health`
- **Supabase Studio**: `http://<YOUR-DESKTOP-IP>:54323`

## Step 8: Open VS Code (Browser)

For editing code with a full IDE:

1. Go to `http://<YOUR-DESKTOP-IP>:8080` in your local browser
1. Password: `magnet123`
1. You'll see VS Code with your project files

The VS Code terminal has **Node.js 20** and **Claude CLI** available.

## Day-to-Day Workflow

### Starting your day

```bash
# Open terminal on desktop, then:
newgrp docker
supabase start
cd ~/development && docker compose up -d
```

### Editing code

Option A: Use the browser VS Code at `http://<IP>:8080`
Option B: Use any editor inside the DCV desktop (right-click → Open Terminal)

### Viewing your changes

The frontend has hot-reload — save a file and the browser refreshes
automatically at `http://<IP>:5173`.

### Stopping at end of day

```bash
cd ~/development && docker compose down
supabase stop
```

Your team lead may also stop the instance to save costs. Your files
are safe — they're stored on a separate persistent disk.

### If the desktop won't connect

Your instance may have been stopped (cost savings) or your IP changed.
Contact your team lead to:

- Start the instance back up
- Update the security group with your new IP

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
└── docker-compose.yml         ← Runs backend + frontend
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
| Run a Python command | `docker run --rm -v ~/development/MagNet-Agents-Backend:/app -w /app python:3.11 python <script.py>` |
| Open Supabase dashboard | Browser → `http://localhost:54323` (on desktop) |
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
| Can't connect to desktop | Ask team lead to check instance status + your IP |
| Backend not starting | Check logs: `docker compose logs backend` |
| Frontend npm error | Usually dependency issues — ask team lead |
| "Port in use" error | `docker compose down` then `docker compose up -d` |
| Supabase won't start | `supabase stop` then `supabase start` again |
| Desktop feels slow | Normal for first few minutes. DCV adapts to bandwidth. |
| Lost my changes | They're safe on `/data`. Files survive restarts. |
| Certificate warning | Normal — click through it. It's a self-signed cert. |

## Getting Help

1. Check this doc first
1. Ask in the team chat
1. Reach out to your team lead for infrastructure issues (instance, IP, keys)
