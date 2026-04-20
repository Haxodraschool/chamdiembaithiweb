import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../config/theme.dart';
import '../models/grade_result.dart';

class GradeResultScreen extends StatelessWidget {
  final GradeResult result;
  final Uint8List imageBytes;
  final String? examTitle;

  const GradeResultScreen({
    super.key,
    required this.result,
    required this.imageBytes,
    this.examTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kết quả chấm'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: result.success ? _buildSuccess(context) : _buildError(context),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: GradeFlowTheme.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(LucideIcons.alertTriangle,
                  size: 36, color: GradeFlowTheme.error),
            ),
            const SizedBox(height: 20),
            Text(
              'Không nhận diện được',
              style: GoogleFonts.manrope(
                  fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              result.error,
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: GradeFlowTheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(LucideIcons.scan, size: 18),
              label: const Text('Quét lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final gradeLabel = result.gradeLabel;
    final gradeColor = GradeFlowTheme.gradeColor(gradeLabel);
    final gradeBg = GradeFlowTheme.gradeBackground(gradeLabel);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Score hero card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Score circle
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: gradeBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: gradeColor.withOpacity(0.3), width: 3),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          result.score != null
                              ? '${result.score}'
                              : '—',
                          style: GoogleFonts.manrope(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: gradeColor,
                          ),
                        ),
                        Text(
                          result.gradeText,
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: gradeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (examTitle != null)
                  Text(
                    examTitle!,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),

                const SizedBox(height: 12),

                // Info chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (result.sbd.isNotEmpty)
                      _infoChip(LucideIcons.hash, 'SBD: ${result.sbd}'),
                    if (result.made.isNotEmpty)
                      _infoChip(LucideIcons.fileText, 'Mã đề: ${result.made}'),
                    if (result.correctCount != null &&
                        result.totalQuestions != null)
                      _infoChip(LucideIcons.checkSquare,
                          '${result.correctCount}/${result.totalQuestions} câu'),
                    _infoChip(LucideIcons.timer,
                        '${result.processingTime.toStringAsFixed(1)}s'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Part scores
        if (result.weighted != null) _buildPartScores(),
        const SizedBox(height: 16),

        // Scanned image preview
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.image,
                        size: 16, color: GradeFlowTheme.primary),
                    const SizedBox(width: 8),
                    Text('Ảnh đã quét',
                        style: GoogleFonts.dmSans(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    imageBytes,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Detected answers
        if (result.part1.isNotEmpty) _buildDetectedAnswers(),
        const SizedBox(height: 20),

        // Actions
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.scan, size: 18),
                label: const Text('Quét tiếp'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildPartScores() {
    final w = result.weighted!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chi tiết điểm',
                style: GoogleFonts.dmSans(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _partRow('Phần I (Trắc nghiệm)',
                '${w['p1_correct']} câu đúng', '${w['p1_score']} đ'),
            const Divider(height: 16),
            _partRow('Phần II (Đúng/Sai)',
                '${w['p2_correct']} ý đúng', '${w['p2_score']} đ'),
            const Divider(height: 16),
            _partRow('Phần III (Trả lời ngắn)',
                '${w['p3_correct']} câu đúng', '${w['p3_score']} đ'),
          ],
        ),
      ),
    );
  }

  Widget _partRow(String label, String detail, String score) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.dmSans(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(detail,
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: GradeFlowTheme.onSurfaceVariant)),
            ],
          ),
        ),
        Text(
          score,
          style: GoogleFonts.manrope(
              fontSize: 16, fontWeight: FontWeight.w700,
              color: GradeFlowTheme.primary),
        ),
      ],
    );
  }

  Widget _buildDetectedAnswers() {
    final entries = result.part1.entries.toList();
    entries.sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Đáp án phát hiện — Phần I',
                style: GoogleFonts.dmSans(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entries.map((e) {
                return Container(
                  width: 48,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  decoration: BoxDecoration(
                    color: GradeFlowTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: GradeFlowTheme.outlineVariant, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      Text(
                        e.key,
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          color: GradeFlowTheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${e.value}',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: GradeFlowTheme.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: GradeFlowTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: GradeFlowTheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(text,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: GradeFlowTheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
