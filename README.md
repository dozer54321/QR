# Latent

Type a link. Drop a photograph. The QR code hides in the picture, and a phone can still scan it.

Finder squares, timing, and alignment stay solid so a camera can lock on. The photograph lives in the rest of the modules. A line under the preview says whether a reader can still decode it.

Live site: [qr.yourmomon.top](https://qr.yourmomon.top)

## Install

Point a DNS A record for `qr.yourmomon.top` at the VPS first. Paste one line at a time. No git, no username, no compile once the first image is published.

```bash
sudo apt-get update && sudo apt-get install -y curl
```

```bash
curl -fsSL -o /tmp/latent-install.sh https://raw.githubusercontent.com/dozer54321/latent/main/deploy/vps/bootstrap.sh
```

```bash
sudo bash /tmp/latent-install.sh
```

It uses the Caddy you already run (same as Take-Home, Parrot Clicker, and Momon) and listens on `127.0.0.1:3070`. Eye tracker already has `3090`.

| Port | App |
| --- | --- |
| 3010 | Take-Home |
| 3060 | Parrot Clicker |
| 3070 | Latent |
| 3080 | Momon |
| 3090 | Eye tracker |

Nothing is stored on the server. Codes stay in the browser.

## Auto-update

Every push to `main` publishes a public image. The VPS loads it on its own, about every 2 minutes. No login.

```bash
systemctl status latent-update.timer
```

Repair the wiring later with `sudo /opt/latent/deploy/vps/repair.sh qr.yourmomon.top`.
