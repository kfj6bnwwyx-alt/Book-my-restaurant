# Deploying ResyBooker to a Hetzner VPS

> No VPS? If you have a Home Assistant OS box, run it there instead as a local
> add-on: see [home-assistant/README.md](home-assistant/README.md). The rest of
> this file is the VPS path.

The server runs in Docker, fronted by Caddy for TLS, on a small Hetzner Cloud
box. Two paths: automated (cloud-init) or manual. Either way you finish with the
same `docker compose up` and a Caddy reverse proxy.

Pick a **US East (Ashburn)** location. Auto-book and watches race against
`api.resy.com` on the US east coast; low latency wins more tables. A **CPX11**
(2 vCPU / 2 GB, ~$5/mo) is plenty.

## 0. Before you start

- A domain you control (example here: `resy.brentbrooks.com`).
- A local SSH key: `ssh-keygen -t ed25519 -C resybooker` (save to `~/.ssh/resybooker`).

## 1. Create the server

**Automated:** in the Hetzner Cloud Console, Add Server > Ubuntu 24.04 > Ashburn >
CPX11. Open the "Cloud config" box and paste [`server/cloud-init.yaml`](server/cloud-init.yaml),
replacing `SSH-PUBLIC-KEY-HERE` with your `~/.ssh/resybooker.pub`. Attach a
firewall allowing inbound 22, 80, 443. cloud-init creates the `brent` user,
hardens SSH, opens the firewall, and installs Docker + Caddy on first boot.

**Manual:** create the same server with your SSH key, then run the hardening and
install steps from the README's VPS section by hand.

## 2. DNS

Add an A record `resy.brentbrooks.com -> <server IPv4>` (AAAA to the IPv6 too if
you want). Do this before step 4 so Caddy can get a cert.

## 3. Deploy the app

```bash
ssh -i ~/.ssh/resybooker brent@<server-ip>
git clone https://github.com/kfj6bnwwyx-alt/Book-my-restaurant.git
cd Book-my-restaurant/server
cp .env.example .env && nano .env
#   APP_KEY=$(openssl rand -hex 24)   (paste the same value into iOS Constants.swift)
#   RESY_EMAIL / RESY_PASSWORD        (server mints + auto-refreshes the token)
#   RESY_PAYMENT_METHOD_ID=0          (fill in at step 5)
docker compose up -d --build
curl localhost:8080/health
```

## 4. Caddy (TLS)

```bash
sudo cp Caddyfile /etc/caddy/Caddyfile     # edit the domain if not resy.brentbrooks.com
sudo systemctl reload caddy
curl https://resy.brentbrooks.com/health   # cert issued automatically
```

## 5. Payment method + iOS

```bash
curl -H "X-App-Key: YOUR_APP_KEY" https://resy.brentbrooks.com/resy/payment-methods
nano .env            # set RESY_PAYMENT_METHOD_ID=<id>
docker compose up -d # recreate with the new value
```

In the iOS app set `AppConfig.apiBaseURL` to `https://resy.brentbrooks.com` and
`appKey` to your `APP_KEY` in `Constants.swift`.

## Operating it

- **Update:** `cd ~/Book-my-restaurant/server && ./deploy.sh` (git pull + rebuild).
- **Logs:** `docker compose logs -f`.
- **Wipe the DB** (recreates all tables, including drops/watches): from `server/`,
  `docker compose down && rm -rf ./data && docker compose up -d --build`.
- **Single worker only.** The drop auto-book and watch poller run in-process; the
  Dockerfile runs one uvicorn process. Do not add `--workers`, or the scheduler
  would run twice and could double-book.
- **Timezones** are per drop/watch, so the server box can stay on UTC.
