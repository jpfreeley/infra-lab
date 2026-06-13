# DCV Dev Desktop — Operations Runbook

## Overview

The workspaces account (`815802018602`) runs a NICE DCV graphical desktop
on an EC2 Spot instance as a cost-effective remote development environment.
The desktop is pre-configured for MagNet Legal development with Docker-based
tooling and a persistent data volume that survives spot interruptions.

## Architecture

```text
┌─────────────────────────────────────────────────┐
│  EC2 Spot (t3.large, 8GB RAM)                   │
│  AMI: magnetlegal-dev-desktop-v2-20260611          │
│  (ami-0f618edd4b848eb44)                        │
│                                                 │
│  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ DCV Server  │  │ Docker Engine            │  │
│  │ :8443       │  │  - python:3.11 (backend) │  │
│  └─────────────┘  │  - node:20 (frontend)    │  │
│                    │  - supabase (10+ svc)    │  │
│                    │  - code-server (:8080)   │  │
│                    └─────────────────────────┘  │
│                                                 │
│  /data (50GB EBS, persistent)                   │
│    ├── home/dcvuser/development/                │
│    │     ├── MagNet-Agents-Backend/             │
│    │     ├── magnet-app-front/                  │
│    │     └── docker-compose.yml                 │
│    └── docker/data/ (images + volumes)          │
└─────────────────────────────────────────────────┘
```

## Connection Details

| Service | URL | Credentials |
| --- | --- | --- |
| DCV Desktop | `https://<PUBLIC_IP>:8443` | `dcvuser` / (set on first use) |
| code-server (VS Code) | `http://<PUBLIC_IP>:8080` | password: `magnet123` |
| Frontend (Vite) | `http://<PUBLIC_IP>:5173` | — |
| Backend (Flask) | `http://<PUBLIC_IP>:5000` | — |
| Supabase Studio | `http://<PUBLIC_IP>:54323` | (no auth) |
| Supabase API | `http://<PUBLIC_IP>:54321` | — |

Current IP: check with `the API response or AWS console` or:

```bash
aws ec2 describe-instances \
  --instance-ids <YOUR_INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --profile infra-lab
```

## How to Connect

### Browser (DCV Web Client)

1. Open `https://<PUBLIC_IP>:8443`
1. Accept the self-signed certificate warning
1. Log in as `dcvuser`
1. You get a MATE desktop with terminal access

### code-server (Browser VS Code)

1. Open `http://<PUBLIC_IP>:8080`
1. Password: `magnet123`
1. Has Node 20, Claude CLI, full terminal

### SSH (via EC2 Instance Connect)

```bash
# Push your key (valid for 60 seconds)
aws ec2-instance-connect send-ssh-public-key \
  --instance-id <INSTANCE_ID> \
  --instance-os-user ec2-user \
  --ssh-public-key file://~/.ssh/id_ed25519.pub \
  --region us-east-1 \
  --profile infra-lab

# Connect immediately
ssh ec2-user@<PUBLIC_IP>
```

## Starting the Dev Stack

From the DCV terminal:

```bash
# 1. Ensure docker group is active
newgrp docker

# 2. Start Supabase
supabase start

# 3. Start backend + frontend + code-server
cd ~/development
docker compose up -d

# 4. Check status
docker compose ps
```

### Backend only (interactive)

```bash
docker run -it --rm \
  --network host \
  -v ~/development/MagNet-Agents-Backend:/app \
  -w /app \
  --env-file ~/development/MagNet-Agents-Backend/.env \
  python:3.11 bash -c "pip install -r requirements.txt && python app.py"
```

### Frontend only (interactive)

```bash
docker run -it --rm \
  --network host \
  -v ~/development/magnet-app-front:/app \
  -w /app \
  --env-file ~/development/magnet-app-front/.env \
  node:20 bash -c "npm install && npm run dev -- --host 0.0.0.0"
```

## Managing the Instance

### Stop (saves compute cost, data persists)

```bash
aws ec2 stop-instances \
  --instance-ids <INSTANCE_ID> \
  --profile infra-lab
```

### Start

```bash
aws ec2 start-instances \
  --instance-ids <INSTANCE_ID> \
  --profile infra-lab
```

**Note**: Public IP changes after stop/start. Run `terraform refresh` and
check `the API response or AWS console`.

### Reboot

```bash
aws ec2 reboot-instances \
  --instance-ids <INSTANCE_ID> \
  --profile infra-lab
```

## After Instance Replacement (Spot Interruption)

If the spot instance gets reclaimed and a new one starts:

1. The data volume (`/data`) reattaches automatically
1. Repos, Docker images, and compose files persist
1. You need to:
   - Wait for boot (~2 minutes)
   - Get the new public IP (`the API response or AWS console`)
   - Reconnect to DCV
   - Run `newgrp docker` in your terminal
   - Run `supabase start` and `docker compose up -d`

Tools pre-installed on the AMI (survive replacement):

- Docker, Compose, Buildx
- Supabase CLI
- Git
- DCV server

## Updating Your IP

If your public IP changes (new network, VPN):

```bash
cd infra/live/workspaces
terraform apply -var='allowed_ip_cidrs=["YOUR.NEW.IP/32"]'
```

## Supabase Local

### Start Supabase

```bash
newgrp docker
supabase start
```

### Stop

```bash
supabase stop
```

### Reset (wipe all data)

```bash
supabase stop --no-backup
supabase start
```

### Local Supabase Credentials

| Property | Value |
| --- | --- |
| Project URL | `http://127.0.0.1:54321` |
| Database | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| Studio | `http://<PUBLIC_IP>:54323` |
| Publishable key | (shown in `supabase start` output) |
| Secret key | (shown in `supabase start` output) |

## Golden AMI

| Property | Value |
| --- | --- |
| AMI ID | `ami-0f618edd4b848eb44` |
| Name | `magnetlegal-dev-desktop-v2-20260611` |
| Base | DCV Amazon Linux 2 |
| Includes | Docker 25, Compose v5.1, Buildx v0.21, Supabase CLI 2.105, Git 2.47 |
| Does NOT include | Repos, API keys, SSH keys, Docker images |

To launch a new desktop from this AMI, update the `data.aws_ami` in
`dcv_instance.tf` to reference `ami-0f618edd4b848eb44` directly, or
create a new Terraform root with a fresh data volume.

## Scaling to Multiple Developers

**Not yet implemented** — planned approach for provisioning multiple desktops:

- Add a `developers` variable (map of name → IP + password)
- Use `for_each` to create per-developer: spot instance, 50GB data volume, volume attachment
- Shared security group with all developer IPs, or per-developer SGs
- Each dev gets their own isolated instance + data from the same golden AMI
- Estimated cost: ~$28/mo per developer running, ~$10/mo stopped
- User data handles: dcvuser creation, password, docker group, DCV session

```hcl
# Example (not yet implemented):
variable "developers" {
  type = map(object({
    ip       = string
    password = string
  }))
  default = {
    alice = { ip = "1.2.3.4/32", password = "AliceFirst123!" }
    bob   = { ip = "5.6.7.8/32", password = "BobFirst123!" }
  }
}
```

## Cost Breakdown

| Component | Running | Stopped |
| --- | --- | --- |
| EC2 t3.large spot | ~$18/mo | $0 |
| EBS 50GB data vol | ~$4/mo | ~$4/mo |
| EBS 30GB root vol | ~$2.40/mo | ~$2.40/mo |
| Public IPv4 | ~$3.60/mo | ~$3.60/mo |
| **Total** | **~$28/mo** | **~$10/mo** |

**Tip**: Stop the instance when not using it.

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Can't reach DCV (TLS handshake) | Instance OOM'd — reboot or check `free -h` |
| "No session available" | SSH in, run `sudo dcv create-session --owner dcvuser --type virtual console` |
| Docker permission denied | Run `newgrp docker` in your terminal |
| Supabase services stopped | Run `supabase stop && supabase start` |
| Python not found | Use Docker: `docker run --rm -it --network host -v ...:/app python:3.11 bash` |
| Node not found | Use code-server terminal (port 8080) or Docker |
| Public IP changed | `the API response or AWS console` or check EC2 console |
| Instance replaced (spot) | Data persists on /data — get new IP and reconnect |
| DCV license "unlicensed" | Instance role needs S3 read to `dcv-license.us-east-1` bucket |
