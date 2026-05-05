---
description: GradeFlow project knowledge — architecture, APK build, OMR grading pipeline, deployment
---

# GradeFlow — Hệ thống chấm bài trắc nghiệm OMR

## 1. Tổng quan kiến trúc

```
┌──────────────────────────────────────────────────────────────────┐
│                     FLUTTER APP (Android APK)                     │
│  gradeflow_app/                                                   │
│  ┌─────────┐  ┌──────────┐  ┌──────────────────┐                │
│  │ Camera   │→│ OpenCV   │→│ Crop & Upload     │                │
│  │ Preview  │  │ Marker   │  │ to Backend        │                │
│  │          │  │ Detection│  │ POST /api/v1/grade│                │
│  └─────────┘  └──────────┘  └────────┬─────────┘                │
└───────────────────────────────────────┼──────────────────────────┘
                                        │ HTTPS (multipart image)
                                        ▼
┌──────────────────────────────────────────────────────────────────┐
│                     GCP VM (Docker Stack)                          │
│  ┌─────────┐  ┌──────────────┐  ┌──────────────┐                │
│  │ Nginx   │→│ Django+DRF   │→│ OMR Engine    │                │
│  │ :80/443 │  │ (Gunicorn)   │  │ (hi.py)       │                │
│  │ SSL     │  │ :8000        │  │ OpenCV+CNN    │                │
│  └─────────┘  └──────┬───────┘  └──────────────┘                │
│                       │                                            │
│               ┌───────▼───────┐                                   │
│               │ PostgreSQL 16 │                                   │
│               │ (Docker)      │                                   │
│               └───────────────┘                                   │
└──────────────────────────────────────────────────────────────────┘
```

**Domain**: `https://gradefloww.duckdns.org`
**VM IP**: 35.198.202.198 (GCP e2-medium, Singapore)

---

## 2. Cấu trúc thư mục

```
chamdiembaithiweb/
├── gradeflow_app/              # Flutter Android app
│   ├── lib/
│   │   ├── config/
│   │   │   ├── api_config.dart       # API endpoints, baseUrl
│   │   │   └── theme.dart            # Design system (Teal, fonts)
│   │   ├── models/
│   │   │   ├── exam.dart             # Exam model
│   │   │   ├── grade_result.dart     # Grade result model
│   │   │   └── submission.dart       # Submission model
│   │   ├── screens/
│   │   │   ├── live_camera_screen.dart  # ★ Camera + OpenCV marker detection
│   │   │   ├── scan_screen.dart         # Scan tab (camera/gallery picker)
│   │   │   ├── grade_result_screen.dart # Show grading results
│   │   │   ├── exams_screen.dart        # Exam list
│   │   │   ├── exam_create_screen.dart  # Create/edit exam
│   │   │   ├── exam_import_screen.dart  # Import from Excel
│   │   │   ├── batch_scan_screen.dart   # Multi-image scan
│   │   │   ├── dashboard_screen.dart    # Home dashboard
│   │   │   ├── login_screen.dart        # Auth
│   │   │   ├── history_screen.dart      # Past submissions
│   │   │   ├── results_screen.dart      # Results overview
│   │   │   ├── profile_screen.dart      # User profile
│   │   │   ├── settings_screen.dart     # App settings
│   │   │   └── main_shell.dart          # Bottom nav shell
│   │   ├── services/
│   │   │   ├── api_service.dart         # HTTP client → backend
│   │   │   ├── auth_service.dart        # Token auth (SharedPreferences)
│   │   │   └── training_uploader.dart   # Upload training data
│   │   └── main.dart
│   ├── android/
│   │   └── app/
│   │       ├── build.gradle.kts         # Android build config
│   │       └── src/main/AndroidManifest.xml
│   └── pubspec.yaml                     # Flutter dependencies
│
├── grading/                    # Django app — grading logic
│   ├── engine/
│   │   ├── hi.py               # ★★★ OMR Engine chính (4000+ lines)
│   │   ├── bubble_cnn.onnx     # CNN model (bubble classifier)
│   │   ├── bubble_cnn.pth      # PyTorch model
│   │   ├── templates/          # Template JSON files
│   │   └── train_bubble_cnn.py # Training script
│   ├── grader.py               # ★ Wrapper: Django ↔ Engine
│   ├── views.py                # ★ Web views (upload, grade, exams)
│   ├── models.py               # Exam, Submission, ExamVariant models
│   └── forms.py
│
├── api/                        # Django REST API cho Flutter
│   ├── views.py                # ★ REST endpoints (grade, exams, auth)
│   └── urls.py                 # URL routing
│
├── chamdiemtudong/             # Django project settings
│   ├── settings.py             # CSRF, SSL, DB, CORS config
│   └── urls.py                 # Root URL config
│
├── templates/                  # Django HTML templates (web UI)
├── static/                     # Static files (CSS, JS)
├── cacmaubaithi/               # Physical exam template images (QM 2025)
│
├── Dockerfile                  # Python 3.12 + OpenCV + PyTorch CPU
├── docker-compose.yml          # db (Postgres) + web (Django) + nginx
├── nginx.conf                  # Reverse proxy + SSL termination
├── requirements.txt            # Python dependencies
├── .github/workflows/
│   └── deploy.yml              # Auto-deploy on push to main
└── scripts/
    ├── deploy.sh               # Manual deploy helper
    └── init-ssl.sh             # Let's Encrypt SSL setup
```

---

## 3. Build APK — Flutter App

### Prerequisites
- Flutter SDK >= 3.5.0 (Dart SDK ^3.5.0)
- Android SDK + JDK 17
- Windows/macOS/Linux

### Build Commands
```bash
cd gradeflow_app

# Get dependencies
flutter pub get

# Build debug APK (nhanh, có debug symbols)
flutter build apk --debug

# Build release APK (optimized, signed with debug key)
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Key Dependencies (pubspec.yaml)
| Package | Purpose |
|---------|---------|
| `camera: ^0.11.0+2` | Live camera stream |
| `opencv_dart: ^1.3.0` | OpenCV cho marker detection trên device |
| `image_picker: ^1.1.2` | Gallery/camera picker |
| `image_cropper: ^8.0.2` | Manual image cropping |
| `http: ^1.2.2` | REST API calls |
| `provider: ^6.1.2` | State management |
| `shared_preferences: ^2.3.2` | Token storage |
| `google_fonts: ^6.2.1` | Manrope + DM Sans fonts |
| `lucide_icons: ^0.257.0` | Icons |

### Android Config
- **applicationId**: `com.gradeflow.gradeflow_app`
- **minSdk**: Flutter default (~21)
- **compileSdk**: Flutter default
- **Java**: 17
- **Signing**: Debug key (chưa có production keystore)
- **Permissions**: INTERNET, CAMERA
- **usesCleartextTraffic**: true (fallback HTTP)

### Lưu ý khi build
1. `opencv_dart` cần NDK — Flutter tự xử lý qua Gradle
2. Release APK dùng debug signing → chưa upload được Google Play
3. Để tạo production keystore:
   ```bash
   keytool -genkey -v -keystore ~/gradeflow-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias gradeflow
   ```
   Sau đó cấu hình `android/app/build.gradle.kts` với `signingConfigs.release`

---

## 4. Flutter Camera Detection Pipeline

### File: `gradeflow_app/lib/screens/live_camera_screen.dart`

### Flow
```
Camera stream (30fps)
  ↓ _processFrame()
Convert YUV → grayscale → rotate 90° (sensor landscape → portrait)
  ↓ _detect(gray, w, h)
Resize to 640px wide
  ↓
GaussianBlur(3,3)
  ↓
Multi-threshold (7 strategies):
  - Adaptive threshold (blockSize=25, C=10)
  - Simple thresholds: 40, 60, 80, 100, 120, 140
  ↓
For each threshold image:
  findContours → filter by:
    - Area: 36px² - 2500px² (6-50px sides)
    - Aspect ratio: < 2.0 (roughly square)
    - Fill ratio (extent): > 0.4
  ↓
Score each candidate:
  score = extent * 0.4 + squareness * 0.2
  + proximity_bonus (0.5 * (1 - dist/0.30)) if near corner
  ↓
Deduplicate (40px radius)
  ↓
Pick best 1 marker per quadrant (60% score + 40% proximity)
  ↓
Size consistency check (reject if maxDev > 2.0)
  ↓
Return 4 CornerMarkers (or empty)
```

### UI Overlay
- 4 L-shaped brackets (Azota-style guide frame)
- Gray = undetected, Green = detected
- Auto-capture after 4/4 stable for 2 seconds
- Haptic feedback on capture

### Smart Crop
- If 4 markers detected → crop to marker bounding box + 15% padding
- Fallback → crop to guide frame (88% of screen width, aspect 0.69)

### Constants (Azota-derived)
```dart
_kRatioDefault = 0.69     // paper w/h ≈ A4
_kFramePercent = 0.88     // guide frame = 88% screen width
_kMarkPercent  = 0.06     // L-bracket arm = 6% screen width
_kStableMs     = 2000     // 2s stable → auto-capture
_kCropPadding  = 0.05     // 5% extra margin
```

---

## 5. Backend OMR Engine Pipeline

### File: `grading/engine/hi.py` (~4000 lines)

### Main Entry: `process_sheet(image_path, correct_answers, debug, pre_warped, provided_corners)`

### Full Pipeline
```
1. Load image + Fix EXIF orientation (phone camera)
   ↓
2. Detect paper corners + Warp (perspective transform)
   ├── Method A: corner_markers — find all black squares → pick 4 nearest corners
   ├── Method B: paper_contour — find paper edge → warp
   └── Method C: paper+markers — find paper edge → find markers at INSET positions
   Score each method → pick best
   ↓
3. Post-warp validation (HoughCircles grid alignment check)
   If <30% bubbles match → try other method
   ↓
4. Preprocess (multi-mode with auto-retry)
   ├── FAST: standard grayscale + threshold + morphological cleaning
   ├── ROBUST: stronger preprocessing for poor quality
   ├── ENHANCED: camera-specific enhancement (CLAHE)
   └── PHONE: extreme enhancement for phone photos
   Auto-retry if confidence < 0.4 on >25% of questions
   ↓
5. Text erasure (3-layer protection):
   Layer 1: erase_printed_text() — white out text regions with bubble punch-holes
   Layer 2: Morphological opening — remove thin printed strokes
   Layer 3: mask_printed_text() — safety net on threshold image
   ↓
6. Detect section offsets (Y-axis drift compensation)
   Scan for section markers → calculate pixel offset per part
   ↓
7. Extract answers:
   ├── SBD (6 digits) + Mã đề (3 digits): column-based bubble reading
   ├── Part I (40 MCQ): 4 columns × 10 rows × ABCD, hybrid OpenCV+CNN
   ├── Part II (8 T/F): 8 blocks × 4 sub-questions × Đúng/Sai
   └── Part III (6 numeric): sign + comma + 4 digit columns × 0-9, OCR fallback
   ↓
8. Quality gate: reject if >70% low confidence or >70% blank
   ↓
9. Validation warnings:
   - >80% same answer → possible systematic bias
   - >50% blanks → poor image quality
   - Part II/III anomalies
   ↓
10. Score calculation (if answer key provided):
    - Part I: count correct × weight_per_question
    - Part II: MOET scoring table (0→0, 1→0.1, 2→0.25, 3→0.5, 4→1.0)
    - Part III: exact match × weight_per_question
    ↓
11. Generate result image (overlay answers on warped sheet)
    ↓
12. Return result dict
```

### Warped Image Coordinates (1400×1920)
- **Bubble radius**: 13px (adaptive scaling)
- **Part I**: 4 columns at x=[82, 430, 781, 1130], y_start=689, step_x=72-74, step_y=33.1
- **Part II**: 8 blocks at x=[81,228,430,577,781,927,1130,1276], y_start=1187
- **Part III**: 6 blocks, sign_y=1490, comma_y=1522, digits_y=1555+d*33.1
- **SBD**: x=[1057,1085,1113,1141,1169,1197], digit_y=[173,206,...,517]
- **Mã đề**: x=[1292,1321,1345]

### Template System
- Templates stored as JSON in `grading/engine/templates/`
- `load_template(json_path)` updates ALL global coordinate constants
- Template code format: `"40-08-06"` = 40 P1 + 8 P2 + 6 P3 questions
- 15+ pre-built QM 2025 templates in `grading/views.py:EXAM_TEMPLATES`

### Corner Detection (Method C — Template-Aware)
```python
# QM 2025 markers are INSET ~5% from paper edges (not at corners!)
INSET_RATIO = 0.05
SEARCH_RADIUS_RATIO = 0.035

# For each paper corner:
#   1. Calculate expected marker position = corner + 5% toward center
#   2. Define ROI centered at expected position (±3.5%)
#   3. Multi-threshold contour search (50, 70, 90, 110, 130, 150 + Otsu)
#   4. Score by proximity to expected position + shape quality
#   5. Size consistency check (reject if markers differ > 2x median)
```

### Hybrid CNN Bubble Classifier
- ONNX model at `grading/engine/bubble_cnn.onnx`
- Used for ambiguous bubbles (ink ratio between 0.12-0.45)
- Input: 32×32 grayscale patch, Output: filled/empty probability
- Enabled via `HYBRID_CNN_ENABLE=1` env var

---

## 6. Backend Django Architecture

### API Flow (Flutter → Backend)
```
Flutter app
  ↓ POST /api/v1/grade/  (multipart: image + exam_id)
api/views.py → grade_api()
  ↓
grading/grader.py → grade_image(image_path, answer_key_str, template_code)
  ↓ load template JSON
  ↓ parse answer key (JSON or CSV)
grading/engine/hi.py → process_sheet(image_path, correct_answers)
  ↓ (full OMR pipeline)
  ↓ returns result dict
grading/grader.py → compute_weighted_score(result, scoring_config)
  ↓ MOET Part II scoring
  ↓ Scale to 10-point scale
api/views.py → save Submission to DB → return JSON response
```

### Web Flow (Browser → Backend)
```
Browser
  ↓ POST /upload/  (multipart images + template_code + exam_id)
grading/views.py → upload_view()
  ↓ same grading pipeline as API
  ↓ save Submission → redirect to results page
```

### REST API Endpoints (api/views.py)
```
POST /api/v1/auth/register/    — Đăng ký
POST /api/v1/auth/login/       — Đăng nhập → token
POST /api/v1/auth/logout/      — Xóa token
GET  /api/v1/auth/me/          — User info
GET  /api/v1/dashboard/        — Stats
GET  /api/v1/exams/            — List exams
GET  /api/v1/exams/{id}/       — Exam detail
POST /api/v1/exams/            — Create exam
POST /api/v1/grade/            — ★ Chấm ảnh (multipart image + exam_id)
GET  /api/v1/submissions/      — List submissions
GET  /api/v1/submissions/{id}/ — Submission detail
GET  /api/v1/templates/        — List available templates
POST /api/v1/parse-excel/      — Parse Excel answer key
POST /api/v1/parse-image/      — Detect answers from image
GET  /api/v1/settings/         — User settings
POST /api/v1/training/upload/  — Upload training data
```

### Models (grading/models.py)
- **Exam**: title, subject, num_questions, answer_key (JSON), template_code
- **ExamVariant**: exam FK, variant_code (mã đề), answers_json
- **Submission**: exam FK, image, student_id, score, answers_detected, detail_json
- **UserSettings**: user FK, preferences
- **TrainingSample**: bubble images for CNN training

### Scoring System (grading/grader.py)
- **Part I**: `correct_count × p1_weight` (default 0.25 per question)
- **Part II (MOET standard)**: 0 correct=0đ, 1=0.1đ, 2=0.25đ, 3=0.5đ, 4=1.0đ per question
- **Part III**: `correct_count × p3_weight` (default 0.5 per question)
- **Total**: sum of parts, auto-scaled to 10-point scale if `max != 10`

### Answer Key Formats
1. **JSON** (preferred): `{"parts":[40,8,6], "p1":{"1":"A",...}, "p2":{"1":{"a":"Đ","b":"S",...},...}, "p3":{"1":"12.5",...}, "scoring":{"p1":0.25,"p3":0.5,"max":10}}`
2. **CSV** (legacy Part I only): `A,B,C,D,A,B,...`

---

## 7. Deployment

### Docker Stack (docker-compose.yml)
```yaml
services:
  db:      postgres:16-alpine (data persisted in pgdata volume)
  web:     Python 3.12 + OpenCV + PyTorch CPU + Gunicorn (2 workers, timeout 300s)
  nginx:   Alpine + SSL termination (Let's Encrypt certs)
```

### Dockerfile Layers
1. `python:3.12-slim-bookworm`
2. System deps: OpenCV runtime, Tesseract OCR (vie), image codecs
3. PyTorch CPU-only wheel (~150MB, from pytorch.org/whl/cpu)
4. ONNX Runtime
5. `requirements.txt` (Django, DRF, opencv-python, etc.)
6. App code
7. `collectstatic`
8. CMD: `migrate + gunicorn`

### Auto-Deploy (GitHub Actions)
```
Push to main → .github/workflows/deploy.yml
  → SSH into VM (appleboy/ssh-action)
  → cd ~/chamdiembaithiweb
  → git pull origin main
  → docker compose build
  → docker compose up -d
  → docker image prune -f
```

### SSL/HTTPS
- Certificates: Let's Encrypt via certbot
- Auto-renewal: certbot renew (cron on VM)
- Nginx: HTTP→HTTPS redirect on port 80, SSL on 443
- Django: CSRF_TRUSTED_ORIGINS, SECURE_SSL_REDIRECT, HSTS

### Environment Variables (on VM)
```
DJANGO_SECRET_KEY=<secret>
POSTGRES_DB=gradeflow
POSTGRES_USER=gradeflow
POSTGRES_PASSWORD=<secret>
ALLOWED_HOSTS=gradefloww.duckdns.org
CSRF_TRUSTED_ORIGINS=https://gradefloww.duckdns.org
HYBRID_CNN_ENABLE=1
```

---

## 8. Key Design Decisions

### Tại sao dùng OpenCV trên Flutter (device-side)?
- **Realtime feedback**: User thấy markers detected (xanh) trước khi chụp
- **Smart crop**: Crop chính xác theo marker positions thay vì % cố định
- **Reduce backend load**: Ảnh đã crop gọn → backend xử lý nhanh hơn

### Tại sao có 3 detection methods trên backend?
- **Method A (corner_markers)**: Đáng tin cậy nhất (~53 score) — luôn hoạt động
- **Method B (paper_contour)**: Nhanh nhưng kém chính xác
- **Method C (paper+markers)**: Chính xác nhất (~65+ score) nhưng cần markers rõ
- Fallback chain: C → A → B (robust cho mọi điều kiện)

### Tại sao multi-preprocess retry?
- Phone cameras có lighting rất khác nhau (nắng, bóng, đèn vàng)
- FAST mode đủ cho scan/ảnh tốt (80% cases)
- ROBUST/PHONE mode cứu ảnh xấu (20% cases)
- Auto-select: so sánh confidence scores, giữ mode tốt nhất

### QM 2025 Template đặc biệt gì?
- Markers INSET 4-5% từ mép giấy (không ở góc giấy!)
- 4 markers là hình vuông đen cùng kích thước (in sẵn trên phiếu)
- Phải search ROI centered tại expected position (inset) chứ không phải paper corner

### Text Erasure 3-layer protection
- Vấn đề: chữ in A, B, C, D trên phiếu giống bubble tô đen
- Layer 1: Xóa trắng vùng text, BẢO VỆ bubble bằng punch-holes (circle mask)
- Layer 2: Morphological opening loại nét mảnh < 3px
- Layer 3: Tô đen vùng text trên threshold image (safety net)

---

## 9. Troubleshooting

### Camera detection không nhận markers
1. Check lighting — markers phải tối hơn nền rõ ràng
2. Check distance — markers 6-50px trên 640px-wide image
3. Tăng threshold range hoặc giảm minSide
4. Check size consistency threshold (hiện maxDev > 2.0)

### Backend detection fallback về corner_markers
1. Check logs: `docker compose logs web --tail 200 | grep "paper+markers\|PICK\|method="`
2. Xem có `size inconsistent` không → markers detected nhưng kích thước khác nhau
3. Xem ROI search logs → markers có nằm trong vùng search không
4. Adjust INSET_RATIO (default 0.05) nếu template khác

### Ảnh warped bị lệch bubble grid
1. Check `Grid alignment: X/Y bubbles matched (Z%)`
2. Nếu <30% → warp sai → engine tự retry method khác
3. Nếu vẫn sai → check template JSON coordinates

### Build APK lỗi
1. `flutter clean && flutter pub get` — reset cache
2. Check Java version = 17 (`java -version`)
3. Check Android SDK (`flutter doctor`)
4. `opencv_dart` cần NDK — check `flutter doctor -v` cho NDK path

### Docker build lỗi
1. Check disk space: `df -h` (PyTorch cần ~2GB)
2. Check `.dockerignore` (exclude certbot/, node_modules/, media/)
3. Check logs: `docker compose build --no-cache 2>&1 | tail -50`
