import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Singleton service that uploads "clean" scanned papers to the backend for
/// active-learning training.
///
/// Flow:
///  1. After a successful grade, `enqueue(...)` is called with the image bytes
///     + metadata (made, sbd, answers JSON, confidence).
///  2. The image is immediately persisted to app document dir and the metadata
///     saved in SharedPreferences queue.
///  3. Upload is attempted right away; on failure, the entry remains in the
///     queue until `retryAll()` is invoked (by `IdleDetector`).
///
/// Backend re-validates the opt-in flag so even stale queued uploads are safe.
class TrainingUploader {
  TrainingUploader._();
  static final TrainingUploader instance = TrainingUploader._();

  static const _queueKey = 'training_upload_queue_v1';
  static const _subdir = 'training_queue';

  bool _flushing = false;

  /// Enqueue and try to upload immediately (fire-and-forget).
  Future<void> enqueue({
    required String token,
    required Uint8List imageBytes,
    required Map<String, String> metadata,
    String? fileName,
  }) async {
    final dir = await _getSubdir();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final name = fileName ?? 'sample_$ts.jpg';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(imageBytes, flush: true);

    final entry = <String, dynamic>{
      'path': file.path,
      'name': name,
      'metadata': metadata,
      'created_at': ts,
      'attempts': 0,
    };
    await _appendEntry(entry);

    // Fire-and-forget background flush
    unawaited(_tryUploadEntry(token, entry));
  }

  /// Retry all pending uploads (called when user is idle).
  Future<void> retryAll(String token) async {
    if (_flushing) return;
    _flushing = true;
    try {
      final entries = await _loadQueue();
      for (final entry in List<Map<String, dynamic>>.from(entries)) {
        await _tryUploadEntry(token, entry);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<int> pendingCount() async {
    final q = await _loadQueue();
    return q.length;
  }

  // ─── Internals ──────────────────────────────────────────────────

  Future<Directory> _getSubdir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_subdir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<Map<String, dynamic>>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw);
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, json.encode(queue));
  }

  Future<void> _appendEntry(Map<String, dynamic> entry) async {
    final queue = await _loadQueue();
    queue.add(entry);
    await _saveQueue(queue);
  }

  Future<void> _removeEntry(String path) async {
    final queue = await _loadQueue();
    queue.removeWhere((e) => e['path'] == path);
    await _saveQueue(queue);
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _incrementAttempts(String path) async {
    final queue = await _loadQueue();
    for (final e in queue) {
      if (e['path'] == path) {
        e['attempts'] = (e['attempts'] ?? 0) + 1;
        break;
      }
    }
    await _saveQueue(queue);
  }

  Future<void> _tryUploadEntry(
      String token, Map<String, dynamic> entry) async {
    final path = entry['path'] as String?;
    if (path == null) return;

    final file = File(path);
    if (!await file.exists()) {
      await _removeEntry(path);
      return;
    }

    // Give up after too many failed attempts (avoid permanent bloat).
    final attempts = (entry['attempts'] ?? 0) as int;
    if (attempts >= 5) {
      await _removeEntry(path);
      return;
    }

    final bytes = await file.readAsBytes();
    final metadata = Map<String, String>.from(
        (entry['metadata'] as Map?) ?? const <String, dynamic>{});
    final name = (entry['name'] as String?) ?? 'sample.jpg';

    try {
      final ok = await ApiService(token: token).uploadTrainingSample(
        imageBytes: bytes,
        fileName: name,
        metadata: metadata,
      );
      if (ok) {
        await _removeEntry(path);
      } else {
        await _incrementAttempts(path);
      }
    } catch (e) {
      debugPrint('TrainingUploader: upload failed for $name: $e');
      await _incrementAttempts(path);
    }
  }
}
