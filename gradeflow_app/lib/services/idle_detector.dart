import 'dart:async';

import 'package:flutter/material.dart';

import 'training_uploader.dart';

/// Wraps the app root and fires a callback when the user has not interacted
/// with the screen for [idleDuration].
///
/// Used to trigger retries of the training-sample upload queue.
class IdleDetector extends StatefulWidget {
  final Widget child;
  final Duration idleDuration;
  final String Function() tokenProvider;

  const IdleDetector({
    super.key,
    required this.child,
    required this.tokenProvider,
    this.idleDuration = const Duration(minutes: 5),
  });

  @override
  State<IdleDetector> createState() => _IdleDetectorState();
}

class _IdleDetectorState extends State<IdleDetector>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reset();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _timer?.cancel();
    }
  }

  void _reset() {
    _timer?.cancel();
    _timer = Timer(widget.idleDuration, _onIdle);
  }

  Future<void> _onIdle() async {
    final token = widget.tokenProvider();
    if (token.isEmpty) return;
    try {
      await TrainingUploader.instance.retryAll(token);
    } catch (_) {}
    // Re-arm so we keep retrying periodically while user stays idle.
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reset(),
      onPointerMove: (_) => _reset(),
      child: widget.child,
    );
  }
}
