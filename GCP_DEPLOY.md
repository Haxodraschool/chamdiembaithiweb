# GradeFlow — Deploy lên Google Cloud VPS

VM: `gradeflow-server` | IP: `34.87.39.102` | Region: Singapore

---

## 1. SSH vào VM

Mở terminal/PowerShell trên máy bạn:

```bash
gcloud compute ssh gradeflow-server --zone=asia-southeast1-b
```

Hoặc click **SSH** trên trang VM trong Cloud Console.

---

## 2. Cài Docker + Docker Compose (chạy 1 lần)

Copy paste cả block này vào terminal SSH:

```bash
# Update + cài tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg git ufw

# Cài Docker
curl -fsSL https://get.docker.com | sudo sh

# Thêm user vào group docker (không cần sudo)
sudo usermod -aG docker $USER

# Bật firewall
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Logout + login lại để áp dụng group
exit
```

SSH lại:

```bash
gcloud compute ssh gradeflow-server --zone=asia-southeast1-b
```

Test Docker:

```bash
docker --version
docker compose version
```

---

## 3. Clone repo

```bash
git clone https://github.com/Haxodraschool/chamdiembaithiweb.git
cd chamdiembaithiweb
```

---

## 4. Tạo file `.env`

```bash
cat > .env <<'EOF'
# Postgres
POSTGRES_DB=gradeflow
POSTGRES_USER=gradeflow
POSTGRES_PASSWORD=ĐỔI_THÀNH_PASSWORD_MẠNH_TẠI_ĐÂY

# Django
DJANGO_SECRET_KEY=ĐỔI_THÀNH_SECRET_KEY_NGẪU_NHIÊN_50_KÝ_TỰ
ALLOWED_HOSTS=34.87.39.102,localhost

# OMR Engine — tắt CNN trên VPS yếu (e2-medium đủ chạy)
HYBRID_CNN_ENABLE=1
EOF
```

**Sinh SECRET_KEY ngẫu nhiên**:

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(50))"
```

Copy kết quả vào `.env` (thay `ĐỔI_THÀNH_SECRET_KEY...`).

Edit nếu cần:
```bash
nano .env
```

---

## 5. Build + Run

```bash
docker compose up -d --build
```

Lần đầu mất 5-10 phút (download image, build PyTorch...).

Xem log:
```bash
docker compose logs -f web
```

---

## 6. Tạo superuser Django

```bash
docker compose exec web python manage.py createsuperuser
```

---

## 7. Test

Mở browser: `http://34.87.39.102/`

Login admin: `http://34.87.39.102/admin/`

---

## 8. Update Flutter app

Sửa `gradeflow_app/lib/config/api_config.dart`:

```dart
static const String baseUrl = 'http://34.87.39.102';
```

Build APK:
```bash
cd gradeflow_app
flutter build apk --release
```

---

## Lệnh thường dùng

```bash
# Xem log
docker compose logs -f web

# Restart sau khi pull code mới
git pull
docker compose up -d --build

# Vào shell Django
docker compose exec web python manage.py shell

# Backup DB
docker compose exec db pg_dump -U gradeflow gradeflow > backup_$(date +%Y%m%d).sql

# Stop
docker compose down

# Stop + xóa data
docker compose down -v
```

---

## (Sau này) Domain + HTTPS

1. Mua domain → trỏ A record về `34.87.39.102`
2. Đổi `ALLOWED_HOSTS` trong `.env`
3. Cài certbot:

```bash
docker run -it --rm \
  -v ./certbot/conf:/etc/letsencrypt \
  -v ./certbot/www:/var/www/certbot \
  certbot/certbot certonly --webroot \
  -w /var/www/certbot \
  -d yourdomain.com \
  --email you@email.com --agree-tos
```

4. Update `nginx.conf` thêm block 443.
