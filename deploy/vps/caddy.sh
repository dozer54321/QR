#!/bin/bash
# Detect an existing Caddy (host service or Docker container) and piggyback
# Latent onto it. Sourced by start.sh / repair.sh — do not exec this file.
# Same arrangement as Momon on Requestick: share ports 80/443, own container.

latent_docker_caddy_id() {
  docker ps --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null \
    | grep -i caddy \
    | awk '{print $1}' \
    | head -1
}

latent_caddyfile_from_container() {
  local id="$1"
  local dest src
  while read -r dest src; do
    [ -n "$dest" ] || continue
    case "$dest" in
      /etc/caddy/Caddyfile)
        if [ -f "$src" ]; then echo "$src"; return 0; fi
        ;;
      /etc/caddy)
        if [ -f "$src/Caddyfile" ]; then echo "$src/Caddyfile"; return 0; fi
        ;;
    esac
    case "$src" in
      *Caddyfile)
        if [ -f "$src" ]; then echo "$src"; return 0; fi
        ;;
    esac
  done < <(docker inspect -f '{{range .Mounts}}{{.Destination}} {{.Source}}{{"\n"}}{{end}}' "$id" 2>/dev/null)
  for f in /opt/requestick/Caddyfile /opt/caddy/Caddyfile /etc/caddy/Caddyfile; do
    if [ -f "$f" ]; then echo "$f"; return 0; fi
  done
  return 1
}

latent_caddy_net() {
  local id="$1"
  docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "$id" 2>/dev/null \
    | awk 'NF && $0 != "bridge" && $0 != "host" && $0 != "none" {print; exit}'
}

# Sets CADDY_KIND=host|docker|none, plus CADDY_FILE / CADDY_ID / CADDY_NET.
latent_detect_caddy() {
  CADDY_KIND=none
  CADDY_FILE=""
  CADDY_ID=""
  CADDY_NET=""

  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet caddy 2>/dev/null; then
    CADDY_KIND=host
    for f in /etc/caddy/Caddyfile /usr/local/etc/caddy/Caddyfile; do
      if [ -f "$f" ]; then CADDY_FILE="$f"; break; fi
    done
    [ -n "$CADDY_FILE" ] || CADDY_FILE=/etc/caddy/Caddyfile
    echo "Found host Caddy (systemd) → $CADDY_FILE"
    return 0
  fi

  if command -v caddy >/dev/null 2>&1 && pgrep -x caddy >/dev/null 2>&1; then
    CADDY_KIND=host
    for f in /etc/caddy/Caddyfile /usr/local/etc/caddy/Caddyfile; do
      if [ -f "$f" ]; then CADDY_FILE="$f"; break; fi
    done
    [ -n "$CADDY_FILE" ] || CADDY_FILE=/etc/caddy/Caddyfile
    echo "Found host Caddy (process) → $CADDY_FILE"
    return 0
  fi

  CADDY_ID="$(latent_docker_caddy_id || true)"
  if [ -n "$CADDY_ID" ]; then
    CADDY_KIND=docker
    CADDY_NET="$(latent_caddy_net "$CADDY_ID" || true)"
    CADDY_FILE="$(latent_caddyfile_from_container "$CADDY_ID" || true)"
    echo "Found Caddy container ${CADDY_ID:0:12} net=${CADDY_NET:-?} file=${CADDY_FILE:-unset}"
    return 0
  fi

  echo "No Caddy on the host or in Docker."
  return 0
}

latent_write_site() {
  local caddyfile="$1"
  local domain="$2"
  local target="$3"
  if [ -z "$caddyfile" ]; then
    echo "No Caddyfile path — cannot add ${domain}."
    return 1
  fi
  mkdir -p "$(dirname "$caddyfile")"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$caddyfile" "$domain" "$target" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
domain = sys.argv[2]
target = sys.argv[3]
www = f"www.{domain}"
block = (
    f"{domain}, {www} {{\n"
    f"  encode gzip\n"
    f"  reverse_proxy {target}\n"
    f"}}\n"
)
text = path.read_text() if path.exists() else ""
pattern = re.compile(
    rf"(?m)^(?:{re.escape(domain)}|{re.escape(www)})(?:,[^\n]*)?\s*\{{[\s\S]*?^\}}\s*"
)
text, _ = pattern.subn("", text)
path.write_text(text.rstrip() + "\n\n" + block)
print(f"Caddy: {domain} + {www} → {target}")
PY
    return
  fi
  cat >> "$caddyfile" <<EOF

${domain}, www.${domain} {
  encode gzip
  reverse_proxy ${target}
}
EOF
  echo "Caddy: ${domain} + www → ${target}"
}

latent_reload_caddy() {
  case "${CADDY_KIND}" in
    host)
      if command -v systemctl >/dev/null 2>&1; then
        systemctl reload caddy 2>/dev/null || systemctl restart caddy
      else
        caddy reload --config "$CADDY_FILE"
      fi
      ;;
    docker)
      if [ -n "$CADDY_ID" ]; then
        docker exec "$CADDY_ID" caddy reload --config /etc/caddy/Caddyfile 2>/dev/null \
          || docker restart "$CADDY_ID"
      fi
      ;;
  esac
}

latent_join_caddy_net() {
  local i
  [ -n "${CADDY_NET:-}" ] || return 0
  for i in $(seq 1 30); do
    if docker inspect -f '{{.State.Running}}' latent-app 2>/dev/null | grep -qx true; then
      docker network connect "$CADDY_NET" latent-app 2>/dev/null || true
      return 0
    fi
    sleep 2
  done
}

# Host Caddy talks to 127.0.0.1:3070. Docker Caddy talks to latent-app on its network.
latent_piggyback() {
  local domain="$1"
  local port="${LATENT_PORT:-3070}"
  local target ip

  if [ "$CADDY_KIND" = "host" ]; then
    target="127.0.0.1:${port}"
    latent_write_site "$CADDY_FILE" "$domain" "$target"
    latent_reload_caddy
    echo "Piggybacked host Caddy."
    return 0
  fi

  if [ "$CADDY_KIND" = "docker" ]; then
    latent_join_caddy_net
    target="latent-app:3000"
    if [ -n "$CADDY_NET" ]; then
      ip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$CADDY_NET\").IPAddress}}" latent-app 2>/dev/null || true)"
      if [ -n "$ip" ]; then
        target="${ip}:3000"
      fi
    fi
    if [ -z "$CADDY_FILE" ]; then
      echo "Caddy is a container but its Caddyfile is not on disk. Cannot piggyback."
      return 1
    fi
    latent_write_site "$CADDY_FILE" "$domain" "$target"
    latent_reload_caddy
    echo "Piggybacked Caddy container → ${target}"
    return 0
  fi

  return 1
}

latent_write_net_override() {
  local root="$1"
  local net="$2"
  cat > "$root/docker-compose.override.yml" <<EOF
# Generated: attach latent-app to the existing Caddy network (Requestick's).
services:
  app:
    container_name: latent-app
    networks:
      - latent
      - caddy_net
networks:
  caddy_net:
    external: true
    name: ${net}
EOF
}
