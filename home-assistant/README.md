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

## 5. Point the app

In `ios/ResyBooker/Utilities/Constants.swift`:

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
