#!/bin/bash
# Latent — QR studio next to Requestick, the way yourmomon.top is.
# Usage: sudo ./install.sh
#        sudo ./install.sh qr.yourmomon.top
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Need sudo so Docker can be installed. Re-running with sudo..."
  exec sudo -E "$0" "$@"
fi

DOMAIN="${1:-qr.yourmomon.top}"
DOMAIN="$(echo "$DOMAIN" | tr -d '[:space:]')"
if [ -z "$DOMAIN" ]; then
  echo "Usage: sudo ./install.sh qr.yourmomon.top"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)"
fi
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  echo "Missing docker-compose.yml."
  exit 1
fi
cd "$ROOT"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl openssl python3 docker.io docker-compose-v2
systemctl enable --now docker

ENV_FILE="$ROOT/latent.env"
if [ -f "$ENV_FILE" ]; then
  echo "Keeping existing $ENV_FILE."
else
  umask 077
  cat > "$ENV_FILE" <<EOF
LATENT_DOMAIN=${DOMAIN}
LATENT_PORT=3070
EOF
  echo "Wrote $ENV_FILE."
fi

if grep -q '^LATENT_DOMAIN=' "$ENV_FILE"; then
  sed -i "s|^LATENT_DOMAIN=.*|LATENT_DOMAIN=${DOMAIN}|" "$ENV_FILE"
else
  echo "LATENT_DOMAIN=${DOMAIN}" >> "$ENV_FILE"
fi

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
fi

chmod +x "$ROOT/deploy/vps/"*.sh 2>/dev/null || true

if [ -f "$ROOT/latent-image.tar.gz" ]; then
  echo "Loading prebuilt Latent image..."
  docker load -i "$ROOT/latent-image.tar.gz"
fi

if [ -f "$ROOT/VERSION" ] && ! grep -q '^LATENT_VERSION=' "$ENV_FILE"; then
  echo "LATENT_VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")" >> "$ENV_FILE"
fi
if docker image inspect latent:local >/dev/null 2>&1 && ! grep -q '^LATENT_IMAGE=' "$ENV_FILE"; then
  VERSION_TAG="$(grep '^LATENT_VERSION=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)"
  if [ -n "$VERSION_TAG" ] && docker image inspect "latent:${VERSION_TAG}" >/dev/null 2>&1; then
    echo "LATENT_IMAGE=latent:${VERSION_TAG}" >> "$ENV_FILE"
  else
    echo "LATENT_IMAGE=latent:local" >> "$ENV_FILE"
  fi
fi

if [ -x "$ROOT/deploy/vps/start.sh" ]; then
  "$ROOT/deploy/vps/start.sh" "$DOMAIN"
else
  "$ROOT/start.sh" "$DOMAIN"
fi
