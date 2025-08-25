#!/bin/sh
# setup-entware.sh
# Bootstrap Entware (opkg) on Synology DSM 7.2+

set -e

echo "[*] Checking if running as root..."
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Must run as root (use sudo -i)."
  exit 1
fi

echo "[*] Backing up any existing /opt..."
if [ -d /opt ]; then
  mv /opt "/opt.broken.$(date +%Y%m%d%H%M%S)"
fi

echo "[*] Installing Entware..."
wget -O - http://bin.entware.net/x64-k3.2/installer/generic.sh | sh

echo "[*] Ensuring /opt is in PATH..."
for f in /etc/profile /root/.profile "/var/services/homes/${SUDO_USER:-$(logname)}/.profile"; do
  if [ -f "$f" ]; then
    if ! grep -q '/opt/bin' "$f"; then
      echo 'export PATH=/opt/bin:/opt/sbin:$PATH' >> "$f"
      echo "    Added PATH to $f"
    fi
  fi
done
export PATH=/opt/bin:/opt/sbin:$PATH

echo "[*] Updating package lists..."
opkg update

echo "[*] Installing useful tools (jq, git, zsh, ripgrep, tree, eza, curl, htop, tmux)..."
opkg install jq git git-http zsh ripgrep tree eza curl htop tmux ca-bundle

echo "[*] Installing GitHub CLI..."
# Detect architecture for GitHub CLI
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) GH_ARCH="amd64" ;;
  aarch64) GH_ARCH="arm64" ;;
  armv7l) GH_ARCH="armv6" ;;
  *)
    echo "    Unsupported architecture for GitHub CLI: $ARCH. Skipping."
    GH_ARCH=""
    ;;
esac

if [ -n "$GH_ARCH" ]; then
  echo "    Fetching latest GitHub CLI version..."
  GH_VERSION=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name"' | cut -d '"' -f 4 | sed 's/^v//')
  if [ -n "$GH_VERSION" ]; then
    echo "    Downloading GitHub CLI v$GH_VERSION for $GH_ARCH..."
    wget -O /tmp/gh.tar.gz "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz"
    cd /tmp
    tar -xzf gh.tar.gz
    cp "gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /opt/bin/
    chmod 755 /opt/bin/gh
    rm -rf /tmp/gh.tar.gz "gh_${GH_VERSION}_linux_${GH_ARCH}"
    echo "    GitHub CLI installed successfully."
  else
    echo "    Failed to fetch GitHub CLI version. Skipping."
  fi
fi

echo "[*] Creating DSM Task Scheduler entry for auto-start..."
TASK_NAME="Entware Startup"
if synoschedtask --enum all | grep -q "$TASK_NAME"; then
  echo "    Task already exists."
else
  synoschedtask --add bootup "$TASK_NAME" root "/opt/etc/init.d/rc.unslung start"
  echo "    Task added."
fi

echo "[*] Done. Verify with:"
echo "    jq --version"
echo "    git --version"
echo "    rg --version"
echo "    tree --version"
echo "    eza --version"
if [ -x "/opt/bin/gh" ]; then
  echo "    gh --version"
fi
