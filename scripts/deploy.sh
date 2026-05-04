#!/bin/bash
# =============================================================================
# GradeFlow — Deploy script trên VPS
# Usage: ./scripts/deploy.sh
# =============================================================================
set -e

cd "$(dirname "$0")/.."

echo "[1/4] Pull code mới từ GitHub..."
git pull

echo "[2/4] Rebuild Docker images..."
docker compose build

echo "[3/4] Restart services..."
docker compose up -d

echo "[4/4] Cleanup old images..."
docker image prune -f

echo ""
echo "[OK] Deploy xong!"
echo "Logs: docker compose logs -f web"
