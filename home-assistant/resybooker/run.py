"""Add-on entrypoint: map HA options to env vars, then launch the server.

Home Assistant writes the add-on's configured options to /data/options.json and
gives the add-on a persistent /data volume. We translate those options into the
environment variables the app's config.py expects and keep the SQLite DB in /data.
"""

import json
import os

OPTIONS_PATH = "/data/options.json"
OPTION_TO_ENV = {
    "app_key": "APP_KEY",
    "resy_api_key": "RESY_API_KEY",
    "resy_auth_token": "RESY_AUTH_TOKEN",
    "resy_email": "RESY_EMAIL",
    "resy_password": "RESY_PASSWORD",
    "resy_payment_method_id": "RESY_PAYMENT_METHOD_ID",
}

env = dict(os.environ)
try:
    with open(OPTIONS_PATH) as f:
        options = json.load(f)
except FileNotFoundError:
    options = {}

for option, var in OPTION_TO_ENV.items():
    value = options.get(option)
    if value not in (None, ""):
        env[var] = str(value)

# Persist the database on the add-on's /data volume (survives restarts/updates).
env["DB_URL"] = "sqlite:////data/resybooker.db"

os.chdir("/src/server")
os.execvpe(
    "uvicorn",
    ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"],
    env,
)
