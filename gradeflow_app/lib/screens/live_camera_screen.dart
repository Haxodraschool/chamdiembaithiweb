import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

// ═══════════════════════════════════════════════════════════════════
//  TNMaker-faithful Live Camera (Landscape)
//
//  Decompiled from MainActivity.java:
//    onCameraViewStarted → compute p0, q0, s0, squareSide, T0[], U0[]
//    onCameraFrame → L() threshold corners + K() filter squares
//    When t0==4 → M() warp + grade → disableView
//
//  Visual: gray threshold squares at TNMaker positions + red markers
//  Auto-capture after 2s stable 4-corner detection
// ═══════════════════════════════════════════════════════════════════

class CornerMarker {
  final int quadrant;
  final Rect rect;
  const CornerMarker(this.quadrant, this.rect);
}

class _MarkerCandidate {
  final Rect rect;
  final double score; // Higher = more likely a real marker
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
  int _sensorOri = 0;

  // TNMaker layout params (computed from frame dimensions)
  int _myW = 0;   // p0: paper width
  int _myH = 0;   // q0: paper height
  int _startY = 0; // s0: vertical offset
  int _sqSide = 0; // squareSide = q0/4
  int _paperW = 0; // i7 = (q0*9)/8
  int _y34 = 0;    // i6 = (q0*3)/4

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
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
      _sensorOri = cam.sensorOrientation;
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

  // ─── TNMaker onCameraViewStarted: compute layout params ────────
  void _computeLayout(int frameW, int frameH) {
    // TNMaker: mRatio = width/height
    final ratio = frameW / frameH;
    if (ratio >= 16 / 9) {
      _myH = frameH;
      _myW = (frameH * 16) ~/ 9;
    } else {
      _myW = frameW;
      _myH = (frameW * 9) ~/ 16;
    }
    if (ratio >= 16 / 9) {
      _startY = 0;
    } else {
      _startY = (frameH - _myH) ~/ 2;
    }
    _sqSide = _myH ~/ 4;
    _y34 = (_myH * 3) ~/ 4;
    _paperW = (_myH * 9) ~/ 8;
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

      // After rotation: width=sensorH, height=sensorW
      final w = mat.cols;
      final h = mat.rows;
      _imgSize = Size(w.toDouble(), h.toDouble());
      if (_sqSide == 0) {
        debugPrint('OMR portrait frame: ${w}x$h (sensor: ${sensorW}x$sensorH)');
      }

      final corners = _detect(mat, w, h);
      mat.dispose();

      if (mounted) {
        setState(() {
          _markers = corners;
          if (corners.length == 4) {
            _stable++;
            _stableStart ??= DateTime.now();
            final elapsed = DateTime.now().difference(_stableStart!).inMilliseconds;
            if (elapsed >= 2000) _autoCapture();
          } else {
            _stable = 0;
            _stableStart = null;
          }
        });
      }
    } catch (e) { debugPrint('Frame: $e'); }
    _busy = false;
  }

  Future<void> _autoCapture() async {
    if (_captured) return;
    _captured = true;
    try {
      await _ctr!.stopImageStream();
      final file = await _ctr!.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _capturedBytes = bytes);
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

  /// Manual capture fallback when auto-detect can't find corners
  Future<void> _manualCapture() async {
    if (_captured) return;
    _captured = true;
    try {
      await _ctr!.stopImageStream();
      final file = await _ctr!.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _capturedBytes = bytes);
    } catch (e) {
      debugPrint('Manual capture: $e');
      if (mounted) {
        setState(() { _captured = false; });
        try { await _ctr!.startImageStream(_processFrame); } catch (_) {}
      }
    }
  }

  // ─── Full-frame corner detection (Azota-style, production-grade) ──
  List<CornerMarker> _detect(cv.Mat gray, int w, int h) {
    // Downsample for speed
    const targetW = 640;
    final scale = targetW / w;
    final targetH = (h * scale).toInt();
    final small = cv.resize(gray, (targetW, targetH));

    // Pre-process: histogram equalization + blur + adaptive threshold
    final enhanced = cv.equalizeHist(small);
    final blurred = cv.gaussianBlur(enhanced, (5, 5), 2.0);
    final thresh = cv.adaptiveThreshold(blurred, 255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 31, 5.0);

    // Use RETR_TREE for hierarchy info (nested contours = more reliable marker)
    final (contours, hierarchy) = cv.findContours(
        thresh, cv.RETR_TREE, cv.CHAIN_APPROX_SIMPLE);

    // Find dark square-ish markers in the full frame
    final minSide = (targetW * 0.012).toInt();  // ~8px at 640w
    final maxSide = (targetW * 0.08).toInt();   // ~51px at 640w
    final minArea = minSide * minSide;
    final maxArea = maxSide * maxSide;

    final candidates = <_MarkerCandidate>[];
    for (int j = 0; j < contours.length; j++) {
      final cnt = contours[j];
      final area = cv.contourArea(cnt);
      if (area < minArea || area > maxArea) continue;

      final rect = cv.boundingRect(cnt);
      if (rect.width < minSide || rect.height < minSide) continue;

      // 1) Squareness: aspect ratio close to 1.0
      final ratio = rect.width > rect.height
          ? rect.width / rect.height : rect.height / rect.width;
      if (ratio > 1.35) continue;

      // 2) Polygon approximation: real markers ≈ 4 vertices (square)
      final peri = cv.arcLength(cnt, true);
      final approx = cv.approxPolyDP(cnt, 0.04 * peri, true);
      final nVertices = approx.length;
      approx.dispose();
      // Accept 4-8 vertices (slightly rounded squares still have 4-6)
      if (nVertices < 4 || nVertices > 8) continue;

      // 3) Solidity: contour area / bounding rect area (extent)
      final rectArea = rect.width * rect.height;
      final extent = area / rectArea;
      if (extent < 0.6) continue;  // Square marker should fill >60% of bbox

      // 4) Fill ratio: pixel density inside bounding rect
      final sub = thresh.region(rect);
      final nz = cv.countNonZero(sub);
      final solidRatio = nz / rectArea;
      sub.dispose();
      if (solidRatio < 0.4) continue;

      // 5) Hierarchy score: marker with child contour (border) = more reliable
      double score = solidRatio + extent * 0.3;
      try {
        if (j < hierarchy.length) {
          final h = hierarchy[j]; // Vec4i: [next, prev, firstChild, parent]
          if (h.val3 >= 0) score += 0.2; // val3 = firstChild index
        }
      } catch (_) {}

      // Scale coordinates back to original frame
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

    // Classify into quadrants: TL, TR, BL, BR
    final midX = w / 2.0, midY = h / 2.0;
    final tls = candidates.where((c) => c.rect.center.dx < midX && c.rect.center.dy < midY).toList();
    final trs = candidates.where((c) => c.rect.center.dx >= midX && c.rect.center.dy < midY).toList();
    final bls = candidates.where((c) => c.rect.center.dx < midX && c.rect.center.dy >= midY).toList();
    final brs = candidates.where((c) => c.rect.center.dx >= midX && c.rect.center.dy >= midY).toList();

    // Pick best candidate per quadrant: highest score, then closest to corner
    _MarkerCandidate? _pickCorner(List<_MarkerCandidate> cands, double tx, double ty) {
      if (cands.isEmpty) return null;
      cands.sort((a, b) {
        // Primary: higher score wins (hierarchy bonus)
        if ((a.score - b.score).abs() > 0.1) return b.score.compareTo(a.score);
        // Secondary: closer to corner wins
        final da = (a.rect.center.dx - tx) * (a.rect.center.dx - tx) +
            (a.rect.center.dy - ty) * (a.rect.center.dy - ty);
        final db = (b.rect.center.dx - tx) * (b.rect.center.dx - tx) +
            (b.rect.center.dy - ty) * (b.rect.center.dy - ty);
        return da.compareTo(db);
      });
      return cands.first;
    }

    final tl = _pickCorner(tls, 0, 0);
    final tr = _pickCorner(trs, w.toDouble(), 0);
    final bl = _pickCorner(bls, 0, h.toDouble());
    final br = _pickCorner(brs, w.toDouble(), h.toDouble());

    final out = <CornerMarker>[];
    if (tl != null) out.add(CornerMarker(0, tl.rect));
    if (tr != null) out.add(CornerMarker(1, tr.rect));
    if (bl != null) out.add(CornerMarker(2, bl.rect));
    if (br != null) out.add(CornerMarker(3, br.rect));

    // Size consistency check: reject if marker sizes vary too much
    if (out.length == 4) {
      final areas = out.map((m) => m.rect.width * m.rect.height).toList();
      final avg = areas.reduce((a, b) => a + b) / 4;
      final maxDev = areas.map((a) => (a - avg).abs() / avg).reduce(math.max);
      if (maxDev > 0.6) return []; // sizes too inconsistent
    }

    return out;
  }

  // ─── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Scaffold(backgroundColor: Colors.black,
        body: Center(child: Text(_errorMsg,
            style: const TextStyle(color: Colors.white70))));
    }
    if (!_ready || _ctr == null || !_ctr!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.green)));
    }
    if (_captured && _capturedBytes != null) return _buildResult();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview fullscreen
          Center(child: CameraPreview(_ctr!)),

          // Azota-style green corner overlay
          if (_imgSize != null)
            CustomPaint(
              size: Size.infinite,
              painter: _CornerOverlayPainter(
                markers: _markers,
                imageSize: _imgSize!,
              ),
            ),

          // Green dot (top-right, like TNMaker)
          Positioned(
            top: 10, right: 10,
            child: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _markers.length == 4 ? Colors.green : Colors.grey,
              ),
            ),
          ),

          // Back button
          Positioned(
            top: 8, left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // Manual capture button (fallback)
          Positioned(
            bottom: 70, left: 0, right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _manualCapture,
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    color: Colors.white24,
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),

          // Status text
          Positioned(
            bottom: 20, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _stableStart != null
                      ? 'Đứng yên... ${math.max(0, (2000 - DateTime.now().difference(_stableStart!).inMilliseconds) / 1000).toStringAsFixed(1)}s'
                      : _markers.length == 4
                          ? 'Đã nhận diện phiếu!'
                          : 'Hướng camera vào phiếu trắc nghiệm (${_markers.length}/4 góc)',
                  style: TextStyle(
                    color: _markers.length == 4 ? Colors.greenAccent : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
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
          // Bottom action bar
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Retry button
                  ElevatedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Chụp lại'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                  // Confirm button
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(_capturedBytes),
                    icon: const Icon(Icons.check, size: 20),
                    label: const Text('Chấm điểm'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Azota-style corner overlay painter
//  Draws green L-shaped brackets at detected corner marker positions
// ═══════════════════════════════════════════════════════════════════

class _CornerOverlayPainter extends CustomPainter {
  final List<CornerMarker> markers;
  final Size imageSize;

  _CornerOverlayPainter({required this.markers, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;

    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    for (final m in markers) {
      // Expand rect for visibility (like Azota's green brackets)
      final r = Rect.fromLTWH(
        m.rect.left * sx - 8,
        m.rect.top * sy - 8,
        m.rect.width * sx + 16,
        m.rect.height * sy + 16,
      );
      final armLen = math.min(r.width, r.height) * 0.6;

      // Draw L-shaped corner brackets (4 corners of the rect)
      // Top-left
      canvas.drawLine(Offset(r.left, r.top + armLen), Offset(r.left, r.top), paint);
      canvas.drawLine(Offset(r.left, r.top), Offset(r.left + armLen, r.top), paint);
      // Top-right
      canvas.drawLine(Offset(r.right - armLen, r.top), Offset(r.right, r.top), paint);
      canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + armLen), paint);
      // Bottom-left
      canvas.drawLine(Offset(r.left, r.bottom - armLen), Offset(r.left, r.bottom), paint);
      canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left + armLen, r.bottom), paint);
      // Bottom-right
      canvas.drawLine(Offset(r.right - armLen, r.bottom), Offset(r.right, r.bottom), paint);
      canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right, r.bottom - armLen), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerOverlayPainter old) => markers != old.markers;
}
