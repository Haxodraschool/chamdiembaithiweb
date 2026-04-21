import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/exam.dart';
import '../models/submission.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class ResultsScreen extends StatefulWidget {
  final Exam exam;
  const ResultsScreen({super.key, required this.exam});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  List<Submission> _submissions = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  Future<void> _loadSubmissions() async {
    final auth = context.read<AuthService>();
    if (auth.token == null) return;

    setState(() => _loading = true);

    try {
      final api = ApiService(token: auth.token!);
      final subs = await api.getSubmissions(examId: widget.exam.id, limit: 100);
      if (mounted) setState(() => _submissions = subs);
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  List<Submission> get _filtered {
    if (_search.isEmpty) return _submissions;
    final q = _search.toLowerCase();
    return _submissions.where((s) =>
        s.studentId.toLowerCase().contains(q) ||
        s.studentName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final completed =
        _submissions.where((s) => s.status == 'completed').toList();
    final avgScore = completed.isNotEmpty
        ? completed
                .where((s) => s.score != null)
                .fold<double>(0, (sum, s) => sum + s.score!) /
            completed.where((s) => s.score != null).length
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exam.title, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSubmissions,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Stats
                  if (completed.isNotEmpty) ...[
                    Row(
                      children: [
                        _miniStat('Đã chấm', '${completed.length}',
                            GradeFlowTheme.primary),
                        const SizedBox(width: 8),
                        _miniStat(
                            'TB',
                            avgScore != null
                                ? avgScore.toStringAsFixed(1)
                                : '—',
                            GradeFlowTheme.success),
                        const SizedBox(width: 8),
                        _miniStat(
                            'Cao nhất',
                            completed.isNotEmpty
                                ? completed
                                    .where((s) => s.score != null)
                                    .fold<double>(
                                        0,
                                        (max, s) =>
                                            s.score! > max ? s.score! : max)
                                    .toStringAsFixed(1)
                                : '—',
                            GradeFlowTheme.tertiary),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Search
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm SBD, tên...',
                      prefixIcon:
                          const Icon(LucideIcons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 16),

                  // Submissions
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text('Không có kết quả',
                            style: GoogleFonts.dmSans(
                                color: GradeFlowTheme.onSurfaceVariant)),
                      ),
                    )
                  else
                    ..._filtered.map((sub) => _SubmissionCard(sub: sub)),
                ],
              ),
            ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Column(
            children: [
              Text(value,
                  style: GoogleFonts.manrope(
                      fontSize: 20, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(height: 2),
              Text(label,
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: GradeFlowTheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  final Submission sub;
  const _SubmissionCard({required this.sub});

  @override
  Widget build(BuildContext context) {
    final gradeColor = GradeFlowTheme.gradeColor(sub.gradeLabel);
    final gradeBg = GradeFlowTheme.gradeBackground(sub.gradeLabel);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Score badge
            Container(
              width: 56,
              decoration: BoxDecoration(
                color: gradeBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      sub.score != null ? '${sub.score}' : '—',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: gradeColor,
                      ),
                    ),
                    Text(
                      sub.gradeText,
                      style: GoogleFonts.dmSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: gradeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Info
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      sub.studentName.isNotEmpty
                          ? sub.studentName
                          : sub.studentId.isNotEmpty
                              ? 'SBD ${sub.studentId}'
                              : 'Bài #${sub.id}',
                      style: GoogleFonts.dmSans(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    if (sub.correctCount != null &&
                        sub.totalQuestions != null)
                      Text(
                        '${sub.correctCount}/${sub.totalQuestions} câu',
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: GradeFlowTheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),

            // Status
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                sub.status == 'completed'
                    ? LucideIcons.checkCircle
                    : sub.status == 'error'
                        ? LucideIcons.xCircle
                        : LucideIcons.clock,
                size: 18,
                color: sub.status == 'completed'
                    ? GradeFlowTheme.success
                    : sub.status == 'error'
                        ? GradeFlowTheme.error
                        : GradeFlowTheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
