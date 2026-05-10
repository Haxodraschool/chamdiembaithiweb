import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ----------------------------------------------------------------------
// 1. CẤU HÌNH TỌA ĐỘ OVERLAY
// ----------------------------------------------------------------------
const double sqSizeRatio = 0.1881;
const Map<String, Offset> cornerRatios = {
  'TL': Offset(0.0000, 0.1901),
  'TR': Offset(0.8119, 0.1910),
  'BL': Offset(0.0097, 0.7033),
  'BR': Offset(0.8119, 0.7054),
};

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const MaterialApp(home: AutoScanScreen()));
}

class AutoScanScreen extends StatefulWidget {
  const AutoScanScreen({Key? key}) : super(key: key);

  @override
  State<AutoScanScreen> createState() => _AutoScanScreenState();
}

class _AutoScanScreenState extends State<AutoScanScreen> {
  CameraController? _controller;
  bool _isDetecting = false;
  bool _isAligned = false;
  int _alignedFramesCount = 0;
  int _missedFramesCount = 0;
  String? _tiltWarning;

  List<Rect> _markerRectsInCorner = [];

  static const int _requiredAlignedFrames = 3;
  static const int _maxMissedFrames = 5;
  static const Duration _cooldownDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) return;

    _controller = CameraController(
      _cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});

    _controller!.startImageStream((CameraImage image) {
      if (_isDetecting) return;
      _isDetecting = true;
      _processCameraImage(image);
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final Plane yPlane = image.planes[0];
      final Uint8List yBytes = Uint8List.fromList(yPlane.bytes);
      final int rowStride = yPlane.bytesPerRow;
      final int sensorW = image.width;
      final int sensorH = image.height;

      final Map<String, dynamic> result = await compute(_detectMarkers, {
        'yBytes': yBytes,
        'rowStride': rowStride,
        'sensorW': sensorW,
        'sensorH': sensorH,
        'sqSizeRatio': sqSizeRatio,
        'corners': cornerRatios,
      });

      if (!mounted) return;

      final bool isMatch = result['match'] as bool;
      final String? tilt = result['tilt'] as String?;

      final List<dynamic> rawMarkers = result['markers'] as List<dynamic>;
      List<Rect> cornerMarkers = [];
      for (int i = 0; i < rawMarkers.length; i += 4) {
        if (i + 3 < rawMarkers.length) {
          cornerMarkers.add(Rect.fromLTWH(
            (rawMarkers[i] as num).toDouble(),
            (rawMarkers[i + 1] as num).toDouble(),
            (rawMarkers[i + 2] as num).toDouble(),
            (rawMarkers[i + 3] as num).toDouble(),
          ));
        }
      }

      setState(() {
        _markerRectsInCorner = cornerMarkers;
        _tiltWarning = tilt;
      });

      if (isMatch) {
        _missedFramesCount = 0;
        _alignedFramesCount++;
        setState(() => _isAligned = true);
        if (_alignedFramesCount >= _requiredAlignedFrames) {
          _alignedFramesCount = 0;
          _autoCapture();
        }
      } else {
        _missedFramesCount++;
        if (_missedFramesCount >= _maxMissedFrames) {
          _alignedFramesCount = 0;
          _missedFramesCount = 0;
          if (_isAligned) setState(() => _isAligned = false);
        }
      }
    } catch (e) {
      print("Lỗi phân tích ảnh: $e");
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _autoCapture() async {
    await _controller!.stopImageStream();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 Nhận diện thành công! Đang chụp...'),
        backgroundColor: Colors.green,
      ),
    );

    try {
      final file = await _controller!.takePicture();
      print("Đã chụp: ${file.path}");
    } catch (e) {
      print("Lỗi chụp: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),

          CustomPaint(
            size: size,
            painter: _AzotaOverlayPainter(
              screenW: size.width,
              screenH: size.height,
              isAligned: _isAligned,
              markerRectsInCorner: _markerRectsInCorner,
            ),
          ),

          // ★ Cảnh báo nghiêng
          if (_tiltWarning != null)
            Positioned(
              top: 80,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _tiltWarning!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _isAligned
                      ? "Giữ yên... ($_alignedFramesCount/$_requiredAlignedFrames)"
                      : "Hãy đưa 4 ô vuông đen vào khung",
                  style: TextStyle(
                    color: _isAligned ? Colors.greenAccent : Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// 3. THUẬT TOÁN NHẬN DIỆN Ô VUÔNG ĐEN 5×5mm
// ----------------------------------------------------------------------
Map<String, dynamic> _detectMarkers(Map<String, dynamic> params) {
  final Uint8List yBytes = params['yBytes'];
  final int rowStride = params['rowStride'];
  final int sensorW = params['sensorW'];
  final int sensorH = params['sensorH'];
  final double sqRatio = params['sqSizeRatio'];
  final Map<String, Offset> corners = params['corners'];

  bool isRotated = sensorW > sensorH;

  int logicalW = isRotated ? sensorH : sensorW;
  int logicalH = isRotated ? sensorW : sensorH;

  double targetRatio = 3 / 4;
  double currentRatio = logicalW / logicalH;
  int cropW = logicalW, cropH = logicalH, offsetX = 0, offsetY = 0;

  if (currentRatio > targetRatio) {
    cropW = (logicalH * targetRatio).toInt();
    offsetX = (logicalW - cropW) ~/ 2;
  } else if (currentRatio < targetRatio) {
    cropH = (logicalW / targetRatio).toInt();
    offsetY = (logicalH - cropH) ~/ 2;
  }

  double sqSize = cropW * sqRatio;

  bool allMatch = true;
  List<double> markerPositions = [];
  List<Offset> markerCenters = [];

  for (var key in corners.keys) {
    Offset ratio = corners[key]!;

    int roiX = (offsetX + cropW * ratio.dx).toInt();
    int roiY = (offsetY + cropH * ratio.dy).toInt();
    int roiW = sqSize.toInt();
    int roiH = sqSize.toInt();

    roiX = roiX.clamp(0, logicalW - 1);
    roiY = roiY.clamp(0, logicalH - 1);
    roiW = roiW.clamp(1, logicalW - roiX);
    roiH = roiH.clamp(1, logicalH - roiY);

    if (roiW < 5 || roiH < 5) {
      allMatch = false;
      continue;
    }

    List<double> markerRect = _findMarker(
      yBytes, rowStride, sensorW, sensorH, isRotated,
      roiX, roiY, roiW, roiH, logicalW, logicalH,
    );

    if (markerRect[0] >= 0) {
      double relX = markerRect[0] / roiW;
      double relY = markerRect[1] / roiH;
      double relW = markerRect[2] / roiW;
      double relH = markerRect[3] / roiH;
      markerPositions.addAll([relX, relY, relW, relH]);

      double cx = roiX + markerRect[0] + markerRect[2] / 2;
      double cy = roiY + markerRect[1] + markerRect[3] / 2;
      markerCenters.add(Offset(cx, cy));
    } else {
      allMatch = false;
    }
  }

  String? tiltWarning;
  if (markerCenters.length >= 2) {
    tiltWarning = _detectTilt(markerCenters, corners, logicalW, logicalH);
  }

  return {
    'match': allMatch,
    'markers': markerPositions,
    'tilt': tiltWarning,
  };
}

String? _detectTilt(
  List<Offset> centers,
  Map<String, Offset> corners,
  int logicalW,
  int logicalH,
) {
  if (centers.length < 2) return null;

  if (centers.length >= 2) {
    double dy = (centers[0].dy - centers[1].dy).abs();
    double dx = (centers[0].dx - centers[1].dx).abs();
    if (dx > 0) {
      double angle = atan(dy / dx) * 180 / pi;
      if (angle > 8) {
        return "⚠️ Giấy bị nghiêng ~${angle.toStringAsFixed(0)}° — Hãy đặt giấy thẳng!";
      }
    }
  }

  return null;
}

List<double> _findMarker(
  Uint8List yBytes,
  int rowStride,
  int sensorW,
  int sensorH,
  bool isRotated,
  int roiX,
  int roiY,
  int roiW,
  int roiH,
  int logicalW,
  int logicalH,
) {
  int readLuminance(int x, int y) {
    int px = isRotated ? y : x;
    int py = isRotated ? (sensorH - 1 - x) : y;
    if (px < 0 || px >= sensorW || py < 0 || py >= sensorH) return 255;
    int idx = py * rowStride + px;
    if (idx < 0 || idx >= yBytes.length) return 255;
    return yBytes[idx];
  }

  int sumLum = 0, sampleN = 0;
  for (int y = roiY; y < roiY + roiH; y += 3) {
    for (int x = roiX; x < roiX + roiW; x += 3) {
      sumLum += readLuminance(x, y);
      sampleN++;
    }
  }
  if (sampleN == 0) return [-1, -1, -1, -1];
  double avgLum = sumLum / sampleN;

  // ★ Threshold: cân bằng
  int darkThresh = (avgLum * 0.50).toInt().clamp(30, 120);

  int minX = logicalW, minY = logicalH, maxX = 0, maxY = 0;
  int darkCount = 0;

  for (int y = roiY; y < roiY + roiH; y++) {
    for (int x = roiX; x < roiX + roiW; x++) {
      int lum = readLuminance(x, y);
      if (lum < darkThresh) {
        darkCount++;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  int totalPx = roiW * roiH;
  if (totalPx == 0 || darkCount == 0) return [-1, -1, -1, -1];

  double darkRatio = darkCount / totalPx;

  if (darkRatio < 0.01 || darkRatio > 0.50) {
    return [-1, -1, -1, -1];
  }

  double bw = (maxX - minX).toDouble();
  double bh = (maxY - minY).toDouble();

  if (bw < 2 || bh < 2) return [-1, -1, -1, -1];
  if (bw > roiW * 0.90 || bh > roiH * 0.90) return [-1, -1, -1, -1];

  double aspect = bw > bh ? bw / bh : bh / bw;
  if (aspect > 3.5) return [-1, -1, -1, -1];

  double cx = (minX + maxX) / 2.0;
  double cy = (minY + maxY) / 2.0;
  double relX = (cx - roiX) / roiW;
  double relY = (cy - roiY) / roiH;
  if (relX < 0.02 || relX > 0.98) return [-1, -1, -1, -1];
  if (relY < 0.02 || relY > 0.98) return [-1, -1, -1, -1];

  double darkAreaRatio = (bw * bh) / (roiW * roiH);
  if (darkAreaRatio < 0.005 || darkAreaRatio > 0.50) {
    return [-1, -1, -1, -1];
  }

  return [
    (minX - roiX).toDouble(),
    (minY - roiY).toDouble(),
    bw,
    bh,
  ];
}

// ----------------------------------------------------------------------
// 4. LỚP VẼ OVERLAY
// ----------------------------------------------------------------------
class _AzotaOverlayPainter extends CustomPainter {
  final double screenW;
  final double screenH;
  final bool isAligned;
  final List<Rect> markerRectsInCorner;

  _AzotaOverlayPainter({
    required this.screenW,
    required this.screenH,
    required this.isAligned,
    this.markerRectsInCorner = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sqSize = screenW * sqSizeRatio;

    final borderPaint = Paint()
      ..color = isAligned ? Colors.greenAccent : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final corners = [
      Rect.fromLTWH(screenW * 0.0000, screenH * 0.1901, sqSize, sqSize),
      Rect.fromLTWH(screenW * 0.8119, screenH * 0.1910, sqSize, sqSize),
      Rect.fromLTWH(screenW * 0.0097, screenH * 0.7033, sqSize, sqSize),
      Rect.fromLTWH(screenW * 0.8119, screenH * 0.7054, sqSize, sqSize),
    ];

    for (var rect in corners) {
      canvas.drawRect(rect, borderPaint);
    }

    // ★ Vẽ bounding box xanh lục CHỈ BÊN TRONG overlay
    if (markerRectsInCorner.length >= 4) {
      final markerPaint = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      for (int i = 0; i < 4 && i < markerRectsInCorner.length; i++) {
        final corner = corners[i];
        final relMarker = markerRectsInCorner[i];

        // ★ Clamp relative values vào [0, 1]
        double clampedLeft = relMarker.left.clamp(0.0, 1.0);
        double clampedTop = relMarker.top.clamp(0.0, 1.0);
        double clampedRight = (relMarker.left + relMarker.width).clamp(0.0, 1.0);
        double clampedBottom = (relMarker.top + relMarker.height).clamp(0.0, 1.0);
        double clampedW = clampedRight - clampedLeft;
        double clampedH = clampedBottom - clampedTop;

        if (clampedW <= 0 || clampedH <= 0) continue;

        final markerScreenRect = Rect.fromLTWH(
          corner.left + clampedLeft * corner.width,
          corner.top + clampedTop * corner.height,
          clampedW * corner.width,
          clampedH * corner.height,
        );

        // ★ Clip canvas to corner bounds (đảm bảo 100% không vẽ ra ngoài)
        canvas.save();
        canvas.clipRect(corner);
        canvas.drawRect(markerScreenRect, markerPaint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AzotaOverlayPainter oldDelegate) {
    return oldDelegate.isAligned != isAligned ||
        oldDelegate.screenW != screenW ||
        oldDelegate.screenH != screenH ||
        oldDelegate.markerRectsInCorner.length != markerRectsInCorner.length;
  }
}
