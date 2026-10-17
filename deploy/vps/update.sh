#!/bin/bash
# Swap in the public image when a push to main publishes one.
# Never uses git. Never asks for a GitHub username or token.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS SSH_ASKPASS || true

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)"
fi
cd "$ROOT"

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
REV_URL="https://github.com/dozer54321/latent/releases/download/rolling/REVISION"
IMG_URL="https://github.com/dozer54321/latent/releases/download/rolling/latent-image.tar.gz"
STATE="$ROOT/.autoupdate-rev"

install_timer() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Need root to install the auto-update timer."
    echo "  sudo $SELF --install-timer"
    exit 1
  fi
  chmod +x "$SELF"
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "No systemd here. Check for a new image from cron instead:"
    echo "  */2 * * * * $SELF"
    exit 0
  fi
  cat > /etc/systemd/system/latent-update.service <<EOF
[Unit]
Description=Latent — load the public image when main publishes one
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=GIT_TERMINAL_PROMPT=0
WorkingDirectory=${ROOT}
ExecStart=${SELF}
EOF
  cat > /etc/systemd/system/latent-update.timer <<EOF
[Unit]
Description=Check for a new Latent image

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
AccuracySec=15s
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now latent-update.timer
  echo "Auto-update is on. A push to main is live within about 2 minutes."
  echo "No GitHub login on this machine."
  echo "  systemctl status latent-update.timer"
  echo "  journalctl -u latent-update.service -n 40 --no-pager"
}

if [ "${1:-}" = "--install-timer" ]; then
  install_timer
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is missing."
  exit 1
fi
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker is not available."
  exit 1
fi
if [ ! -f "$ROOT/latent.env" ]; then
  echo "No latent.env yet. Install first."
  exit 1
fi

LOCK="$ROOT/.update.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "An update is already running."
  exit 0
fi

new="$(curl -fsSL --retry 2 --retry-delay 2 -A "Latent-updater/1.0" "$REV_URL" 2>/dev/null | tr -d '[:space:]' || true)"
if ! printf '%s' "$new" | grep -Eq '^[0-9a-f]{7,40}$'; then
  exit 0
fi
old=""
if [ -f "$STATE" ]; then
  old="$(tr -d '[:space:]' < "$STATE")"
fi
if [ "$new" = "$old" ]; then
  exit 0
fi

echo "New Latent image ${new:0:7}."
tmp="$(mktemp)"
curl -fL --retry 3 --retry-delay 2 -A "Latent-updater/1.0" -o "$tmp" "$IMG_URL"
docker load -i "$tmp"
rm -f "$tmp"

if grep -q '^LATENT_IMAGE=' "$ROOT/latent.env"; then
  sed -i.bak 's|^LATENT_IMAGE=.*|LATENT_IMAGE=latent:local|' "$ROOT/latent.env" && rm -f "$ROOT/latent.env.bak"
else
  echo "LATENT_IMAGE=latent:local" >> "$ROOT/latent.env"
fi

profiles=()
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'latent-caddy'; then
  profiles=(--profile edge)
fi
docker compose "${profiles[@]}" --env-file "$ROOT/latent.env" up -d --no-build --force-recreate app
printf '%s\n' "$new" > "$STATE"

CADDY_LIB=""
for f in "$ROOT/caddy.sh" "$ROOT/deploy/vps/caddy.sh"; do
  if [ -f "$f" ]; then CADDY_LIB="$f"; break; fi
done
if [ -n "$CADDY_LIB" ]; then
  # shellcheck disable=SC1090
  . "$CADDY_LIB"
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/latent.env"
  set +a
  latent_detect_caddy
  DOMAIN="$(grep '^LATENT_DOMAIN=' "$ROOT/latent.env" | head -1 | cut -d= -f2- || true)"
  if [ "${CADDY_KIND:-none}" != "none" ] && [ -n "${DOMAIN:-}" ]; then
    latent_piggyback "$DOMAIN" || echo "Image is in. Caddy still points at the old container — run repair.sh."
  fi
fi

echo "Updated to ${new:0:7}."
