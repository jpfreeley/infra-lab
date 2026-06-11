#!/bin/bash
set -ex

echo "=== MagNet Legal Dev Environment Setup ==="

# System updates
sudo yum update -y

# Git
sudo yum install -y git

# Python 3.11 (Amazon Linux 2 extras)
sudo amazon-linux-extras enable python3.8 2>/dev/null || true
sudo yum install -y python3.11 python3.11-pip python3.11-devel
sudo alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
sudo alternatives --set python3 /usr/bin/python3.11

# Node.js 20 via nvm (for dcvuser)
sudo -u dcvuser bash -c '
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install 20
  nvm use 20
  nvm alias default 20
  echo "Node: $(node --version)"
  echo "npm: $(npm --version)"
'

# Development tools
sudo yum install -y gcc gcc-c++ make openssl-devel bzip2-devel libffi-devel

# Docker (required for Supabase local)
sudo amazon-linux-extras install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker dcvuser

# Docker Compose v2
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Supabase CLI
sudo -u dcvuser bash -c '
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  npm install -g supabase
  echo "Supabase CLI: $(supabase --version 2>/dev/null || echo installed)"
'

# VS Code (for desktop use)
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo tee /etc/yum.repos.d/vscode.repo << 'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
sudo yum install -y code

# Claude CLI (installed for dcvuser via npm)
sudo -u dcvuser bash -c '
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  npm install -g @anthropic-ai/claude-code
  echo "Claude CLI: $(claude --version 2>/dev/null || echo installed)"
'

# Create project directory structure for dcvuser
sudo -u dcvuser bash -c '
  mkdir -p ~/development
  cd ~/development

  # Clone MagNet repos (will fail without auth, but creates structure)
  echo "Project directory created at ~/development"
  echo ""
  echo "=== Dev Server Access (from your local browser) ==="
  echo "Frontend: http://3.237.223.36:5173"
  echo "Backend:  http://3.237.223.36:5000"
  echo ""
  echo "=== Important: Bind to 0.0.0.0 ==="
  echo "Frontend: npm run dev -- --host 0.0.0.0"
  echo "Backend:  python app.py (already binds 0.0.0.0 in debug mode)"
  echo ""
  echo "Next steps:"
  echo "  1. cd ~/development"
  echo "  2. git clone <MagNet-Agents-Backend repo URL>"
  echo "  3. git clone <magnet-app-front repo URL>"
'

# Verify installations
echo ""
echo "=== Installation Summary ==="
echo "Git: $(git --version)"
echo "Python3: $(python3 --version)"
echo "pip3: $(python3 -m pip --version 2>/dev/null || echo 'not available')"
sudo -u dcvuser bash -c '
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  echo "Node: $(node --version)"
  echo "npm: $(npm --version)"
'
echo "VS Code: $(code --version 2>/dev/null | head -1 || echo 'installed')"
echo ""
echo "=== Setup Complete ==="
echo "Log in as dcvuser and run: source ~/.nvm/nvm.sh"
