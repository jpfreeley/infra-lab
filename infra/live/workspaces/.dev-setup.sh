#!/bin/bash
# =============================================================================
# MagNet Legal Dev Desktop — Post-Boot Setup Script
# =============================================================================
# This script is a REFERENCE for what's needed to turn a bare DCV AMI
# (DCV-AmazonLinux2-x86_64) into a working dev desktop.
#
# In practice, the Terraform user_data in dcv_instance.tf handles the core
# setup automatically on boot. This script adds the project-level setup
# (docker-compose, .env files) that goes on the persistent data volume.
#
# Run as dcvuser AFTER the instance has booted and user_data has completed.
# =============================================================================
set -ex

echo "=== MagNet Legal Dev Desktop Setup ==="

# Verify prerequisites (installed by user_data)
command -v docker || { echo "ERROR: Docker not installed"; exit 1; }
command -v git || { echo "ERROR: Git not installed"; exit 1; }
command -v supabase || { echo "ERROR: Supabase CLI not installed"; exit 1; }

# Ensure docker group is active
newgrp docker << 'SETUP'

cd ~/development

# Clone repos if not present
if [ ! -d "MagNet-Agents-Backend" ]; then
  echo "Clone MagNet-Agents-Backend manually:"
  echo "  git clone git@github.com:<org>/MagNet-Agents-Backend.git"
fi

if [ ! -d "magnet-app-front" ]; then
  echo "Clone magnet-app-front manually:"
  echo "  git clone git@github.com:<org>/magnet-app-front.git"
fi

# Create docker-compose.yml if not present
if [ ! -f "docker-compose.yml" ]; then
  cat > docker-compose.yml << 'COMPOSE'
services:
  backend:
    image: python:3.11-slim
    working_dir: /app
    volumes:
      - ./MagNet-Agents-Backend:/app
    env_file:
      - ./MagNet-Agents-Backend/.env
    network_mode: host
    command: bash -c "pip install -r requirements.txt && python app.py"
    restart: unless-stopped

  frontend:
    image: node:20-slim
    working_dir: /app
    volumes:
      - ./magnet-app-front:/app
      - frontend-node-modules:/app/node_modules
    network_mode: host
    env_file:
      - ./magnet-app-front/.env
    command: bash -c "npm install --legacy-peer-deps && npm run dev -- --host 0.0.0.0"
    restart: unless-stopped

  code-server:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "8080:8080"
    volumes:
      - .:/workspace
    environment:
      - PASSWORD=magnet123
    restart: unless-stopped

volumes:
  frontend-node-modules:
COMPOSE
  echo "docker-compose.yml created"
fi

# Create Dockerfile.dev for code-server if not present
if [ ! -f "Dockerfile.dev" ]; then
  cat > Dockerfile.dev << 'DOCKERFILE'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl wget git sudo build-essential \
    python3.11 python3.11-venv python3.11-dev python3-pip \
    software-properties-common ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

ENV NVM_DIR=/usr/local/nvm
RUN mkdir -p $NVM_DIR && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
    && . $NVM_DIR/nvm.sh && nvm install 20 && nvm alias default 20
ENV PATH=$NVM_DIR/versions/node/v20.20.2/bin:$PATH

RUN npm install -g @anthropic-ai/claude-code \
    && curl -sSL https://github.com/supabase/cli/releases/latest/download/supabase_linux_amd64.tar.gz | tar xz -C /usr/local/bin supabase

RUN curl -fsSL https://code-server.dev/install.sh | sh

RUN useradd -m -s /bin/bash dev && echo "dev:dev" | chpasswd && adduser dev sudo
USER dev
WORKDIR /workspace

EXPOSE 8080 5000 5173

CMD ["code-server", "--bind-addr", "0.0.0.0:8080", "--auth", "password", "/workspace"]
DOCKERFILE
  echo "Dockerfile.dev created"
fi

# Create backend .env template if not present
if [ -d "MagNet-Agents-Backend" ] && [ ! -f "MagNet-Agents-Backend/.env" ]; then
  cat > MagNet-Agents-Backend/.env << 'ENV'
# === MagNet Backend .env ===
# Local Supabase (run 'supabase start' to get actual keys)
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_KEY=REPLACE_WITH_SECRET_KEY_FROM_SUPABASE_START
SUPABASE_JWT_SECRET=super-secret-jwt-token-with-at-least-32-characters-long

# API Keys — REPLACE THESE WITH YOUR REAL KEYS
OPENAI_API_KEY=sk-REPLACE_ME
TAVILY_API_KEY=tvly-REPLACE_ME
APIFY_API_TOKEN=apify_api_REPLACE_ME

# Flask
DEBUG=True
FLASK_DEBUG=1

# Optional
APOLLO_CLIENT_ID=
APOLLO_CLIENT_SECRET=
NY_TOKEN=
ENV
  echo "Backend .env template created — fill in your API keys!"
fi

# Create frontend .env template if not present
if [ -d "magnet-app-front" ] && [ ! -f "magnet-app-front/.env" ]; then
  cat > magnet-app-front/.env << 'ENV'
# === MagNet Frontend .env ===
# Local Supabase (run 'supabase start' to get actual keys)
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_ANON_KEY=REPLACE_WITH_PUBLISHABLE_KEY_FROM_SUPABASE_START

# Microsoft Graph (optional — email integration)
VITE_MICROSOFT_CLIENT_ID=REPLACE_ME
VITE_MICROSOFT_TENANT_ID=common
VITE_MICROSOFT_REDIRECT_URI=http://INSTANCE_IP:5173/contact

# Apollo.io (optional)
VITE_APOLLO_CLIENT_ID=
VITE_APOLLO_CLIENT_SECRET=

# API Base URL — point at local backend
VITE_API_BASE_URL=http://INSTANCE_IP:5000
ENV
  echo "Frontend .env template created — update INSTANCE_IP and Supabase keys!"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Clone your repos (if not done):"
echo "     git clone git@github.com:<org>/MagNet-Agents-Backend.git"
echo "     git clone git@github.com:<org>/magnet-app-front.git"
echo "  2. Fill in API keys in MagNet-Agents-Backend/.env"
echo "  3. Run: supabase start"
echo "  4. Copy Supabase keys from output into .env files"
echo "  5. Run: docker compose up -d"
echo ""
echo "Access from your local browser:"
echo "  Frontend:       http://INSTANCE_IP:5173"
echo "  Backend:        http://INSTANCE_IP:5000"
echo "  Supabase Studio: http://INSTANCE_IP:54323"
echo "  code-server:    http://INSTANCE_IP:8080 (password: magnet123)"
echo ""
SETUP
