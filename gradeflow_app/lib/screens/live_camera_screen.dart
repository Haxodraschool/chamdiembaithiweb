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
  Uint8List _cropToGuideFrame(Uint8List jpegBytes) {
    final img = cv.imdecode(jpegBytes, cv.IMREAD_COLOR);

    final imgW = img.cols.toDouble();
    final imgH = img.rows.toDouble();

    // Guide frame rect (same math as overlay painter)
    final frameW = imgW * _kFramePercent;
    final frameH = frameW / _kRatioDefault;
    final frameX = (imgW - frameW) / 2;
    final frameY = (imgH - frameH) / 2;

    // Add padding (5%) to avoid cutting corner markers at the edge
    final padX = frameW * _kCropPadding;
    final padY = frameH * _kCropPadding;

    final x1 = (frameX - padX).clamp(0, imgW).toInt();
    final y1 = (frameY - padY).clamp(0, imgH).toInt();
    final x2 = (frameX + frameW + padX).clamp(0, imgW).toInt();
    final y2 = (frameY + frameH + padY).clamp(0, imgH).toInt();

    final roi = img.region(cv.Rect(x1, y1, x2 - x1, y2 - y1));
    final (success, encoded) = cv.imencode('.jpg', roi);
    img.dispose();

    if (success) {
      final result = Uint8List.fromList(encoded);
      return result;
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

  // ─── Full-frame corner detection (Azota-style) ─────────────────
  List<CornerMarker> _detect(cv.Mat gray, int w, int h) {
    const targetW = 640;
    final scale = targetW / w;
    final targetH = (h * scale).toInt();
    final small = cv.resize(gray, (targetW, targetH));

    final enhanced = cv.equalizeHist(small);
    final blurred = cv.gaussianBlur(enhanced, (5, 5), 2.0);
    final thresh = cv.adaptiveThreshold(blurred, 255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 31, 5.0);

    final (contours, hierarchy) = cv.findContours(
        thresh, cv.RETR_TREE, cv.CHAIN_APPROX_SIMPLE);

    final minSide = (targetW * 0.012).toInt();
    final maxSide = (targetW * 0.08).toInt();
    final minArea = minSide * minSide;
    final maxArea = maxSide * maxSide;

    final candidates = <_MarkerCandidate>[];
    for (int j = 0; j < contours.length; j++) {
      final cnt = contours[j];
      final area = cv.contourArea(cnt);
      if (area < minArea || area > maxArea) continue;

      final rect = cv.boundingRect(cnt);
      if (rect.width < minSide || rect.height < minSide) continue;

      final ratio = rect.width > rect.height
          ? rect.width / rect.height : rect.height / rect.width;
      if (ratio > 1.35) continue;

      final peri = cv.arcLength(cnt, true);
      final approx = cv.approxPolyDP(cnt, 0.04 * peri, true);
      final nVertices = approx.length;
      approx.dispose();
      if (nVertices < 4 || nVertices > 8) continue;

      final rectArea = rect.width * rect.height;
      final extent = area / rectArea;
      if (extent < 0.6) continue;

      final sub = thresh.region(rect);
      final nz = cv.countNonZero(sub);
      final solidRatio = nz / rectArea;
      sub.dispose();
      if (solidRatio < 0.4) continue;

      double score = solidRatio + extent * 0.3;
      try {
        if (j < hierarchy.length) {
          final h = hierarchy[j];
          if (h.val3 >= 0) score += 0.2;
        }
      } catch (_) {}

      candidates.add(_MarkerCandidate(
        Rect.fromLTWH(
          rect.x / scale, rect.y / scale,
          rect.width / scale, rect.height / scale,
        ),
        score,
      ));
    }

    small.dispose(); enhanced.dispose(); blurred.dispose(); thresh.dispose();

    if (candidates.length < 4) return [];

    final midX = w / 2.0, midY = h / 2.0;
    final tls = candidates.where((c) => c.rect.center.dx < midX && c.rect.center.dy < midY).toList();
    final trs = candidates.where((c) => c.rect.center.dx >= midX && c.rect.center.dy < midY).toList();
    final bls = candidates.where((c) => c.rect.center.dx < midX && c.rect.center.dy >= midY).toList();
    final brs = candidates.where((c) => c.rect.center.dx >= midX && c.rect.center.dy >= midY).toList();

    _MarkerCandidate? pickCorner(List<_MarkerCandidate> cands, double tx, double ty) {
      if (cands.isEmpty) return null;
      cands.sort((a, b) {
        if ((a.score - b.score).abs() > 0.1) return b.score.compareTo(a.score);
        final da = (a.rect.center.dx - tx) * (a.rect.center.dx - tx) +
            (a.rect.center.dy - ty) * (a.rect.center.dy - ty);
        final db = (b.rect.center.dx - tx) * (b.rect.center.dx - tx) +
            (b.rect.center.dy - ty) * (b.rect.center.dy - ty);
        return da.compareTo(db);
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

    // Size consistency check
    if (out.length == 4) {
      final areas = out.map((m) => m.rect.width * m.rect.height).toList();
      final avg = areas.reduce((a, b) => a + b) / 4;
      final maxDev = areas.map((a) => (a - avg).abs() / avg).reduce(math.max);
      if (maxDev > 0.6) return [];
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

          // Azota-style overlay: dim + guide frame + L-brackets
          CustomPaint(
            size: Size.infinite,
            painter: _AzotaOverlayPainter(
              markers: _markers,
              imageSize: _imgSize,
              detectedQuadrants: detectedQuadrants,
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
//  Azota-style overlay painter
//
//  Always draws:
//    1. Dimmed region outside the guide frame
//    2. 4 L-shaped brackets at guide frame corners (gray when idle)
//  When corners detected:
//    3. Green L-brackets at detected marker positions
//    4. Guide bracket turns green for that quadrant
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

    // ── Guide frame (Azota layout) ──
    final frameW = screenW * _kFramePercent;
    final frameH = frameW / _kRatioDefault;
    final frameX = (screenW - frameW) / 2;
    final frameY = (screenH - frameH) / 2;
    final guideRect = Rect.fromLTWH(frameX, frameY, frameW, frameH);

    // 1. Dim area outside guide frame
    final dimPaint = Paint()..color = _kColorDim;
    // Top
    canvas.drawRect(Rect.fromLTWH(0, 0, screenW, frameY), dimPaint);
    // Bottom
    canvas.drawRect(Rect.fromLTWH(0, frameY + frameH, screenW, screenH - frameY - frameH), dimPaint);
    // Left
    canvas.drawRect(Rect.fromLTWH(0, frameY, frameX, frameH), dimPaint);
    // Right
    canvas.drawRect(Rect.fromLTWH(frameX + frameW, frameY, screenW - frameX - frameW, frameH), dimPaint);

    // 2. Guide frame border (subtle)
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(guideRect, borderPaint);

    // 3. L-brackets at guide frame corners
    final armLen = screenW * _kMarkPercent;
    _drawGuideBrackets(canvas, guideRect, armLen);

    // 4. Green L-brackets at detected marker positions
    if (imageSize != null && markers.isNotEmpty) {
      final sx = screenW / imageSize!.width;
      final sy = screenH / imageSize!.height;
      _drawDetectedBrackets(canvas, sx, sy, armLen);
    }
  }

  void _drawGuideBrackets(Canvas canvas, Rect frame, double armLen) {
    // Draw L-bracket at each guide frame corner
    // Color: green if that quadrant is detected, gray otherwise
    final corners = [
      (0, frame.topLeft),     // TL
      (1, frame.topRight),    // TR
      (2, frame.bottomLeft),  // BL
      (3, frame.bottomRight), // BR
    ];

    for (final (q, pt) in corners) {
      final detected = detectedQuadrants.contains(q);
      final paint = Paint()
        ..color = detected ? _kColorGreen : _kColorGuide
        ..style = PaintingStyle.stroke
        ..strokeWidth = detected ? _kStrokeWidth + 1 : _kStrokeWidth
        ..strokeCap = StrokeCap.round;

      switch (q) {
        case 0: // TL: ╔
          canvas.drawLine(pt, Offset(pt.dx + armLen, pt.dy), paint);
          canvas.drawLine(pt, Offset(pt.dx, pt.dy + armLen), paint);
          break;
        case 1: // TR: ╗
          canvas.drawLine(pt, Offset(pt.dx - armLen, pt.dy), paint);
          canvas.drawLine(pt, Offset(pt.dx, pt.dy + armLen), paint);
          break;
        case 2: // BL: ╚
          canvas.drawLine(pt, Offset(pt.dx + armLen, pt.dy), paint);
          canvas.drawLine(pt, Offset(pt.dx, pt.dy - armLen), paint);
          break;
        case 3: // BR: ╝
          canvas.drawLine(pt, Offset(pt.dx - armLen, pt.dy), paint);
          canvas.drawLine(pt, Offset(pt.dx, pt.dy - armLen), paint);
          break;
      }
    }
  }

  void _drawDetectedBrackets(Canvas canvas, double sx, double sy, double armLen) {
    final paint = Paint()
      ..color = _kColorGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kStrokeWidth
      ..strokeCap = StrokeCap.round;

    for (final m in markers) {
      // Scale marker rect from image coords to screen coords, expand for visibility
      final r = Rect.fromLTWH(
        m.rect.left * sx - 6,
        m.rect.top * sy - 6,
        m.rect.width * sx + 12,
        m.rect.height * sy + 12,
      );
      final arm = math.min(r.width, r.height) * 0.55;

      // L-bracket at all 4 corners of the detected marker rect
      // TL
      canvas.drawLine(Offset(r.left, r.top), Offset(r.left + arm, r.top), paint);
      canvas.drawLine(Offset(r.left, r.top), Offset(r.left, r.top + arm), paint);
      // TR
      canvas.drawLine(Offset(r.right, r.top), Offset(r.right - arm, r.top), paint);
      canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + arm), paint);
      // BL
      canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left + arm, r.bottom), paint);
      canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left, r.bottom - arm), paint);
      // BR
      canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right - arm, r.bottom), paint);
      canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right, r.bottom - arm), paint);
    }
  }

  @override
  bool shouldRepaint(_AzotaOverlayPainter old) =>
      markers != old.markers || detectedQuadrants != old.detectedQuadrants;
}
