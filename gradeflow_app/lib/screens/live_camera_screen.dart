import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

// ═══════════════════════════════════════════════════════════════════
//  Azota-style Live Camera with guide frame overlay
//
//  Key constants (from Azota decompile analysis):
//    ratioDefault  = 0.69  (paper w/h ≈ A4)
//    markPercent   = 0.06  (corner bracket arm = 6% of screen width)
//    framePercent  = 0.88  (guide frame = 88% of screen width)
//
//  Flow:
//    1. Show guide frame with 4 gray L-brackets (always visible)
//    2. Camera streams frames → OpenCV detects dark square markers
//    3. Detected corners turn GREEN on the overlay
//    4. All 4 detected + stable 2s → auto-capture
//    5. User confirms or retries
// ═══════════════════════════════════════════════════════════════════

// ─── Azota overlay constants ────────────────────────────────────
const double _kRatioDefault = 0.69;   // paper width/height (≈ A4)
const double _kFramePercent = 0.88;   // guide frame width as % of screen
const double _kMarkPercent  = 0.06;   // L-bracket arm length as % of screen width
const double _kStrokeWidth  = 3.0;    // base stroke width (dp)
const Color  _kColorGreen   = Color(0xFF00E676); // detected corner
const Color  _kColorGuide   = Color(0x99FFFFFF);  // undetected guide bracket
const Color  _kColorDim     = Color(0x88000000);  // dim outside guide frame
const int    _kStableMs     = 2000;   // stable duration before auto-capture
const double _kCropPadding  = 0.05;   // 5% extra margin around guide frame when cropping

class CornerMarker {
  final int quadrant; // 0=TL 1=TR 2=BL 3=BR
  final Rect rect;
  const CornerMarker(this.quadrant, this.rect);
}

class _MarkerCandidate {
  final Rect rect;
  final double score;
  const _MarkerCandidate(this.rect, this.score);
}

class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({super.key});
  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _ctr;
  bool _ready = false;
  bool _busy = false;
  bool _error = false;
  String _errorMsg = '';
  bool _captured = false;
  Uint8List? _capturedBytes;

  List<CornerMarker> _markers = [];
  int _stable = 0;
  DateTime? _stableStart;
  int _fps = 0;
  int _frameCnt = 0;
  DateTime _lastFps = DateTime.now();

  Size? _imgSize;

  // [UnT-STYLE] Touch coordinate debug overlay
  double _touchX = 0, _touchY = 0;
  double _touchPrs = 0, _touchSize = 0;
  int _touchPointers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctr?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ctr == null || !_ctr!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) _ctr?.dispose();
    else if (state == AppLifecycleState.resumed) _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() { _error = true; _errorMsg = 'Không tìm thấy camera'; });
        return;
      }
      final cam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      _ctr = CameraController(cam, ResolutionPreset.veryHigh,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await _ctr!.initialize();
      try { await _ctr!.setFocusMode(FocusMode.auto); } catch (_) {}
      if (mounted) {
        setState(() => _ready = true);
        await _ctr!.startImageStream(_processFrame);
      }
    } catch (e) {
      if (mounted) setState(() { _error = true; _errorMsg = '$e'; });
    }
  }

  // ─── Frame processing ──────────────────────────────────────────
  void _processFrame(CameraImage image) {
    if (_busy || !mounted || _captured) return;
    _busy = true;

    _frameCnt++;
    final now = DateTime.now();
    if (now.difference(_lastFps).inMilliseconds >= 1000) {
      _fps = _frameCnt; _frameCnt = 0; _lastFps = now;
    }

    try {
      final sensorW = image.width;
      final sensorH = image.height;

      final yPlane = image.planes[0];
      final stride = yPlane.bytesPerRow;
      Uint8List gray;
      if (stride == sensorW) {
        gray = Uint8List.fromList(yPlane.bytes);
      } else {
        gray = Uint8List(sensorW * sensorH);
        for (int y = 0; y < sensorH; y++) {
          gray.setRange(y * sensorW, y * sensorW + sensorW,
              yPlane.bytes, y * stride);
        }
      }

      // Sensor captures landscape; rotate to portrait for detection
      final sensorMat = cv.Mat.fromList(
          sensorH, sensorW, cv.MatType.CV_8UC1, gray);
      final mat = cv.rotate(sensorMat, cv.ROTATE_90_CLOCKWISE);
      sensorMat.dispose();

      final w = mat.cols;
      final h = mat.rows;
      _imgSize = Size(w.toDouble(), h.toDouble());

      final corners = _detect(mat, w, h);
      mat.dispose();

      if (mounted) {
        setState(() {
          _markers = corners;
          if (corners.length == 4) {
            _stable++;
            _stableStart ??= DateTime.now();
            final elapsed = DateTime.now().difference(_stableStart!).inMilliseconds;
            if (elapsed >= _kStableMs) _autoCapture();
          } else {
            _stable = 0;
            _stableStart = null;
          }
        });
      }
    } catch (e) { debugPrint('Frame: $e'); }
    _busy = false;
  }

  // ─── Crop image to guide frame region ──────────────────────
  //  If markers were detected, crop to marker bounding box + padding.
  //  Otherwise, fall back to guide frame percentage.
  Uint8List _cropToGuideFrame(Uint8List jpegBytes) {
    final img = cv.imdecode(jpegBytes, cv.IMREAD_COLOR);

    final imgW = img.cols.toDouble();
    final imgH = img.rows.toDouble();

    int x1, y1, x2, y2;

    // If we have 4 detected markers, use their bounding box
    if (_markers.length == 4) {
      final allLeft = _markers.map((m) => m.rect.left).reduce(math.min);
      final allTop = _markers.map((m) => m.rect.top).reduce(math.min);
      final allRight = _markers.map((m) => m.rect.right).reduce(math.max);
      final allBottom = _markers.map((m) => m.rect.bottom).reduce(math.max);

      // Scale from screen coords back to image coords
      // (markers were detected on 640px-wide image, but crop is on full-res image)
      // Since markers are already in original image coords (scaled back in _detect),
      // we just need to account for the full-res image vs detection image
      final detScale = imgW / 640.0; // detection was on 640px wide
      
      // Add generous padding (8%) to include markers and some margin
      final padX = (allRight - allLeft) * 0.15;
      final padY = (allBottom - allTop) * 0.15;

      x1 = (allLeft * detScale - padX).clamp(0, imgW).toInt();
      y1 = (allTop * detScale - padY).clamp(0, imgH).toInt();
      x2 = (allRight * detScale + padX).clamp(0, imgW).toInt();
      y2 = (allBottom * detScale + padY).clamp(0, imgH).toInt();
    } else {
      // Fallback: guide frame rect (same math as overlay painter)
      final frameW = imgW * _kFramePercent;
      final frameH = frameW / _kRatioDefault;
      final frameX = (imgW - frameW) / 2;
      final frameY = (imgH - frameH) / 2;

      final padX = frameW * _kCropPadding;
      final padY = frameH * _kCropPadding;

      x1 = (frameX - padX).clamp(0, imgW).toInt();
      y1 = (frameY - padY).clamp(0, imgH).toInt();
      x2 = (frameX + frameW + padX).clamp(0, imgW).toInt();
      y2 = (frameY + frameH + padY).clamp(0, imgH).toInt();
    }

    final roi = img.region(cv.Rect(x1, y1, x2 - x1, y2 - y1));
    final (success, encoded) = cv.imencode('.jpg', roi);
    img.dispose();

    if (success) {
      return Uint8List.fromList(encoded);
    }
    return jpegBytes; // fallback: return original if encode fails
  }

  Future<void> _autoCapture() async {
    if (_captured) return;
    _captured = true;
    HapticFeedback.mediumImpact();
    try {
      await _ctr!.stopImageStream();
      final file = await _ctr!.takePicture();
      final bytes = await file.readAsBytes();
      final cropped = _cropToGuideFrame(bytes);
      if (mounted) setState(() => _capturedBytes = cropped);
    } catch (e) {
      debugPrint('Capture: $e');
      if (mounted) {
        setState(() { _captured = false; _stableStart = null; _stable = 0; });
        try { await _ctr!.startImageStream(_processFrame); } catch (_) {}
      }
    }
  }

  void _reset() {
    setState(() {
      _captured = false; _capturedBytes = null;
      _stable = 0; _stableStart = null; _markers = [];
    });
    try { _ctr!.startImageStream(_processFrame); } catch (_) {}
  }

  Future<void> _manualCapture() async {
    if (_captured) return;
    _captured = true;
    HapticFeedback.lightImpact();
    try {
      await _ctr!.stopImageStream();
      final file = await _ctr!.takePicture();
      final bytes = await file.readAsBytes();
      final cropped = _cropToGuideFrame(bytes);
      if (mounted) setState(() => _capturedBytes = cropped);
    } catch (e) {
      debugPrint('Manual capture: $e');
      if (mounted) {
        setState(() { _captured = false; });
        try { await _ctr!.startImageStream(_processFrame); } catch (_) {}
      }
    }
  }

  // ─── Full-frame corner detection (Azota-style + UnT retry) ───────
  //  Strategy: simple preprocessing + multiple thresholds + wide area range
  //  Key insight: markers are SOLID BLACK SQUARES — the darkest objects
  //  near image corners. Don't over-process.
  //  [UnT-STYLE] _reDetectPoints: if initial detection fails, retry with
  //  CLAHE preprocessing and different threshold parameters.
  List<CornerMarker> _detect(cv.Mat gray, int w, int h) {
    const targetW = 640;
    final scale = targetW / w;
    final targetH = (h * scale).toInt();
    final small = cv.resize(gray, (targetW, targetH));

    // ── Pass 1: Simple preprocessing (fast path — works 80% of time) ──
    final blurred = cv.gaussianBlur(small, (3, 3), 0);
    var result = _detectPass(blurred, small, scale, targetW, targetH, w, h);
    if (result.length == 4) {
      small.dispose(); blurred.dispose();
      return result;
    }

    // ── Pass 2: [UnT-STYLE] _reDetectPoints — CLAHE + dilate retry ──
    // UnT retries with CLAHE (better than equalizeHist) when initial fails
    final clahe = cv.CLAHE.create(2.0, (8, 8));
    final enhanced = clahe.apply(small);
    clahe.dispose();
    final enhBlurred = cv.gaussianBlur(enhanced, (3, 3), 0);
    result = _detectPass(enhBlurred, enhanced, scale, targetW, targetH, w, h);
    enhanced.dispose(); enhBlurred.dispose();
    if (result.length >= 3) {
      small.dispose(); blurred.dispose();
      return result;
    }

    // ── Pass 3: Dilate + stronger blur (for faint pencil markers) ──
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    final dilated = cv.dilate(small, kernel);
    final dilBlurred = cv.gaussianBlur(dilated, (5, 5), 0);
    result = _detectPass(dilBlurred, dilated, scale, targetW, targetH, w, h);
    kernel.dispose(); dilated.dispose(); dilBlurred.dispose();

    small.dispose(); blurred.dispose();
    return result;
  }

  // ── Single detection pass with given preprocessed image ──
  List<CornerMarker> _detectPass(cv.Mat blurred, cv.Mat source,
      double scale, int targetW, int targetH, int w, int h) {

    // ── Multi-threshold: try many levels to catch markers in any lighting ──
    final thresholds = <cv.Mat>[];
    // Adaptive threshold (good for uneven lighting)
    thresholds.add(cv.adaptiveThreshold(blurred, 255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 25, 10.0));
    // Simple thresholds at multiple levels
    for (final tval in [40.0, 60.0, 80.0, 100.0, 120.0, 140.0]) {
      thresholds.add(cv.threshold(blurred, tval, 255, cv.THRESH_BINARY_INV).$2);
    }

    // ── Marker size constraints (WIDE — camera at distance = tiny markers) ──
    // On 640px image: markers can be 6-50px depending on distance
    final minSide = 6;
    final maxSide = (targetW * 0.08).toInt();  // ~50px
    final minArea = minSide * minSide;  // 36px²
    final maxArea = maxSide * maxSide;  // ~2500px²

    final candidates = <_MarkerCandidate>[];

    for (final thresh in thresholds) {
      final (contours, _) = cv.findContours(
          thresh, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

      for (int j = 0; j < contours.length; j++) {
        final cnt = contours[j];
        final area = cv.contourArea(cnt);
        if (area < minArea || area > maxArea) continue;

        final rect = cv.boundingRect(cnt);
        if (rect.width < minSide || rect.height < minSide) continue;

        // Aspect ratio: markers are roughly square (allow 2:1 for perspective)
        final ratio = rect.width > rect.height
            ? rect.width / rect.height : rect.height / rect.width;
        if (ratio > 2.0) continue;

        // Fill ratio: solid black square
        final rectArea = rect.width * rect.height;
        final extent = area / rectArea;
        if (extent < 0.4) continue;

        // ── Scoring ──
        final squareness = 1.0 - (ratio - 1.0).abs() * 0.3;
        double score = extent * 0.4 + squareness * 0.2;

        // Proximity to image corner (strong signal for OMR markers)
        final cx = (rect.x + rect.width / 2) / targetW;
        final cy = (rect.y + rect.height / 2) / targetH;
        final dTL = math.sqrt(cx * cx + cy * cy);
        final dTR = math.sqrt((1 - cx) * (1 - cx) + cy * cy);
        final dBL = math.sqrt(cx * cx + (1 - cy) * (1 - cy));
        final dBR = math.sqrt((1 - cx) * (1 - cx) + (1 - cy) * (1 - cy));
        final minCornerDist = [dTL, dTR, dBL, dBR].reduce(math.min);
        // Strong bonus for being near a corner (within 30%)
        if (minCornerDist < 0.30) {
          score += 0.5 * (1.0 - minCornerDist / 0.30);
        }

        // Deduplicate
        final scaledRect = Rect.fromLTWH(
          rect.x / scale, rect.y / scale,
          rect.width / scale, rect.height / scale,
        );
        bool isDuplicate = false;
        for (final existing in candidates) {
          final dx = (existing.rect.center.dx - scaledRect.center.dx).abs();
          final dy = (existing.rect.center.dy - scaledRect.center.dy).abs();
          if (dx < 40 && dy < 40) {
            isDuplicate = true;
            if (score > existing.score) {
              candidates.remove(existing);
              candidates.add(_MarkerCandidate(scaledRect, score));
            }
            break;
          }
        }
        if (!isDuplicate) {
          candidates.add(_MarkerCandidate(scaledRect, score));
        }
      }
    }

    // Dispose threshold mats (small/blurred handled by caller _detect)
    for (final t in thresholds) { t.dispose(); }

    if (candidates.length < 4) return [];

    // Sort by score descending, take top candidates
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final topCands = candidates.take(20).toList();

    final midX = w / 2.0, midY = h / 2.0;
    final tls = topCands.where((c) => c.rect.center.dx < midX && c.rect.center.dy < midY).toList();
    final trs = topCands.where((c) => c.rect.center.dx >= midX && c.rect.center.dy < midY).toList();
    final bls = topCands.where((c) => c.rect.center.dx < midX && c.rect.center.dy >= midY).toList();
    final brs = topCands.where((c) => c.rect.center.dx >= midX && c.rect.center.dy >= midY).toList();

    // Pick best candidate per quadrant: weighted by score + proximity to corner
    _MarkerCandidate? pickCorner(List<_MarkerCandidate> cands, double tx, double ty) {
      if (cands.isEmpty) return null;
      cands.sort((a, b) {
        // Combined score: 60% detection score + 40% proximity to expected corner
        final da = math.sqrt(
            (a.rect.center.dx - tx) * (a.rect.center.dx - tx) +
            (a.rect.center.dy - ty) * (a.rect.center.dy - ty));
        final db = math.sqrt(
            (b.rect.center.dx - tx) * (b.rect.center.dx - tx) +
            (b.rect.center.dy - ty) * (b.rect.center.dy - ty));
        final maxDist = math.sqrt(w * w + h * h);
        final scoreA = a.score * 0.6 + (1.0 - da / maxDist) * 0.4;
        final scoreB = b.score * 0.6 + (1.0 - db / maxDist) * 0.4;
        return scoreB.compareTo(scoreA);
      });
      return cands.first;
    }

    final tl = pickCorner(tls, 0, 0);
    final tr = pickCorner(trs, w.toDouble(), 0);
    final bl = pickCorner(bls, 0, h.toDouble());
    final br = pickCorner(brs, w.toDouble(), h.toDouble());

    final out = <CornerMarker>[];
    if (tl != null) out.add(CornerMarker(0, tl.rect));
    if (tr != null) out.add(CornerMarker(1, tr.rect));
    if (bl != null) out.add(CornerMarker(2, bl.rect));
    if (br != null) out.add(CornerMarker(3, br.rect));

    // ── 3-corner fallback: infer missing corner via parallelogram ──
    if (out.length == 3) {
      final have = {for (final m in out) m.quadrant};
      final missing = [0, 1, 2, 3].firstWhere((q) => !have.contains(q));
      final pts = {for (final m in out) m.quadrant: m.rect.center};
      Offset? inferred;
      switch (missing) {
        case 0: inferred = Offset(pts[1]!.dx + pts[2]!.dx - pts[3]!.dx,
                                  pts[1]!.dy + pts[2]!.dy - pts[3]!.dy); break;
        case 1: inferred = Offset(pts[0]!.dx + pts[3]!.dx - pts[2]!.dx,
                                  pts[0]!.dy + pts[3]!.dy - pts[2]!.dy); break;
        case 2: inferred = Offset(pts[0]!.dx + pts[3]!.dx - pts[1]!.dx,
                                  pts[0]!.dy + pts[3]!.dy - pts[1]!.dy); break;
        case 3: inferred = Offset(pts[1]!.dx + pts[2]!.dx - pts[0]!.dx,
                                  pts[1]!.dy + pts[2]!.dy - pts[0]!.dy); break;
      }
      if (inferred != null &&
          inferred.dx > 0 && inferred.dx < w &&
          inferred.dy > 0 && inferred.dy < h) {
        final avgW = out.map((m) => m.rect.width).reduce((a, b) => a + b) / 3;
        final avgH = out.map((m) => m.rect.height).reduce((a, b) => a + b) / 3;
        out.add(CornerMarker(missing, Rect.fromCenter(
          center: inferred, width: avgW, height: avgH,
        )));
      }
    }

    // Size consistency check (very relaxed for phone camera at distance)
    // At distance, perspective makes markers very different sizes
    if (out.length == 4) {
      final areas = out.map((m) => m.rect.width * m.rect.height).toList();
      final avg = areas.reduce((a, b) => a + b) / 4;
      final maxDev = areas.map((a) => (a - avg).abs() / avg).reduce(math.max);
      // Only reject if wildly inconsistent (>3x difference)
      if (maxDev > 2.0) return [];
    }

    return out;
  }

  // ─── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Scaffold(backgroundColor: Colors.black,
        body: Center(child: Text(_errorMsg,
            style: const TextStyle(color: Colors.white70, fontSize: 16))));
    }
    if (!_ready || _ctr == null || !_ctr!.value.isInitialized) {
      return Scaffold(backgroundColor: Colors.black,
        body: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _kColorGreen),
            const SizedBox(height: 16),
            Text('Khởi tạo camera...',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
          ],
        )));
    }
    if (_captured && _capturedBytes != null) return _buildResult();

    final detectedQuadrants = {for (final m in _markers) m.quadrant};
    final allDetected = _markers.length == 4;
    final progress = _stableStart != null
        ? math.min(1.0, DateTime.now().difference(_stableStart!).inMilliseconds / _kStableMs)
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          Center(child: CameraPreview(_ctr!)),

          // UnT-style overlay: filled squares at 4 corners + touch listener
          Listener(
            onPointerDown: (e) => setState(() {
              _touchX = e.position.dx;
              _touchY = e.position.dy;
              _touchPrs = e.pressure;
              _touchSize = e.size;
              _touchPointers = e.buttons;
            }),
            onPointerMove: (e) => setState(() {
              _touchX = e.position.dx;
              _touchY = e.position.dy;
              _touchPrs = e.pressure;
              _touchSize = e.size;
            }),
            child: CustomPaint(
              size: Size.infinite,
              painter: _AzotaOverlayPainter(
                markers: _markers,
                imageSize: _imgSize,
                detectedQuadrants: detectedQuadrants,
              ),
            ),
          ),

          // [UnT-STYLE] Touch coordinate debug bar (top)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black.withOpacity(0.6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: SafeArea(
                bottom: false,
                child: Text(
                  'P: ${_markers.length}/4  '
                  'X: ${_touchX.toStringAsFixed(1)}  '
                  'Y: ${_touchY.toStringAsFixed(1)}  '
                  'Prs: ${_touchPrs.toStringAsFixed(1)}  '
                  'Size: ${_touchSize.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),

          // Top bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    // Corner count indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: allDetected
                            ? _kColorGreen.withOpacity(0.25)
                            : Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: allDetected ? _kColorGreen : Colors.white30,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int q = 0; q < 4; q++) ...[
                            if (q > 0) const SizedBox(width: 4),
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: detectedQuadrants.contains(q)
                                    ? _kColorGreen
                                    : Colors.white30,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status text
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        _stableStart != null
                            ? 'Giữ yên... ${math.max(0.0, (_kStableMs - DateTime.now().difference(_stableStart!).inMilliseconds) / 1000).toStringAsFixed(1)}s'
                            : allDetected
                                ? 'Đã nhận diện phiếu!'
                                : 'Hướng camera vào phiếu (${_markers.length}/4)',
                        style: TextStyle(
                          color: allDetected ? _kColorGreen : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Capture button with progress ring
                    GestureDetector(
                      onTap: _manualCapture,
                      child: SizedBox(
                        width: 72, height: 72,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Progress ring (auto-capture countdown)
                            if (progress > 0)
                              SizedBox(
                                width: 72, height: 72,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 3,
                                  color: _kColorGreen,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                            // Capture button
                            Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: allDetected ? _kColorGreen : Colors.white,
                                  width: 3,
                                ),
                                color: allDetected
                                    ? _kColorGreen.withOpacity(0.15)
                                    : Colors.white10,
                              ),
                              child: Icon(
                                allDetected ? Icons.check : Icons.camera_alt,
                                color: allDetected ? _kColorGreen : Colors.white,
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Image.memory(_capturedBytes!, fit: BoxFit.contain)),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.refresh, size: 20),
                      label: const Text('Chụp lại'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(_capturedBytes),
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Chấm điểm'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kColorGreen,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Back button on result
          Positioned(
            top: 0, left: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
                onPressed: _reset,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  UnT-style overlay painter
//
//  Based on UnT Dạy Học decompile analysis:
//    1. 4 filled squares at camera corners (no dim overlay)
//    2. Squares turn GREEN when marker detected in that quadrant
//    3. Squares stay dark/translucent when not detected
//    4. When detected, also draw green border around detected marker rect
// ═══════════════════════════════════════════════════════════════════

class _AzotaOverlayPainter extends CustomPainter {
  final List<CornerMarker> markers;
  final Size? imageSize;
  final Set<int> detectedQuadrants;

  _AzotaOverlayPainter({
    required this.markers,
    required this.imageSize,
    required this.detectedQuadrants,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screenW = size.width;
    final screenH = size.height;

    // ── UnT-style: filled squares at 4 corners of camera view ──
    // Square size scales with screen width (~10% of screen width)
    final sqSize = screenW * 0.10;
    final margin = 4.0; // small margin from screen edges

    final corners = [
      (0, Rect.fromLTWH(margin, margin, sqSize, sqSize)),                                       // TL
      (1, Rect.fromLTWH(screenW - sqSize - margin, margin, sqSize, sqSize)),                     // TR
      (2, Rect.fromLTWH(margin, screenH - sqSize - margin, sqSize, sqSize)),                     // BL
      (3, Rect.fromLTWH(screenW - sqSize - margin, screenH - sqSize - margin, sqSize, sqSize)),  // BR
    ];

    for (final (q, rect) in corners) {
      final detected = detectedQuadrants.contains(q);

      // Filled square background
      final fillPaint = Paint()
        ..color = detected
            ? _kColorGreen.withOpacity(0.35)
            : Colors.black.withOpacity(0.25)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      // Square border (thick, green if detected)
      final borderPaint = Paint()
        ..color = detected ? _kColorGreen : Colors.white.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = detected ? 3.5 : 2.0;
      canvas.drawRect(rect, borderPaint);
    }

    // ── Draw green highlight around detected marker positions ──
    if (imageSize != null && markers.isNotEmpty) {
      final sx = screenW / imageSize!.width;
      final sy = screenH / imageSize!.height;

      final markerPaint = Paint()
        ..color = _kColorGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      for (final m in markers) {
        // Scale marker rect from image coords to screen coords
        final r = Rect.fromLTWH(
          m.rect.left * sx - 4,
          m.rect.top * sy - 4,
          m.rect.width * sx + 8,
          m.rect.height * sy + 8,
        );
        canvas.drawRect(r, markerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_AzotaOverlayPainter old) =>
      markers != old.markers || detectedQuadrants != old.detectedQuadrants;
}
