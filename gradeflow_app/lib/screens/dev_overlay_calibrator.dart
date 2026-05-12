import 'package:flutter/material.dart';

/// Dev overlay calibrator — draggable/resizable corner squares
/// for tuning marker detection positions.
///
/// Usage:
///   1. Long press settings icon → enter dev mode
///   2. Drag each corner independently to adjust position
///   3. Drag center resize handle up/down to resize all corners
///   4. Tap "Done" → shows code snippet to copy
class DevOverlayCalibrator extends StatefulWidget {
  final Size screenSize;
  final VoidCallback onDone;
  final Function(String code) onCodeGenerated;
  final double initialSqSize;
  // Individual corner positions (as % of screen, top-left of each square)
  final double initialTlX, initialTlY;
  final double initialTrX, initialTrY;
  final double initialBlX, initialBlY;
  final double initialBrX, initialBrY;

  const DevOverlayCalibrator({
    super.key,
    required this.screenSize,
    required this.onDone,
    required this.onCodeGenerated,
    this.initialSqSize = 0.12,
    this.initialTlX = 0.02, this.initialTlY = 0.02,
    double? initialTrX, double? initialTrY,
    double? initialBlX, double? initialBlY,
    double? initialBrX, double? initialBrY,
  })  : initialTrX = initialTrX ?? (1.0 - 0.02 - 0.12),
        initialTrY = initialTrY ?? 0.02,
        initialBlX = initialBlX ?? 0.02,
        initialBlY = initialBlY ?? (1.0 - 0.02 - 0.12),
        initialBrX = initialBrX ?? (1.0 - 0.02 - 0.12),
        initialBrY = initialBrY ?? (1.0 - 0.02 - 0.12);

  @override
  State<DevOverlayCalibrator> createState() => _DevOverlayCalibratorState();
}

class _DevOverlayCalibratorState extends State<DevOverlayCalibrator> {
  // Each corner has independent position (relative to screen, 0.0-1.0)
  // Stored as top-left corner of each square
  late double _tlX, _tlY;
  late double _trX, _trY;
  late double _blX, _blY;
  late double _brX, _brY;
  late double _sqSize; // square size as % of screen width

  // Drag state
  int? _draggingCorner; // 0=TL, 1=TR, 2=BL, 3=BR
  Offset _dragStart = Offset.zero;
  double _cornerStartX = 0, _cornerStartY = 0;

  // Resize state
  bool _resizing = false;
  double _resizeStartY = 0;
  double _resizeStartSize = 0;

  @override
  void initState() {
    super.initState();
    _sqSize = widget.initialSqSize;
    // Initialize each corner independently from painter values
    _tlX = widget.initialTlX;
    _tlY = widget.initialTlY;
    _trX = widget.initialTrX;
    _trY = widget.initialTrY;
    _blX = widget.initialBlX;
    _blY = widget.initialBlY;
    _brX = widget.initialBrX;
    _brY = widget.initialBrY;
  }

  // Get current corner positions as list
  List<Offset> get _corners => [
        Offset(_tlX, _tlY),
        Offset(_trX, _trY),
        Offset(_blX, _blY),
        Offset(_brX, _brY),
      ];

  void _onPanStart(DragStartDetails details, int corner) {
    final c = _corners[corner];
    setState(() {
      _draggingCorner = corner;
      _dragStart = details.localPosition;
      _cornerStartX = c.dx;
      _cornerStartY = c.dy;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_draggingCorner == null) return;
    final dx = details.localPosition.dx - _dragStart.dx;
    final dy = details.localPosition.dy - _dragStart.dy;
    final screenW = widget.screenSize.width;
    final screenH = widget.screenSize.height;

    final newX = (_cornerStartX + dx / screenW).clamp(0.0, 1.0 - _sqSize);
    final newY = (_cornerStartY + dy / screenH).clamp(0.0, 1.0 - _sqSize);

    setState(() {
      switch (_draggingCorner!) {
        case 0: _tlX = newX; _tlY = newY; break;
        case 1: _trX = newX; _trY = newY; break;
        case 2: _blX = newX; _blY = newY; break;
        case 3: _brX = newX; _brY = newY; break;
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _draggingCorner = null;
    });
  }

  // Resize: drag up = bigger, drag down = smaller
  void _onResizeStart(DragStartDetails details) {
    setState(() {
      _resizing = true;
      _resizeStartY = details.localPosition.dy;
      _resizeStartSize = _sqSize;
    });
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    if (!_resizing) return;
    final dy = _resizeStartY - details.localPosition.dy; // up = positive
    final screenW = widget.screenSize.width;
    final screenH = widget.screenSize.height;
    final delta = dy / screenH * 0.5; // scale factor
    final newSize = (_resizeStartSize + delta).clamp(0.05, 0.35);
    final sizeDiff = newSize - _sqSize;
    final aspectRatio = screenW / screenH;

    setState(() {
      // Adjust positions to keep centers stable when resizing
      _tlX -= sizeDiff / 2;
      _tlY -= sizeDiff * aspectRatio / 2;
      _trX -= sizeDiff / 2;
      _trY -= sizeDiff * aspectRatio / 2;
      _blX -= sizeDiff / 2;
      _blY -= sizeDiff * aspectRatio / 2;
      _brX -= sizeDiff / 2;
      _brY -= sizeDiff * aspectRatio / 2;
      _sqSize = newSize;

      // Clamp all corners
      _tlX = _tlX.clamp(0.0, 1.0 - _sqSize);
      _tlY = _tlY.clamp(0.0, 1.0 - _sqSize);
      _trX = _trX.clamp(0.0, 1.0 - _sqSize);
      _trY = _trY.clamp(0.0, 1.0 - _sqSize);
      _blX = _blX.clamp(0.0, 1.0 - _sqSize);
      _blY = _blY.clamp(0.0, 1.0 - _sqSize);
      _brX = _brX.clamp(0.0, 1.0 - _sqSize);
      _brY = _brY.clamp(0.0, 1.0 - _sqSize);
    });
  }

  void _onResizeEnd(DragEndDetails details) {
    setState(() {
      _resizing = false;
    });
  }

  void _generateCode() {
    final screenW = widget.screenSize.width;
    final screenH = widget.screenSize.height;

    // Positions are already direct screen percentages (top-left of each square)
    final code = '''
// Dev-calibrated overlay positions
// Screen: \${screenW.round()}x\${screenH.round()}
// Generated by DevOverlayCalibrator (independent corners)

// In _AzotaOverlayPainter.paint():
final sqSize = screenW * ${_sqSize.toStringAsFixed(4)};

final corners = [
  (0, Rect.fromLTWH(screenW * ${_tlX.toStringAsFixed(4)}, screenH * ${_tlY.toStringAsFixed(4)}, sqSize, sqSize)),  // TL
  (1, Rect.fromLTWH(screenW * ${_trX.toStringAsFixed(4)}, screenH * ${_trY.toStringAsFixed(4)}, sqSize, sqSize)),  // TR
  (2, Rect.fromLTWH(screenW * ${_blX.toStringAsFixed(4)}, screenH * ${_blY.toStringAsFixed(4)}, sqSize, sqSize)),  // BL
  (3, Rect.fromLTWH(screenW * ${_brX.toStringAsFixed(4)}, screenH * ${_brY.toStringAsFixed(4)}, sqSize, sqSize)),  // BR
];''';

    widget.onCodeGenerated(code);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = widget.screenSize.width;
    final screenH = widget.screenSize.height;
    final sqPx = _sqSize * screenW;

    return Stack(
      children: [
        // Semi-transparent background
        GestureDetector(
          onTap: () {}, // Absorb taps
          child: Container(color: Colors.black.withOpacity(0.3)),
        ),

        // 4 corner squares (draggable independently)
        for (int i = 0; i < 4; i++)
          Positioned(
            left: _corners[i].dx * screenW,
            top: _corners[i].dy * screenH,
            width: sqPx,
            height: sqPx,
            child: GestureDetector(
              onPanStart: (d) => _onPanStart(d, i),
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Container(
                decoration: BoxDecoration(
                  color: _draggingCorner == i
                      ? Colors.yellow.withOpacity(0.5)
                      : Colors.green.withOpacity(0.3),
                  border: Border.all(
                    color: _draggingCorner == i ? Colors.yellow : Colors.green,
                    width: 3,
                  ),
                ),
                child: Center(
                  child: Text(
                    ['TL', 'TR', 'BL', 'BR'][i],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Resize handle (center, drag up/down)
        Positioned(
          left: screenW / 2 - 40,
          top: screenH / 2 - 40,
          width: 80,
          height: 80,
          child: GestureDetector(
            onPanStart: _onResizeStart,
            onPanUpdate: _onResizeUpdate,
            onPanEnd: _onResizeEnd,
            child: Container(
              decoration: BoxDecoration(
                color: _resizing
                    ? Colors.orange.withOpacity(0.8)
                    : Colors.orange.withOpacity(0.6),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.swap_vert, color: Colors.white, size: 20),
                  Text(
                    '${(_sqSize * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Info bar
        Positioned(
          top: 40,
          left: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'DEV: Drag each corner independently. Drag center ↕ to resize.\n'
              'Size: ${(_sqSize * 100).toStringAsFixed(1)}%  '
              'TL:(${(_tlX*100).toStringAsFixed(1)}%,${(_tlY*100).toStringAsFixed(1)}%) '
              'TR:(${(_trX*100).toStringAsFixed(1)}%,${(_trY*100).toStringAsFixed(1)}%)',
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ),
        ),

        // Done button
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: ElevatedButton.icon(
              onPressed: () {
                _generateCode();
                widget.onDone();
              },
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Done — Generate Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
