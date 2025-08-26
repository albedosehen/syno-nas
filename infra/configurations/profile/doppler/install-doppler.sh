#!/bin/sh
# doppler-install.sh — Install the latest Doppler CLI from GitHub releases.
#
# Linux:
# chmod +x doppler-install.sh
#
# Usage:
#   sh doppler-install.sh [--bin-dir /path/to/bin]
# Examples:
#   sh doppler-install.sh
#   sh doppler-install.sh --bin-dir /usr/bin
#   sudo sh ./doppler-install.sh

set -eu

BIN_DIR="/usr/local/bin"
# Simple args
while [ "${1-}" ]; do
  case "$1" in
    --bin-dir) BIN_DIR="${2:?}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--bin-dir /path/to/bin]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }

need awk
need tar
# Need one of curl or wget
if command -v curl >/dev/null 2>&1; then
  FETCH="curl -fsSL"
  FETCH_HEAD="curl -fsIL"
elif command -v wget >/dev/null 2>&1; then
  FETCH="wget -qO-"
  FETCH_HEAD="wget -qS --spider"
else
  echo "Missing dependency: curl or wget" >&2
  exit 1
fi

arch="$(uname -m 2>/dev/null || echo unknown)"
case "$arch" in
  x86_64|amd64) GOARCH="amd64" ;;
  aarch64|arm64) GOARCH="arm64" ;;
  armv7l|armhf)  GOARCH="armv7" ;;
  *)
    echo "Unsupported arch: $arch" >&2
    exit 1
    ;;
esac

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Get latest tag (API first; fallback to releases/latest redirect)
get_latest_tag_api() {
  $FETCH https://api.github.com/repos/DopplerHQ/cli/releases/latest \
  | awk -F'"' '/"tag_name":/{print $4; exit}'
}
get_latest_tag_fallback() {
  # Follow redirects and print final URL (works with curl and wget)
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/DopplerHQ/cli/releases/latest
  else
    wget -qO /dev/null --server-response https://github.com/DopplerHQ/cli/releases/latest 2>&1 \
      | awk '/^  Location: /{u=$2} END{print u}'
  fi | awk -F'/download/' '{print $1}' | awk -F'/tag/' '{print $NF}'
}

TAG="$(get_latest_tag_api || true)"
[ -n "${TAG:-}" ] || TAG="$(get_latest_tag_fallback || true)"
if [ -z "${TAG:-}" ]; then
  echo "Failed to determine latest release tag." >&2
  exit 1
fi

ASSET="doppler_${TAG}_linux_${GOARCH}.tar.gz"
URL="https://github.com/DopplerHQ/cli/releases/download/${TAG}/${ASSET}"
TGZ="$tmp/doppler.tgz"

echo "Downloading: $URL"
# Save to file rather than piping to keep BusyBox happy
if command -v curl >/dev/null 2>&1; then
  curl -fL "$URL" -o "$TGZ"
else
  wget -q "$URL" -O "$TGZ"
fi

# Find the doppler binary path within the archive
BIN_PATH="$(tar -tzf "$TGZ" | awk '/(^|\/)doppler$/{print; exit}')"
if [ -z "$BIN_PATH" ]; then
  echo "doppler binary not found in archive; first few entries:" >&2
  tar -tzf "$TGZ" | sed -n '1,50p' >&2
  exit 1
fi

tar -xzf "$TGZ" -C "$tmp" "$BIN_PATH"

# Install
mkdir -p "$BIN_DIR"
cp "$tmp/$BIN_PATH" "$BIN_DIR/doppler"
chmod 0755 "$BIN_DIR/doppler"

# Best-effort link into /usr/bin if doppler not already resolvable
if ! command -v doppler >/dev/null 2>&1; then
  if [ -d /usr/bin ] && [ "$BIN_DIR/doppler" != "/usr/bin/doppler" ]; then
    ln -sf "$BIN_DIR/doppler" /usr/bin/doppler 2>/dev/null || true
  fi
fi

echo "Installed to: $BIN_DIR/doppler"
echo "Version:"
"$BIN_DIR/doppler" --version || { echo "Installed, but not on PATH. Call it via: $BIN_DIR/doppler"; exit 0; }
