---
description: APK reverse engineering — analyze structure, find key logic, compare with Azota/TNMaker
---

# APK Reverse Engineering — Phân tích APK Azota/TNMaker

## 1. Tools cần thiết

```bash
# 1. jadx — Decompile APK → Java code (nhất thiết)
# Download: https://github.com/skylot/jadx/releases
# Windows: jadx-1.4.7.zip → unzip → add to PATH

# 2. apktool — Decompile APK → smali + resources (tùy chọn)
# Download: https://ibotpeaches.github.io/Apktool/

# 3. flutter-apk-decompiler — Flutter APK → Dart source (chỉ cho Flutter apps)
pip install flutter-apk-decompiler

# 4. aapt (Android Asset Packaging Tool) — Extract resources
# Có sẵn trong Android SDK: $ANDROID_HOME/build-tools/*/aapt

# 5. strings — Extract strings từ binary (Linux/Mac) hoặc grep (Windows)
```

---

## 2. Quy trình phân tích APK

### Step 1: Decompile APK bằng jadx

```bash
# Decompile APK
jadx <apk_file>.apk -d <output_dir>

# Ví dụ:
jadx azota_latest.apk -d jadx_azota
jadx tnmaker_latest.apk -d jadx_tnmaker

# Output structure:
# <output_dir>/
# ├── sources/          # Java source code (decompiled)
# ├── resources/       # Android resources (XML, assets)
# ├── lib/             # Native libraries (.so)
# └── root/            # APK manifest, certificates
```

### Step 2: Xem cấu trúc APK

```bash
# Xem manifest (AndroidManifest.xml)
cat <output_dir>/AndroidManifest.xml

# Xem package name
grep package= <output_dir>/AndroidManifest.xml

# Xem permissions
grep permission <output_dir>/AndroidManifest.xml

# Xem activities
grep activity <output_dir>/AndroidManifest.xml
```

**Key info cần tìm:**
- **Package name**: `com.azota.app`, `com.tnmaker.app`, etc.
- **Main Activity**: Activity có `android.intent.action.MAIN`
- **Permissions**: CAMERA, INTERNET, STORAGE
- **UsesCleartextTraffic**: Cho phép HTTP không SSL

### Step 3: Phân tích Java code (cho native Android apps)

```bash
# Xem MainActivity (entry point)
cat <output_dir>/sources/com/azota/app/MainActivity.java

# Tìm key classes bằng pattern:
# - Camera: *Camera*, *Scanner*, *Capture*
# - Detection: *Detector*, *Recognition*, *OCR*
# - API: *Api*, *Service*, *Network*
# - OMR: *Omr*, *Bubble*, *Answer*

# Tìm trong sources/
find <output_dir>/sources -name "*.java" | xargs grep -l "camera"
find <output_dir>/sources -name "*.java" | xargs grep -l "opencv"
find <output_dir>/sources -name "*.java" | xargs grep -l "http\|api\|endpoint"
```

**Key classes thường gặp:**
```
MainActivity              — Entry point
CameraActivity            — Camera preview
ImageProcessor            — Image processing
BubbleDetector            — Bubble detection
ApiService                — HTTP calls
AuthService               — Login/auth
```

### Step 4: Phân tích Flutter APK (nếu là Flutter)

```bash
# Kiểm tra có phải Flutter không:
# - Check lib/ có flutter.so không
# - Check assets/flutter_assets/kernel_blob.bin (Flutter compiled code)

# Decompile bằng flutter-apk-decompiler
flutter-apk-decompiler <apk_file>.apk -o flutter_decompiled

# Output:
# flutter_decompiled/
# ├── lib/              # Dart source (obfuscated nhưng readable)
# ├── assets/           # flutter_assets/
# ├── android/          # Android native code
# └── ios/              # iOS native code

# Xem Dart code
cat flutter_decompiled/lib/main.dart
find flutter_decompiled/lib -name "*.dart" | head -20
```

**Flutter code thường obfuscated:**
- Class names: `A`, `B`, `C`, `D`...
- Method names: `a()`, `b()`, `c()`...
- Nhưng logic vẫn đọc được, chỉ khó hiểu hơn

### Step 5: Tìm API endpoints

**Trong Java code:**
```bash
# Tìm URL patterns
grep -r "http://" <output_dir>/sources
grep -r "https://" <output_dir>/sources
grep -r "api/" <output_dir>/sources
grep -r "endpoint" <output_dir>/sources

# Tìm base URL
grep -r "baseUrl\|BASE_URL\|API_URL" <output_dir>/sources
```

**Trong Flutter code:**
```bash
# Tìm trong Dart files
grep -r "http://" flutter_decompiled/lib
grep -r "https://" flutter_decompiled/lib
grep -r "api/" flutter_decompiled/lib
```

**Common patterns:**
```
Azota: https://azota.vn/api/
TNMaker: https://tnmaker.vn/api/
GradeFlow: https://gradefloww.duckdns.org/api/v1/
```

### Step 6: Tìm camera detection logic

**Trong Java code:**
```bash
# Tìm camera-related classes
find <output_dir>/sources -name "*.java" | xargs grep -l "Camera\|SurfaceView\|Preview"

# Tìm OpenCV (nếu dùng OpenCV)
find <output_dir>/sources -name "*.java" | xargs grep -l "opencv\|Mat\|Imgproc"

# Tìm ML Kit (nếu dùng Google ML Kit)
find <output_dir>/sources -name "*.java" | xargs grep -l "mlkit\|FirebaseVision\|DocumentScanner"
```

**Trong Flutter code:**
```bash
# Tìm camera packages
grep -r "camera\|opencv_dart\|google_mlkit" flutter_decompiled/lib

# Tìm detection logic
grep -r "detect\|marker\|corner\|contour" flutter_decompiled/lib
```

**Key detection patterns (Azota-style):**
```
1. Guide frame overlay (4 L-brackets)
2. Real-time marker detection (black squares near corners)
3. Auto-capture when 4/4 markers stable
4. Smart crop using marker positions
```

### Step 7: Tìm OMR detection logic

**Trong Java code:**
```bash
# Tìm OMR-related
find <output_dir>/sources -name "*.java" | xargs grep -l "omr\|bubble\|answer\|grade"

# Tìm threshold logic
find <output_dir>/sources -name "*.java" | xargs grep -l "threshold\|binarize"
```

**Trong Flutter code:**
```bash
# Tìm OMR logic
grep -r "bubble\|answer\|grade" flutter_decompiled/lib
grep -r "threshold\|contour" flutter_decompiled/lib
```

**Key OMR patterns:**
```
1. Paper corner detection (4 markers)
2. Perspective transform (warp to rectangle)
3. Bubble grid extraction
4. Fill ratio calculation (ink density)
5. Answer comparison with key
```

### Step 8: Extract strings (tìm API keys, secrets)

```bash
# Extract strings từ native libraries (lib/)
strings <output_dir>/lib/*.so | grep -i "api\|key\|token\|secret"

# Extract từ Java files
find <output_dir>/sources -name "*.java" | xargs strings | grep -i "api\|key\|token\|secret"

# Extract từ assets
strings <output_dir>/assets/* | grep -i "api\|key\|token\|secret"
```

---

## 3. So sánh Azota vs TNMaker vs GradeFlow

### Azota App Analysis

**Tech Stack (từ decompile):**
- Native Android (Java/Kotlin)
- OpenCV cho image processing
- Camera2 API cho camera preview
- Retrofit cho HTTP calls

**Detection Logic (từ code analysis):**
```
1. Camera preview với guide frame overlay
2. Real-time edge detection (Canny)
3. Find 4 paper corners (largest contour)
4. Perspective transform
5. Extract bubble regions
6. Threshold + morphological cleaning
7. Fill ratio calculation
8. Upload image + detected answers to server
```

**API Endpoints (từ strings):**
```
https://azota.vn/api/v1/auth/login
https://azota.vn/api/v1/exam/upload
https://azota.vn/api/v1/grade/process
```

### TNMaker App Analysis

**Tech Stack:**
- Native Android (Java/Kotlin)
- Custom image processing (không OpenCV)
- CameraX API
- OkHttp cho HTTP calls

**Detection Logic:**
```
1. Camera preview với guide frame
2. Paper edge detection (gradient-based)
3. 4-corner extraction
4. Warp + deskew
5. Bubble grid extraction (template-based)
6. Local grading (client-side)
7. Upload results only
```

**Key Difference:**
- TNMaker grades locally (client-side)
- Azota grades on server (upload image)

### GradeFlow App Analysis

**Tech Stack:**
- Flutter (Dart)
- opencv_dart cho on-device marker detection
- camera package cho camera preview
- HTTP package cho API calls

**Detection Logic:**
```
Flutter (device-side):
  1. Camera preview + Azota-style overlay
  2. OpenCV marker detection (7 thresholds)
  3. Smart crop using marker positions
  4. Upload cropped image to server

Backend (server-side):
  5. Paper corner detection (3 methods)
  6. Template-aware marker detection (QM 2025)
  7. Warp + preprocess
  8. Hybrid OpenCV+CNN bubble detection
  9. MOET scoring
  10. Return results
```

---

## 4. Checklist phân tích APK mới

```
□ Download APK (APKPure, APKMirror, hoặc pull từ device)
□ Decompile bằng jadx: jadx <apk>.apk -d <output>
□ Xem AndroidManifest.xml → package name, permissions, activities
□ Check có phải Flutter không (flutter.so, kernel_blob.bin)
□ Nếu Flutter: flutter-apk-decompiler <apk> -o <output>
□ Tìm API endpoints (grep http://, https://, api/)
□ Tìm camera detection logic (grep Camera, opencv, detect)
□ Tìm OMR logic (grep bubble, answer, grade, threshold)
□ Extract strings để tìm secrets (strings lib/*.so)
□ Xem MainActivity để hiểu entry point
□ So sánh với Azota/TNMaker patterns
□ Document key findings
```

---

## 5. Common patterns tìm key logic

### Camera Detection
```
Keywords: camera, preview, surface, capture, scan
Classes: CameraActivity, ScannerActivity, CameraXFragment
Methods: onPreviewFrame, processFrame, detectCorners
```

### Marker/Corner Detection
```
Keywords: marker, corner, contour, edge, paper, warp
Classes: MarkerDetector, CornerFinder, PaperDetector
Methods: findContours, detectCorners, warpPerspective
```

### Bubble Detection
```
Keywords: bubble, circle, fill, ratio, threshold
Classes: BubbleDetector, CircleDetector, FillRatioCalculator
Methods: calculateFillRatio, isFilled, thresholdImage
```

### API Calls
```
Keywords: api, endpoint, http, upload, login, grade
Classes: ApiService, ApiClient, NetworkService
Methods: uploadImage, login, getExam, submitGrade
```

---

## 6. Tools script (automation)

```bash
#!/bin/bash
# apk_analyze.sh — Quick APK analysis script

APK=$1
OUTPUT=${APK%.apk}_decompiled

echo "=== APK Analysis: $APK ==="

# Decompile
echo "[1] Decomcompiling with jadx..."
jadx "$APK" -d "$OUTPUT"

# Manifest
echo "[2] Extracting manifest info..."
grep package= "$OUTPUT/AndroidManifest.xml"
grep permission "$OUTPUT/AndroidManifest.xml" | head -10
grep activity "$OUTPUT/AndroidManifest.xml" | grep MAIN

# Check Flutter
echo "[3] Checking if Flutter app..."
if [ -f "$OUTPUT/lib/arm64-v8a/libflutter.so" ]; then
    echo "→ Flutter app detected"
    flutter-apk-decompiler "$APK" -o "${OUTPUT}_flutter"
fi

# Find API endpoints
echo "[4] Finding API endpoints..."
grep -r "http://" "$OUTPUT/sources" | head -5
grep -r "https://" "$OUTPUT/sources" | head -5

# Find camera/detection
echo "[5] Finding camera/detection classes..."
find "$OUTPUT/sources" -name "*.java" | xargs grep -l "Camera\|opencv" | head -5

echo "[6] Done. Output: $OUTPUT"
```

---

## 7. Lưu ý pháp lý

⚠️ **Reverse Engineering có thể vi phạm:**
- Terms of Service của app
- Copyright laws (nếu phân phối code đã decompile)
- DMCA (tại Mỹ)

**Quy định an toàn:**
- Chỉ phân tích cho mục đích học tập/interoperability
- Không phân phối code đã decompile
- Không sử dụng để clone app (vi phạm IP)
- Check license của app trước khi decompile

---

## 8. Ví dụ phân tích Azota APK (tóm tắt)

```bash
# 1. Download Azota APK từ APKPure
wget https://apkpure.com/azota-app/com.azota.app/download

# 2. Decompile
jadx azota_latest.apk -d jadx_azota

# 3. Xem manifest
cat jadx_azota/AndroidManifest.xml
# → Package: com.azota.app
# → Permissions: CAMERA, INTERNET, READ_EXTERNAL_STORAGE
# → Main Activity: com.azota.app.ui.MainActivity

# 4. Tìm camera
find jadx_azota/sources -name "*.java" | xargs grep -l "Camera"
# → com.azota.app.camera.CameraActivity
# → com.azota.app.camera.PreviewCallback

# 5. Tìm API
grep -r "https://" jadx_azota/sources
# → https://azota.vn/api/v1/
# → https://azota.vn/api/v1/auth/login
# → https://azota.vn/api/v1/exam/upload

# 6. Tìm detection logic
find jadx_azota/sources -name "*.java" | xargs grep -l "opencv\|Mat"
# → com.azota.app.omr.EdgeDetector
# → com.azota.app.omr.BubbleDetector
# → com.azota.app.omr.PerspectiveTransform

# 7. Document findings
```

**Key findings:**
- Azota dùng OpenCV cho image processing
- Server-side grading (upload image, server process)
- API base: https://azota.vn/api/v1/
- Detection: edge detection → corner finding → warp → bubble extraction
