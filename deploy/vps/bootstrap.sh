#!/bin/bash
# Latent. One command. No questions. No git. No compile if the image is published.
#   sudo bash /tmp/latent-install.sh
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS SSH_ASKPASS || true

if [ "$(id -u)" -ne 0 ]; then
  echo "Need sudo. Re-running with sudo..."
  exec sudo -E "$0" "$@"
fi

DOMAIN="${1:-qr.yourmomon.top}"
ROOT=/opt/latent
SRC_URL="https://codeload.github.com/dozer54321/latent/tar.gz/refs/heads/main"
IMG_URL="https://github.com/dozer54321/latent/releases/download/rolling/latent-image.tar.gz"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl

tmp="$(mktemp)"
stage="$(mktemp -d)"
keep="$(mktemp -d)"
cleanup() { rm -rf "$tmp" "$stage" "$keep"; }
trap cleanup EXIT

echo "Downloading Latent."
curl -fsSL --retry 3 --retry-delay 2 -A "Latent-install/1.0" -o "$tmp" "$SRC_URL"
tar -xzf "$tmp" -C "$stage"
src="$(find "$stage" -mindepth 1 -maxdepth 1 -type d | head -n1)"
if [ -z "$src" ] || [ ! -f "$src/docker-compose.yml" ]; then
  echo "The download did not contain Latent."
  exit 1
fi

mkdir -p "$ROOT"
for f in latent.env docker-compose.override.yml .autoupdate-rev; do
  if [ -f "$ROOT/$f" ]; then
    cp -a "$ROOT/$f" "$keep/"
  fi
done
cp -a "$src/." "$ROOT/"
for f in latent.env docker-compose.override.yml .autoupdate-rev; do
  if [ -f "$keep/$f" ]; then
    cp -a "$keep/$f" "$ROOT/$f"
  fi
done

echo "Downloading the prebuilt app (no compile)."
if curl -fL --retry 3 --retry-delay 2 -A "Latent-install/1.0" -o "$ROOT/latent-image.tar.gz" "$IMG_URL"; then
  echo "Got the prebuilt image."
else
  rm -f "$ROOT/latent-image.tar.gz"
  echo "No prebuilt image yet. This machine will build it. The yellow text is normal."
fi

chmod +x "$ROOT/deploy/vps/"*.sh
"$ROOT/deploy/vps/install.sh" "$DOMAIN"
