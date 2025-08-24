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

echo "[*] Installing useful tools (jq, git, ripgrep, htop, tmux)..."
opkg install jq git ripgrep htop tmux ca-bundle git-http

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
