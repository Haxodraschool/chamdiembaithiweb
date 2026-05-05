---
description: UnT Dạy Học APK analysis — architecture, detection pipeline, comparison with GradeFlow
---

# UnT Dạy Học — Kết quả phân tích APK

## 1. Package Structure

```
flutter_unt_edu/
├── data/
│   ├── form/
│   │   ├── code_3_digits/     ← Form 3 chữ số SBD (20+ files)
│   │   │   ├── UnT_40_8_6_ABCD_Form.dart
│   │   │   ├── unt_40_8_0_abcd_form.dart
│   │   │   └── ...
│   │   ├── code_4_digits/     ← Form 4 chữ số SBD (7 files)
│   │   │   ├── bgdvN_40_8_6_abcd_4_digits_form.dart  ← PHIẾU BGDVN
│   │   │   └── ...
│   │   ├── paper_form.dart
│   │   └── paper_form_manager.dart    ← Quản lý 28 form templates
│   └── model/
│       ├── iso_scanner.dart           ← ★ Scanner chính (FFI → C++)
│       ├── answer_model.dart
│       ├── paper_result_model.dart
│       └── ...
├── screen/
│   ├── paper_scan_screen.dart         ← Screen scan
│   ├── paper_test_screen.dart
│   └── ...
├── service/
│   ├── paper_service.dart
│   └── scanner_service.dart
└── bloc/
    ├── assignment_data_bloc.dart
    └── submission_list_bloc.dart
```

## 2. Key Classes

| Class | Vai trò |
|-------|---------|
| `IsoScanner` | Scanner chính — gọi FFI → `libffi_opencv_scanner.so` |
| `OpenCvScannerBGDVN` | Scanner riêng cho phiếu BGDVN |
| `PaperFormManager` | Quản lý 28 form templates |
| `DetectionSpeed` | Chế độ nhanh/chậm |
| `PaperScanSettings` | Cài đặt scan |
| `AnswerModel` | Model đáp án |
| `PaperResult` | Kết quả chấm |

## 3. Detection Pipeline (C++ native)

```
Flutter Dart (IsoScanner)
    ↓ FFI call
libffi_opencv_scanner.so (C++)
    ↓
1. rotatePaper()              — Xoay ảnh theo EXIF
2. detectConnersAndCrop()     — ★ TÌM 4 GÓC ★
   ├── _preProcessPaper()     — GaussianBlur + adaptiveThreshold + Canny
   ├── _findContours()        — cv::findContours
   ├── find4Points()          — approxPolyDP + sort4Contour
   ├── _findConnerRect()      — boundingRect
   └── _reDetectPoints()      — ★ RETRY nếu fail (khác params) ★
3. tranformPaperByRects()     — getPerspectiveTransform + warpPerspective
4. detectCircles()            — Tìm bubble
   └── _preProcessCircle()    — Preprocessing RIÊNG cho bubble (CLAHE + dilate)
5. getFeatures()              — Trích xuất features
```

## 4. TFLite Models (classification only)

| Model | Size | Vai trò |
|-------|------|---------|
| `test_paper.tflite` | 131KB | Phân loại: có phiếu không |
| `test_paper_BGDVN.tflite` | 99KB | Phân loại: phiếu BGDVN |

**QUAN TRỌNG**: TFLite KHÔNG dùng cho corner detection — corner detection vẫn là OpenCV C++.

## 5. So sánh UnT vs GradeFlow

| Feature | UnT Dạy Học | GradeFlow |
|---------|------------|-----------|
| Language | Dart + C++ (FFI) | Dart + Python (server) |
| Corner detection | C++ native (fast) | Python OpenCV (server-side) |
| Device-side detection | FFI → libffi_opencv_scanner.so | opencv_dart (Dart bindings) |
| Retry on fail | ✅ `_reDetectPoints()` | ❌ Không có |
| Bubble preprocessing | ✅ `_preProcessCircle()` riêng | ❌ Dùng chung preprocess |
| Point sorting | ✅ `sort4Contour()` chính xác | ⚠️ `order_points()` basic |
| Histogram eq. | CLAHE + dilate | equalizeHist (basic) |
| Form templates | 28 forms (code) | 15+ forms (JSON) |
| TFLite | Classification only | CNN bubble classifier |
| Grading location | Client-side (local) | Server-side (upload) |
| State management | BLoC | Provider |

## 6. Cải tiến cần áp dụng cho GradeFlow

### 6.1. _reDetectPoints() — Retry with different params
UnT retry detect khi fail với params khác (blockSize, C, Canny thresholds).
GradeFlow cần thêm retry logic tương tự cho Flutter-side detection.

### 6.2. _preProcessCircle() — Separate bubble preprocessing
UnT dùng CLAHE + dilate riêng cho bubble detection (khác paper detection).
GradeFlow dùng chung preprocessing cho cả paper + bubble.

### 6.3. sort4Contour() — Better 4-point ordering
UnT sắp xếp 4 contour theo thứ tự: top-left, top-right, bottom-right, bottom-left
bằng cách so sánh centroid positions.

### 6.4. CLAHE thay equalizeHist
UnT dùng CLAHE (Contrast Limited Adaptive Histogram Equalization) cho bubble detection.
CLAHE tốt hơn equalizeHist vì không over-amplify noise.

## 7. Implementation Status (Applied to GradeFlow)

### ✅ 6.1 _reDetectPoints — DONE
- **Backend** (`hi.py:1566-1624`): Added 3 retry configs with CLAHE+dilate+adaptive threshold in `_find_marker_near_corner()`
- **Flutter** (`live_camera_screen.dart:285-327`): Refactored `_detect()` into 3-pass pipeline:
  - Pass 1: Simple blur (fast path)
  - Pass 2: CLAHE enhanced (UnT-style)
  - Pass 3: Dilate + stronger blur (faint markers)

### ✅ 6.2 _preProcessCircle — DONE
- **Backend** (`hi.py:2010-2035`): Added `_preprocess_for_bubbles()` function with CLAHE+dilate+bilateral specifically for bubble detection

### ✅ 6.3 sort4Contour — DONE
- **Backend** (`hi.py:590-635`): Improved `order_points()` with:
  - Method 1: Classic sum/diff (fast, 95% correct)
  - Method 2: Centroid-based fallback for extreme perspective skew
  - Validates all 4 points are unique before returning

### ✅ 6.4 CLAHE — Already implemented
- Backend `_find_corner_markers()` already uses CLAHE (added in earlier session)
- New `_preprocess_for_bubbles()` also uses CLAHE
- Flutter retry pass uses `cv.CLAHE.create()`
