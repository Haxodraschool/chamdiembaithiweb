# GradeFlow Mobile — Flutter App

Ứng dụng chấm điểm trắc nghiệm tự động bằng camera điện thoại.  
Sử dụng **Google ML Kit Document Scanner** để quét phiếu thi → gửi lên API Python → nhận kết quả chấm.

## Tính năng

- **Quét phiếu thông minh** — Google Document Scanner tự động cắt, nắn thẳng, xóa bóng
- **Chấm điểm tự động** — gửi ảnh lên server Python (OpenCV + CNN)
- **Dashboard** — tổng quan bài thi, điểm trung bình, tỉ lệ đạt
- **Quản lý bài thi** — xem danh sách, chọn đề để chấm
- **Lịch sử** — xem lại kết quả đã chấm
- **Giao diện Vietnamese** — thiết kế giống web GradeFlow

## Yêu cầu

- **Flutter SDK** ≥ 3.5.0
- **Dart** ≥ 3.5.0
- **Android Studio** hoặc **VS Code** + Flutter extensions
- **Android** ≥ 5.0 (API 21) / **iOS** ≥ 12.0
- **Server Django** đang chạy (backend API)

## Cài đặt

### 1. Cài Flutter SDK

```bash
# Xem hướng dẫn: https://docs.flutter.dev/get-started/install
# Windows:
# Tải Flutter SDK từ https://docs.flutter.dev/get-started/install/windows
# Thêm flutter/bin vào PATH
```

### 2. Sinh platform files

```bash
cd gradeflow_app
flutter create .
```

### 3. Cài dependencies

```bash
flutter pub get
```

### 4. Cấu hình server API

Sửa file `lib/config/api_config.dart`:

```dart
// Nếu chạy Android Emulator:
static const String baseUrl = 'http://10.0.2.2:8000';

// Nếu chạy trên thiết bị thật (cùng WiFi):
static const String baseUrl = 'http://192.168.x.x:8000';

// Nếu dùng server Railway:
static const String baseUrl = 'https://your-app.up.railway.app';
```

### 5. Cài thêm packages cho backend Django

```bash
cd ..  # về thư mục gốc
pip install djangorestframework django-cors-headers
python manage.py migrate  # tạo bảng token
```

### 6. Chạy server Django

```bash
python manage.py runserver 0.0.0.0:8000
```

### 7. Chạy app Flutter

```bash
cd gradeflow_app
flutter run
```

## Cấu trúc project

```
gradeflow_app/
├── lib/
│   ├── main.dart              # Entry point
│   ├── config/
│   │   ├── api_config.dart    # Server URL config
│   │   └── theme.dart         # Design system (match web)
│   ├── models/
│   │   ├── exam.dart          # Exam model
│   │   ├── submission.dart    # Submission model
│   │   └── grade_result.dart  # Grade result model
│   ├── services/
│   │   ├── auth_service.dart  # Token auth
│   │   └── api_service.dart   # HTTP client
│   ├── screens/
│   │   ├── login_screen.dart
│   │   ├── main_shell.dart    # Bottom nav shell
│   │   ├── dashboard_screen.dart
│   │   ├── exams_screen.dart
│   │   ├── scan_screen.dart   # Document scanner + grade
│   │   ├── grade_result_screen.dart
│   │   ├── results_screen.dart
│   │   ├── history_screen.dart
│   │   └── profile_screen.dart
│   └── widgets/
│       └── stat_card.dart
└── pubspec.yaml
```

## API Endpoints (Backend)

| Method | Endpoint                      | Mô tả                    |
|--------|-------------------------------|---------------------------|
| POST   | `/api/v1/auth/login/`         | Đăng nhập, trả token     |
| POST   | `/api/v1/auth/logout/`        | Đăng xuất                 |
| GET    | `/api/v1/auth/me/`            | Thông tin user            |
| GET    | `/api/v1/dashboard/`          | Dashboard stats           |
| GET    | `/api/v1/exams/`              | Danh sách đề thi          |
| GET    | `/api/v1/exams/{id}/`         | Chi tiết đề thi           |
| POST   | `/api/v1/grade/`              | **Chấm ảnh** (multipart)  |
| GET    | `/api/v1/submissions/`        | Danh sách bài nộp         |
| GET    | `/api/v1/submissions/{id}/`   | Chi tiết bài nộp          |

### Chấm điểm: `POST /api/v1/grade/`

```bash
curl -X POST https://your-server/api/v1/grade/ \
  -H "Authorization: Token abc123" \
  -F "image=@phieu_thi.jpg" \
  -F "exam_id=1" \
  -F "save=true"
```

Response:
```json
{
  "success": true,
  "sbd": "001234",
  "made": "002",
  "score": 8.5,
  "correct_count": 38,
  "total_questions": 40,
  "grade_label": "excellent",
  "grade_text": "Giỏi",
  "processing_time": 2.3
}
```

## Lưu ý

- **Google ML Kit Document Scanner** chỉ hoạt động trên thiết bị thật Android/iOS (không hoạt động trên Emulator). Trên emulator, app sẽ tự fallback sang camera bình thường hoặc chọn từ gallery.
- Font Manrope và DM Sans sẽ được tải tự động qua `google_fonts` package (không cần file `.ttf` local).
- Nếu muốn sử dụng font local, tải từ Google Fonts và đặt vào `assets/fonts/`.
