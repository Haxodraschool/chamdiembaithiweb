import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class ExamCreateScreen extends StatefulWidget {
  const ExamCreateScreen({super.key});

  @override
  State<ExamCreateScreen> createState() => _ExamCreateScreenState();
}

class _ExamCreateScreenState extends State<ExamCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();

  // Template selection (from API)
  List<Map<String, dynamic>> _templates = [];
  bool _loadingTemplates = true;
  Map<String, dynamic>? _selectedTemplate;
  int _previewPageIdx = 0;

  // Derived from selected template
  int _p1Count = 24;
  int _p2Count = 4;
  int _p3Count = 0;

  // Variants: list of {code, p1, p2, p3}
  List<_VariantData> _variants = [_VariantData()];
  bool _saving = false;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final auth = context.read<AuthService>();
    if (auth.token == null) return;
    try {
      final api = ApiService(token: auth.token!);
      final templates = await api.getTemplates();
      if (mounted) {
        setState(() {
          _templates = templates;
          _loadingTemplates = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTemplates = false);
    }
  }

  int get _totalQuestions => _p1Count + _p2Count + _p3Count;

  Future<void> _saveExam() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();
    if (auth.token == null) return;

    setState(() => _saving = true);
    try {
      final api = ApiService(token: auth.token!);
      final variantsList = _variants
          .where((v) => v.codeCtrl.text.trim().isNotEmpty)
          .map((v) => {
                'code': v.codeCtrl.text.trim(),
                'p1': v.buildP1Answers(_p1Count),
                'p2': v.buildP2Answers(_p2Count),
                'p3': v.buildP3Answers(_p3Count),
              })
          .toList();

      await api.createExam(
        title: _titleCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        templateCode: _selectedTemplate?['code'] ?? '',
        parts: [_p1Count, _p2Count, _p3Count],
        variants: variantsList,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Đã tạo đề thi thành công!'),
              backgroundColor: Color(0xFF2E7D32)),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo đề thi'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (_currentStep == 2)
            TextButton.icon(
              onPressed: _saving ? null : _saveExam,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(LucideIcons.save, size: 18),
              label: Text(_saving ? 'Đang lưu...' : 'Lưu',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < 2) {
              setState(() => _currentStep++);
            } else {
              _saveExam();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) setState(() => _currentStep--);
          },
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: details.onStepContinue,
                    child: Text(_currentStep == 2 ? 'Lưu đề thi' : 'Tiếp tục'),
                  ),
                  if (_currentStep > 0) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Quay lại'),
                    ),
                  ],
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Thông tin đề thi'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0
                  ? StepState.complete
                  : StepState.indexed,
              content: _buildStep1(),
            ),
            Step(
              title: const Text('Chọn mẫu giấy thi'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1
                  ? StepState.complete
                  : StepState.indexed,
              content: _buildStep2(),
            ),
            Step(
              title: const Text('Mã đề và đáp án'),
              isActive: _currentStep >= 2,
              content: _buildStep3(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: Basic info ──
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            labelText: 'Tên đề thi *',
            hintText: 'VD: Kiểm tra giữa kỳ Toán 12',
            prefixIcon: Icon(LucideIcons.fileText, size: 18),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên đề thi' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _subjectCtrl,
          decoration: const InputDecoration(
            labelText: 'Môn học',
            hintText: 'VD: Toán',
            prefixIcon: Icon(LucideIcons.bookOpen, size: 18),
          ),
        ),
      ],
    );
  }

  // ── Step 2: Choose template with preview images ──
  Widget _buildStep2() {
    if (_loadingTemplates) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Không có mẫu giấy thi nào',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: GradeFlowTheme.onSurfaceVariant)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chọn mẫu phiếu thi phù hợp',
            style: GoogleFonts.dmSans(
                fontSize: 13, color: GradeFlowTheme.onSurfaceVariant)),
        const SizedBox(height: 12),

        ..._templates.map((t) {
          final code = t['code'] as String;
          final label = t['label'] as String? ?? code;
          final parts = List<int>.from(t['parts'] ?? [0, 0, 0]);
          final desc = t['desc'] as String? ?? '';
          final total = t['total'] ?? 0;
          final images = List<String>.from(t['images'] ?? []);
          final pages = t['pages'] ?? 1;
          final selected = _selectedTemplate?['code'] == code;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedTemplate = t;
                _p1Count = parts[0];
                _p2Count = parts.length > 1 ? parts[1] : 0;
                _p3Count = parts.length > 2 ? parts[2] : 0;
                _previewPageIdx = 0;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: selected
                    ? GradeFlowTheme.primary.withOpacity(0.06)
                    : GradeFlowTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? GradeFlowTheme.primary
                      : GradeFlowTheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Row(
                      children: [
                        if (selected)
                          Icon(LucideIcons.checkCircle2,
                              size: 18, color: GradeFlowTheme.primary),
                        if (selected) const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(code,
                                  style: GoogleFonts.manrope(
                                      fontSize: 14, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(desc,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: GradeFlowTheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: GradeFlowTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('$total câu',
                              style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: GradeFlowTheme.primary)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        _partBadge('P1: ${parts[0]}', GradeFlowTheme.primary),
                        const SizedBox(width: 4),
                        if (parts.length > 1 && parts[1] > 0) ...[
                          _partBadge('P2: ${parts[1]}', const Color(0xFFE65100)),
                          const SizedBox(width: 4),
                        ],
                        if (parts.length > 2 && parts[2] > 0)
                          _partBadge('P3: ${parts[2]}', const Color(0xFF6A1B9A)),
                        const Spacer(),
                        Text('$pages trang',
                            style: GoogleFonts.dmSans(
                                fontSize: 11,
                                color: GradeFlowTheme.onSurfaceVariant)),
                      ],
                    ),
                  ),

                  // Preview images — show when selected
                  if (selected && images.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.eye,
                                  size: 14, color: GradeFlowTheme.primary),
                              const SizedBox(width: 6),
                              Text('Xem trước mẫu phiếu',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              const Spacer(),
                              if (images.length > 1)
                                Text(
                                    'Trang ${_previewPageIdx + 1}/${images.length}',
                                    style: GoogleFonts.dmSans(
                                        fontSize: 11,
                                        color: GradeFlowTheme.onSurfaceVariant)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: images[_previewPageIdx],
                              httpHeaders: _getAuthHeaders(),
                              width: double.infinity,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => Container(
                                height: 200,
                                color: GradeFlowTheme.surfaceContainer,
                                child: const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                height: 120,
                                color: GradeFlowTheme.surfaceContainer,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(LucideIcons.imageOff,
                                          size: 28,
                                          color:
                                              GradeFlowTheme.onSurfaceVariant),
                                      const SizedBox(height: 4),
                                      Text('Không tải được ảnh',
                                          style: GoogleFonts.dmSans(
                                              fontSize: 11,
                                              color: GradeFlowTheme
                                                  .onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (images.length > 1) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(images.length, (i) {
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _previewPageIdx = i),
                                  child: Container(
                                    width: 60,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _previewPageIdx == i
                                          ? GradeFlowTheme.primary
                                          : GradeFlowTheme.surfaceContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Trang ${i + 1}',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.dmSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _previewPageIdx == i
                                            ? Colors.white
                                            : GradeFlowTheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (!selected) const SizedBox(height: 14),
                ],
              ),
            ),
          );
        }),

        if (_selectedTemplate != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GradeFlowTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.info, size: 16, color: GradeFlowTheme.primary),
                const SizedBox(width: 8),
                Text('Cấu trúc: P1=$_p1Count · P2=$_p2Count · P3=$_p3Count · Tổng=$_totalQuestions câu',
                    style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }

  Map<String, String> _getAuthHeaders() {
    final auth = context.read<AuthService>();
    return {
      'Authorization': 'Token ${auth.token ?? ''}',
    };
  }

  Widget _partBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: GoogleFonts.manrope(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ── Step 3: Mã đề & Đáp án ──
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Thêm mã đề và nhập đáp án',
            style: GoogleFonts.dmSans(
                fontSize: 13, color: GradeFlowTheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        ..._variants.asMap().entries.map((entry) {
          final idx = entry.key;
          final v = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: v.codeCtrl,
                          decoration: InputDecoration(
                            labelText: 'Mã đề ${idx + 1}',
                            hintText: 'VD: 101',
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_variants.length > 1)
                        IconButton(
                          icon: const Icon(LucideIcons.trash2,
                              size: 18, color: Colors.red),
                          onPressed: () =>
                              setState(() => _variants.removeAt(idx)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_p1Count > 0) ...[
                    Text('Phần I — Đáp án ABCD (${_p1Count} câu)',
                        style: GoogleFonts.dmSans(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _buildP1AnswerInputs(v),
                  ],
                  if (_p2Count > 0) ...[
                    const SizedBox(height: 8),
                    Text('Phần II — Đúng/Sai (${_p2Count} câu x 4 ý)',
                        style: GoogleFonts.dmSans(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _buildP2AnswerInputs(v),
                  ],
                  if (_p3Count > 0) ...[
                    const SizedBox(height: 8),
                    Text('Phần III — Trả lời ngắn (${_p3Count} câu)',
                        style: GoogleFonts.dmSans(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _buildP3AnswerInputs(v),
                  ],
                ],
              ),
            ),
          );
        }),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _variants.add(_VariantData())),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Thêm mã đề'),
          ),
        ),
      ],
    );
  }

  Widget _buildP1AnswerInputs(_VariantData v) {
    while (v.p1Answers.length < _p1Count) {
      v.p1Answers.add('');
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: List.generate(_p1Count, (i) {
        final qNum = i + 1;
        return SizedBox(
          width: 55,
          child: DropdownButtonFormField<String>(
            value: v.p1Answers[i].isNotEmpty ? v.p1Answers[i] : null,
            decoration: InputDecoration(
              labelText: '$qNum',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            ),
            items: ['A', 'B', 'C', 'D']
                .map((c) =>
                    DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13))))
                .toList(),
            onChanged: (val) {
              v.p1Answers[i] = val ?? '';
            },
            style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black),
          ),
        );
      }),
    );
  }

  Widget _buildP2AnswerInputs(_VariantData v) {
    while (v.p2Answers.length < _p2Count) {
      v.p2Answers.add({'a': '', 'b': '', 'c': '', 'd': ''});
    }
    return Column(
      children: List.generate(_p2Count, (i) {
        final qNum = _p1Count + i + 1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text('$qNum',
                    style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              ...['a', 'b', 'c', 'd'].map((sub) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: DropdownButtonFormField<String>(
                        value: v.p2Answers[i][sub]!.isNotEmpty
                            ? v.p2Answers[i][sub]
                            : null,
                        decoration: InputDecoration(
                          labelText: sub.toUpperCase(),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                        ),
                        items: ['Đ', 'S']
                            .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c,
                                    style: const TextStyle(fontSize: 11))))
                            .toList(),
                        onChanged: (val) {
                          v.p2Answers[i][sub] = val ?? '';
                        },
                        style: GoogleFonts.dmSans(fontSize: 11, color: Colors.black),
                      ),
                    ),
                  )),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildP3AnswerInputs(_VariantData v) {
    while (v.p3Ctrls.length < _p3Count) {
      v.p3Ctrls.add(TextEditingController());
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(_p3Count, (i) {
        final qNum = _p1Count + _p2Count + i + 1;
        return SizedBox(
          width: 80,
          child: TextFormField(
            controller: v.p3Ctrls[i],
            decoration: InputDecoration(
              labelText: 'C$qNum',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        );
      }),
    );
  }
}

class _VariantData {
  final codeCtrl = TextEditingController();
  List<String> p1Answers = [];
  List<Map<String, String>> p2Answers = [];
  List<TextEditingController> p3Ctrls = [];

  Map<String, dynamic> buildP1Answers(int count) {
    final map = <String, dynamic>{};
    for (int i = 0; i < count && i < p1Answers.length; i++) {
      if (p1Answers[i].isNotEmpty) {
        map['${i + 1}'] = p1Answers[i];
      }
    }
    return map;
  }

  Map<String, dynamic> buildP2Answers(int count) {
    final map = <String, dynamic>{};
    for (int i = 0; i < count && i < p2Answers.length; i++) {
      final sub = <String, String>{};
      p2Answers[i].forEach((k, v) {
        if (v.isNotEmpty) sub[k] = v;
      });
      if (sub.isNotEmpty) map['${i + 1}'] = sub;
    }
    return map;
  }

  Map<String, dynamic> buildP3Answers(int count) {
    final map = <String, dynamic>{};
    for (int i = 0; i < count && i < p3Ctrls.length; i++) {
      final v = p3Ctrls[i].text.trim();
      if (v.isNotEmpty) map['${i + 1}'] = v;
    }
    return map;
  }
}
