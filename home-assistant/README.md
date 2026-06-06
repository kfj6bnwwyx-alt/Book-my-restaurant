# Running ResyBooker on Home Assistant OS

No VPS needed. ResyBooker runs as a local Home Assistant add-on (a supervised
Docker container): it auto-starts, survives reboots, and is configured from the
HA UI. Remote access goes through your existing Cloudflare tunnel.

The add-on keeps its SQLite database on the add-on's persistent `/data` volume,
and runs a single process (the drop auto-book and watch poller live in it).

## 1. Get the add-on onto the box

Local add-ons live in `/addons/<slug>/`. Use any of these to put the files there:

- **Samba share** add-on: mount `\\homeassistant\addons`, then create a
  `resybooker` folder and copy in `config.yaml`, `Dockerfile`, and `run.py`.
- **Studio Code Server** or **Advanced SSH & Web Terminal** add-on: create
  `/addons/resybooker/` and add the three files.

So you end up with:

```
/addons/resybooker/config.yaml
/addons/resybooker/Dockerfile
/addons/resybooker/run.py
```

## 2. Install and configure

1. Settings > Add-ons > Add-on Store > (top-right menu) > **Check for updates**.
   ResyBooker appears under **Local add-ons**. Open it and click **Install**
   (the first build clones the repo and installs deps, a few minutes).
2. Open the **Configuration** tab and set:
   - `app_key`: a long random string (`openssl rand -hex 24`). Paste the same
     value into the iOS app's `Constants.swift`.
   - `resy_email` / `resy_password`: lets the server mint and refresh the Resy
     token automatically. (Or paste a `resy_auth_token` instead.)
   - leave `resy_payment_method_id` at `0` for now.
3. **Info** tab > enable **Start on boot** and **Watchdog**, then **Start**.
4. Check the **Log** tab for `Application startup complete`.

## 3. Find your payment method id

From any machine on your LAN (replace the host if needed):

```bash
curl -H "X-App-Key: YOUR_APP_KEY" http://homeassistant.local:8080/resy/payment-methods
```

Copy the id of the card you want to book with, set `resy_payment_method_id` in
the add-on Configuration, and **Restart** the add-on.

## 4. Expose it through Cloudflare

The add-on publishes port `8080` on the HA host, so point a Cloudflare tunnel
hostname at it. If you use the **Cloudflared** add-on, add to its config:

```yaml
additional_hosts:
  - hostname: resy.brentbrooks.com
    service: http://homeassistant.local:8080
```

Or, in the Cloudflare Zero Trust dashboard, add a public hostname on your tunnel:
`resy.brentbrooks.com` -> service `http://homeassistant.local:8080` (or the HA
box's LAN IP). Cloudflare terminates TLS, so there is no Caddy or cert to manage.

Verify: `curl https://resy.brentbrooks.com/health`.

## 4b. Alternative: Tailscale (instead of Cloudflare)

If you ever want to skip Cloudflare and reach the add-on over a private tailnet:

1. Install the **Tailscale** add-on, start it, and open the **Log** to follow the
   login URL. The HA host joins your tailnet.
2. In the Tailscale admin console, enable **MagicDNS**. The host gets a name like
   `homeassistant.<your-tailnet>.ts.net`.
3. Put HTTPS in front with **Tailscale Serve**, so iOS App Transport Security is
   happy: enable serve to `localhost:8080` in the add-on options, or run
   `tailscale serve --bg 8080` on the host. ResyBooker is then reachable at
   `https://homeassistant.<your-tailnet>.ts.net`.
   - Without Serve you would be on plain `http://...:8080`, which iOS blocks by
     default (ATS). Serve gives you a real cert and avoids that.
4. Install Tailscale on each phone and sign in, then point the app at the
   `https://...ts.net` URL.

Trade-off: every device that uses the app must be on your tailnet. That is fine
for your own phones; for friends you would add them to the tailnet (or just use
the Cloudflare route above, which needs nothing on their end).

## 5. Point the app

In `ios/ResyBooker/Utilities/Constants.swift`, use whichever hostname you set up
(the Cloudflare one, or the Tailscale `...ts.net` one):

```swift
static let apiBaseURL = URL(string: "https://resy.brentbrooks.com")!
static let appKey = "YOUR_APP_KEY"
```

## Operating it

- **Update:** open the add-on > (menu) > **Rebuild** to pull the latest code.
- **Logs:** the add-on **Log** tab.
- **Wipe the DB:** delete `/data/resybooker.db` inside the add-on (via the SSH or
  Code Server add-on at `/addons/.../`), or **Uninstall** the add-on (this clears
  its `/data`) and reinstall. Either way the schema is recreated on next start.
- **Latency note:** booking from home is a touch slower than a US-East datacenter,
  fine for personal use, marginally worse on the most contested noon drops.
