import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Admin-only screen: shows training-sample stats and lets the admin
/// download the collected dataset as a ZIP file to the device Downloads dir.
class AdminTrainingScreen extends StatefulWidget {
  const AdminTrainingScreen({super.key});

  @override
  State<AdminTrainingScreen> createState() => _AdminTrainingScreenState();
}

class _AdminTrainingScreenState extends State<AdminTrainingScreen> {
  bool _loading = true;
  bool _downloading = false;
  String? _error;
  Map<String, dynamic>? _stats;
  String? _lastSavedPath;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final auth = context.read<AuthService>();
    if (auth.token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService(token: auth.token!);
      final data = await api.getTrainingStats();
      if (!mounted) return;
      setState(() {
        _stats = data;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _download() async {
    final auth = context.read<AuthService>();
    if (auth.token == null) return;
    setState(() {
      _downloading = true;
      _lastSavedPath = null;
    });
    try {
      final api = ApiService(token: auth.token!);
      final bytes = await api.downloadTrainingZip();

      // Save to app downloads dir (Android external, iOS docs)
      Directory? baseDir;
      if (Platform.isAndroid) {
        baseDir = await getExternalStorageDirectory();
      }
      baseDir ??= await getApplicationDocumentsDirectory();

      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${baseDir.path}${Platform.pathSeparator}training_samples_$ts.zip');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      setState(() {
        _downloading = false;
        _lastSavedPath = file.path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã lưu: ${file.path}'),
          backgroundColor: GradeFlowTheme.success,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'vừa xong';
      if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
      if (diff.inHours < 24) return '${diff.inHours} giờ trước';
      if (diff.inDays < 30) return '${diff.inDays} ngày trước';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản trị training data'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.shieldOff,
                size: 48, color: GradeFlowTheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(_error ?? '',
                style: GoogleFonts.dmSans(fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final count = _stats?['count'] ?? 0;
    final totalMb = _stats?['total_mb'] ?? 0;
    final contributors = _stats?['contributors'] ?? 0;
    final lastUploaded = _stats?['last_uploaded'] as String?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [GradeFlowTheme.primary, GradeFlowTheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.shieldCheck,
                  color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Chế độ quản trị viên',
                        style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    Text('Chỉ admin mới thấy trang này',
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.9))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Stat grid
        Row(
          children: [
            Expanded(
              child: _statCard(
                LucideIcons.image,
                'Tổng số mẫu',
                '$count',
                GradeFlowTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                LucideIcons.hardDrive,
                'Dung lượng',
                '$totalMb MB',
                GradeFlowTheme.tertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statCard(
                LucideIcons.users,
                'Người đóng góp',
                '$contributors',
                GradeFlowTheme.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                LucideIcons.clock,
                'Lần cuối',
                _formatTime(lastUploaded),
                GradeFlowTheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Download button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: (_downloading || count == 0) ? null : _download,
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(LucideIcons.download, size: 20),
            label: Text(
              _downloading ? 'Đang tải...' : 'Tải gói training (.zip)',
              style: GoogleFonts.dmSans(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: GradeFlowTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),

        if (_lastSavedPath != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(LucideIcons.fileCheck,
                      size: 18, color: GradeFlowTheme.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_lastSavedPath!,
                        style: GoogleFonts.dmSans(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
        Text(
          'Gói ZIP chứa folder images/ và labels.json với các trường: '
          'id, file, teacher, made, sbd, template_code, confidence, '
          'uploaded_at, answers.',
          style: GoogleFonts.dmSans(
              fontSize: 12, color: GradeFlowTheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 8),
            Text(value,
                style: GoogleFonts.manrope(
                    fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: GradeFlowTheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
