import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthService>();
    if (auth.token == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ApiService(token: auth.token!);
      final data = await api.getDashboard();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('GradeFlow',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _buildContent(auth),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.wifiOff,
                size: 48, color: GradeFlowTheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Không thể kết nối server',
                style: GoogleFonts.dmSans(fontSize: 16)),
            const SizedBox(height: 8),
            Text(_error ?? '',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: GradeFlowTheme.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AuthService auth) {
    final stats = _data?['stats'] ?? {};
    final recentSubs = (_data?['recent_submissions'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Welcome
        Text(
          'Xin chào, ${auth.userName}!',
          style: GoogleFonts.manrope(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: GradeFlowTheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tổng quan hoạt động chấm điểm của bạn',
          style: GoogleFonts.dmSans(
            fontSize: 15,
            color: GradeFlowTheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Stats Grid — 2x2
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: [
            StatCard(
              icon: LucideIcons.fileText,
              iconColor: GradeFlowTheme.primary,
              iconBg: GradeFlowTheme.primaryFixed,
              value: '${stats['total_exams'] ?? 0}',
              label: 'Bài thi',
            ),
            StatCard(
              icon: LucideIcons.checkCircle,
              iconColor: GradeFlowTheme.success,
              iconBg: GradeFlowTheme.successContainer,
              value: '${stats['total_graded'] ?? 0}',
              label: 'Bài đã chấm',
            ),
            StatCard(
              icon: LucideIcons.trendingUp,
              iconColor: GradeFlowTheme.tertiary,
              iconBg: GradeFlowTheme.tertiaryContainer,
              value: stats['avg_score'] != null
                  ? '${stats['avg_score']}'
                  : '—',
              label: 'Điểm trung bình',
            ),
            StatCard(
              icon: LucideIcons.barChart3,
              iconColor: GradeFlowTheme.onSurfaceVariant,
              iconBg: GradeFlowTheme.surfaceContainer,
              value: stats['pass_rate'] != null
                  ? '${stats['pass_rate']}%'
                  : '—',
              label: 'Tỉ lệ đạt',
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Recent Submissions
        Text(
          'Bài chấm gần đây',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        if (recentSubs.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(LucideIcons.inbox,
                      size: 40, color: GradeFlowTheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('Chưa có bài chấm nào',
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: GradeFlowTheme.onSurfaceVariant)),
                ],
              ),
            ),
          )
        else
          ...recentSubs.map((sub) => _SubmissionTile(data: sub)),
      ],
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SubmissionTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final score = data['score'];
    final gradeLabel = data['grade_label'] ?? 'pending';
    final gradeText = data['grade_text'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Score badge
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: GradeFlowTheme.gradeBackground(gradeLabel),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  score != null ? '$score' : '—',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: GradeFlowTheme.gradeColor(gradeLabel),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['student_id']?.isNotEmpty == true
                        ? 'SBD ${data['student_id']}'
                        : data['exam_title'] ?? 'Bài nộp',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data['exam_title'] ?? '',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: GradeFlowTheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Grade chip
            if (gradeText.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: GradeFlowTheme.gradeBackground(gradeLabel),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  gradeText,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: GradeFlowTheme.gradeColor(gradeLabel),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
