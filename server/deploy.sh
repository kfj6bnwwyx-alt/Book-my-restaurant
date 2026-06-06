#!/usr/bin/env bash
# Pull the latest code and rebuild the running server. Run from the VPS:
#   cd ~/Book-my-restaurant/server && ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Pulling latest"
git pull --ff-only

echo "==> Rebuilding and restarting"
docker compose up -d --build

echo "==> Status"
docker compose ps
echo "==> Health"
curl -fsS localhost:8080/health && echo
