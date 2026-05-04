#!/bin/bash
# =============================================================================
# Init SSL với Let's Encrypt — chạy 1 lần đầu
# Usage: ./scripts/init-ssl.sh gradefloww.duckdns.org you@email.com
# =============================================================================
set -e

DOMAIN=${1:-gradefloww.duckdns.org}
EMAIL=${2:-admin@example.com}

cd "$(dirname "$0")/.."

echo "[1/5] Tạo thư mục cho certbot..."
mkdir -p certbot/conf certbot/www

echo "[2/5] Lấy SSL cert từ Let's Encrypt..."
docker run --rm \
  -v "$PWD/certbot/conf:/etc/letsencrypt" \
  -v "$PWD/certbot/www:/var/www/certbot" \
  -p 80:80 \
  certbot/certbot certonly \
  --standalone \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  -d "$DOMAIN"

echo "[3/5] Restart nginx..."
docker compose up -d nginx

echo "[4/5] Setup auto-renew (cron)..."
(crontab -l 2>/dev/null; echo "0 3 * * 0 cd $PWD && docker run --rm -v \$PWD/certbot/conf:/etc/letsencrypt -v \$PWD/certbot/www:/var/www/certbot certbot/certbot renew --quiet && docker compose restart nginx") | crontab -

echo ""
echo "[OK] HTTPS setup xong!"
echo "Test: https://$DOMAIN/"
