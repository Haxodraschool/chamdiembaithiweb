class Submission {
  final int id;
  final String studentId;
  final String studentName;
  final int? examId;
  final String examTitle;
  final String status;
  final double? score;
  final int? correctCount;
  final int? totalQuestions;
  final String gradeLabel;
  final String gradeText;
  final String uploadedAt;
  final double? processingTime;

  Submission({
    required this.id,
    this.studentId = '',
    this.studentName = '',
    this.examId,
    this.examTitle = '',
    this.status = 'pending',
    this.score,
    this.correctCount,
    this.totalQuestions,
    this.gradeLabel = 'pending',
    this.gradeText = 'Chờ chấm',
    this.uploadedAt = '',
    this.processingTime,
  });

  factory Submission.fromJson(Map<String, dynamic> json) {
    return Submission(
      id: json['id'] ?? 0,
      studentId: json['student_id'] ?? '',
      studentName: json['student_name'] ?? '',
      examId: json['exam_id'],
      examTitle: json['exam_title'] ?? '',
      status: json['status'] ?? 'pending',
      score: json['score']?.toDouble(),
      correctCount: json['correct_count'],
      totalQuestions: json['total_questions'],
      gradeLabel: json['grade_label'] ?? 'pending',
      gradeText: json['grade_text'] ?? 'Chờ chấm',
      uploadedAt: json['uploaded_at'] ?? '',
      processingTime: json['processing_time']?.toDouble(),
    );
  }
}
