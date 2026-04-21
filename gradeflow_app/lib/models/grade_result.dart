class GradeResult {
  final bool success;
  final int? submissionId;
  final String sbd;
  final String made;
  final double? score;
  final int? correctCount;
  final int? totalQuestions;
  final String gradeLabel;
  final String gradeText;
  final Map<String, dynamic> scores;
  final Map<String, dynamic> part1;
  final Map<String, dynamic> part2;
  final Map<String, dynamic> part3;
  final Map<String, dynamic> correctAnswers;
  final Map<String, dynamic>? weighted;
  final String detectMethod;
  final double processingTime;
  final String error;
  final String resultImageBase64;
  final String overlayImageBase64;
  final String nameImageBase64;

  GradeResult({
    required this.success,
    this.submissionId,
    this.sbd = '',
    this.made = '',
    this.score,
    this.correctCount,
    this.totalQuestions,
    this.gradeLabel = 'pending',
    this.gradeText = 'Chờ chấm',
    this.scores = const {},
    this.part1 = const {},
    this.part2 = const {},
    this.part3 = const {},
    this.correctAnswers = const {},
    this.weighted,
    this.detectMethod = '',
    this.processingTime = 0,
    this.error = '',
    this.resultImageBase64 = '',
    this.overlayImageBase64 = '',
    this.nameImageBase64 = '',
  });

  /// Returns `true` when the detection is fully confident — no `?` anywhere in
  /// mã đề, SBD, part1/2/3. Used to decide whether to upload the scan as a
  /// training sample for CNN active learning.
  bool get isCleanForTraining {
    if (!success) return false;
    if (made.isEmpty || made.contains('?')) return false;
    if (sbd.isEmpty || sbd.contains('?')) return false;

    bool _hasUnknown(dynamic v) {
      if (v == null) return false;
      if (v is String) return v.contains('?');
      if (v is Map) return v.values.any(_hasUnknown);
      if (v is List) return v.any(_hasUnknown);
      return false;
    }

    for (final v in part1.values) {
      if (_hasUnknown(v)) return false;
    }
    for (final v in part2.values) {
      if (_hasUnknown(v)) return false;
    }
    for (final v in part3.values) {
      if (_hasUnknown(v)) return false;
    }
    // Require at least some answers detected (avoid empty phiếu)
    if (part1.isEmpty && part2.isEmpty && part3.isEmpty) return false;
    return true;
  }

  /// Compute a 0..1 confidence score for active-learning sampling.
  /// Currently binary: 1.0 if clean, else ratio of non-`?` cells.
  double get confidenceScore {
    int total = 0;
    int unknown = 0;
    void _count(dynamic v) {
      if (v == null) return;
      if (v is String) {
        total += 1;
        if (v.contains('?') || v.isEmpty) unknown += 1;
      } else if (v is Map) {
        v.values.forEach(_count);
      } else if (v is List) {
        v.forEach(_count);
      }
    }

    for (final v in part1.values) _count(v);
    for (final v in part2.values) _count(v);
    for (final v in part3.values) _count(v);
    if (total == 0) return 0.0;
    return 1.0 - (unknown / total);
  }

  /// Metadata to send along with the image when uploading a training sample.
  Map<String, String> toTrainingMetadata() {
    return {
      'made': made,
      'sbd': sbd,
      'confidence': confidenceScore.toStringAsFixed(4),
      'answers_json': _encodeAnswers(),
      if (submissionId != null) 'submission_id': submissionId!.toString(),
    };
  }

  String _encodeAnswers() {
    // Best-effort JSON encode; avoid importing dart:convert here by caller.
    final sb = StringBuffer('{"part1":');
    sb.write(_jsonEncode(part1));
    sb.write(',"part2":');
    sb.write(_jsonEncode(part2));
    sb.write(',"part3":');
    sb.write(_jsonEncode(part3));
    sb.write('}');
    return sb.toString();
  }

  String _jsonEncode(dynamic v) {
    if (v == null) return 'null';
    if (v is String) return '"${v.replaceAll('"', '\\"')}"';
    if (v is num || v is bool) return v.toString();
    if (v is List) {
      return '[${v.map(_jsonEncode).join(',')}]';
    }
    if (v is Map) {
      final entries = v.entries
          .map((e) => '"${e.key}":${_jsonEncode(e.value)}')
          .join(',');
      return '{$entries}';
    }
    return '"${v.toString()}"';
  }

  factory GradeResult.fromJson(Map<String, dynamic> json) {
    return GradeResult(
      success: json['success'] ?? false,
      submissionId: json['submission_id'],
      sbd: json['sbd'] ?? '',
      made: json['made'] ?? '',
      score: json['score']?.toDouble(),
      correctCount: json['correct_count'],
      totalQuestions: json['total_questions'],
      gradeLabel: json['grade_label'] ?? 'pending',
      gradeText: json['grade_text'] ?? 'Chờ chấm',
      scores: Map<String, dynamic>.from(json['scores'] ?? {}),
      part1: Map<String, dynamic>.from(json['part1'] ?? {}),
      part2: Map<String, dynamic>.from(json['part2'] ?? {}),
      part3: Map<String, dynamic>.from(json['part3'] ?? {}),
      correctAnswers: Map<String, dynamic>.from(json['correct_answers'] ?? {}),
      weighted: json['weighted'] != null
          ? Map<String, dynamic>.from(json['weighted'])
          : null,
      detectMethod: json['detect_method'] ?? '',
      processingTime: (json['processing_time'] ?? 0).toDouble(),
      error: json['error'] ?? '',
      resultImageBase64: json['result_image'] ?? '',
      overlayImageBase64: json['overlay_image'] ?? '',
      nameImageBase64: json['name_image'] ?? '',
    );
  }
}
