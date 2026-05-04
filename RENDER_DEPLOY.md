# Deploy GradeFlow lên Render

## 1. Chuẩn bị

- Đã có tài khoản [Render.com](https://render.com)
- Repo GitHub đã push code mới (Dockerfile + .dockerignore)

## 2. Tạo Web Service

1. Vào Render Dashboard → **New +** → **Web Service**
2. Connect GitHub → chọn repo `chamdiembaithiweb`
3. Cấu hình:
   - **Name**: `gradeflow` (tùy ý)
   - **Region**: **Singapore** (latency thấp nhất từ VN, ~30-50ms)
   - **Branch**: `main`
   - **Runtime**: **Docker** (Render tự detect Dockerfile)
   - **Instance Type**:
     - Free: 512MB RAM (chỉ test, sẽ ngủ sau 15 phút không dùng)
     - **Starter $7/tháng**: 512MB RAM, không ngủ ← khuyến nghị
     - Standard $25/tháng: 2GB RAM, mạnh hơn nhiều

## 3. Environment Variables

Bấm **Advanced** → **Add Environment Variable**, thêm:

| Key | Value | Ghi chú |
|-----|-------|---------|
| `SECRET_KEY` | `<random 50 ký tự>` | Django secret |
| `DEBUG` | `False` | Production |
| `ALLOWED_HOSTS` | `<your-app>.onrender.com` | Render sẽ cấp domain |
| `DATABASE_URL` | `<từ Render Postgres>` | Tạo Postgres riêng (xem bước 4) |
| `DJANGO_SETTINGS_MODULE` | `chamdiemtudong.settings` | |

## 4. Postgres database (free 90 ngày)

1. Render Dashboard → **New +** → **PostgreSQL**
2. Region **Singapore** (cùng region với web service)
3. Plan: **Free** (1GB storage, 90 ngày)
4. Sau khi tạo xong, copy **Internal Database URL** → paste vào `DATABASE_URL` của web service

## 5. Health Check (optional)

- **Health Check Path**: `/` (hoặc bất kỳ URL nào trả 200)
- Render tự ping mỗi 30s

## 6. Deploy

- Bấm **Create Web Service** → Render tự build Dockerfile (~5-10 phút lần đầu)
- Build xong → URL có dạng `https://gradeflow.onrender.com`

## 7. Cập nhật Flutter app

Sửa `gradeflow_app/lib/services/api_service.dart`:
```dart
static const String baseUrl = 'https://gradeflow.onrender.com/api/v1';
```

Build lại APK.

## 8. Lưu ý

- **Free plan ngủ sau 15 phút** không có request → request đầu tiên sau đó mất 30-60s khởi động
- **Nâng lên Starter $7** để tránh cold start
- **Build cache**: Render cache layer Docker, push thay đổi nhỏ chỉ rebuild ~1-2 phút
- **Logs**: tab **Logs** trong Render dashboard

## 9. Test sau deploy

```bash
curl https://gradeflow.onrender.com/api/v1/exams/ \
    -H "Authorization: Token <your-token>"
```

Nên thấy JSON danh sách đề thi.

## Khắc phục sự cố

| Lỗi | Fix |
|-----|-----|
| `WORKER TIMEOUT` | Tăng `--timeout` trong CMD Dockerfile |
| `OOMKilled` | Nâng plan lên Standard 2GB hoặc tắt `HYBRID_CNN_ENABLE` |
| `libGL.so.1: cannot open` | Đã có trong Dockerfile (`libgl1`) |
| `tesseract not found` | Đã có (`tesseract-ocr` + `tesseract-ocr-vie`) |
| Static files 404 | Đảm bảo `whitenoise.middleware` đứng sau `SecurityMiddleware` trong settings |
