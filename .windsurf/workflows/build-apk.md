---
description: Build APK từ source code Flutter sau khi sửa
---

# Quy trình sửa và build APK

## Bước 1: Sửa source code
- AI sửa file Dart trong `gradeflow_app/lib/`
- Ví dụ: `live_camera_screen.dart`, `api_service.dart`, v.v.

## Bước 2: Build APK mới
```bash
cd gradeflow_app
flutter clean
flutter pub get
flutter build apk --release
```

## Bước 3: Lấy APK mới
APK xuất hiện tại:
```
gradeflow_app/build/app/outputs/flutter-apk/app-release.apk
```

## Lưu ý
- Đảm bảo Flutter SDK đã cài đặt (C:\flutter\bin)
- Nếu `flutter` không có trong PATH, dùng đường dẫn đầy đủ:
  ```bash
  C:\flutter\bin\flutter build apk --release
  ```
