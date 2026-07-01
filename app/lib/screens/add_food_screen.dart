import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../providers.dart';
import '../theme.dart';

// Macro accent colours (shared with the scan result sheet).
const _proteinColor = Color(0xFFC25A4E);
const _carbsColor = Color(0xFFBF8A23);
const _fatColor = Color(0xFF5A66B8);

// Capture-shell tokens (dark viewfinder + lighter reticle green).
const _shell = Color(0xFF11150F);
const _reticle = Color(0xFF7BDCAB);

// Honey-tinted tip callout background.
const _tipBg = Color(0xFFFDF6E6);

/// The "Add a new food" flow (B1–B5): name + capture the Nutrition Facts label,
/// the AI extracts calories & macros, you check/fix the details, save it as a
/// user food, then log it. Entry route is `/food/new`; an [initialBarcode]
/// (from a failed scan) is linked to the saved food so the next scan matches.
///
/// The whole flow lives in one screen as an internal step machine so the typed
/// name, the captured photo, the extraction, and the user's edits all share
/// state without route plumbing.
class AddFoodScreen extends ConsumerStatefulWidget {
  const AddFoodScreen({super.key, this.initialBarcode});
  final String? initialBarcode;

  @override
  ConsumerState<AddFoodScreen> createState() => _AddFoodScreenState();
}

enum _Step { hub, capture, reading, check, saved }

/// What the camera step is capturing — the label (required, drives extraction)
/// or an optional front-of-package photo (held in memory, never blocks).
enum _Target { label, front }

/// A single editable field in the "Check the details" screen: its text, the
/// confidence the extractor reported, and whether the user has edited it
/// (an edit clears the flag and counts as confirmed).
class _Field {
  _Field();
  final TextEditingController controller = TextEditingController();
  ConfidenceTier? confidence; // null => unread / needs input
  bool edited = false;

  void seed(LabelField<Object> f) {
    final v = f.value;
    controller.text = v == null ? '' : _fmt(v);
    confidence = f.confidence;
    edited = false;
  }

  static String _fmt(Object v) {
    if (v is num) {
      return v == v.roundToDouble() ? v.round().toString() : '$v';
    }
    return '$v';
  }

  String get text => controller.text.trim();
  bool get isEmpty => text.isEmpty;
  double? get number => double.tryParse(text);

  void dispose() => controller.dispose();
}

class _AddFoodScreenState extends ConsumerState<AddFoodScreen> {
  _Step _step = _Step.hub;
  _Target _target = _Target.label;

  final _name = _Field();
  final _brand = _Field();
  final _servingLabel = _Field();
  final _servingGrams = _Field();
  final _calories = _Field();
  final _protein = _Field();
  final _carbs = _Field();
  final _fat = _Field();

  late final List<_Field> _allFields = [
    _name, _brand, _servingLabel, _servingGrams,
    _calories, _protein, _carbs, _fat,
  ];

  Uint8List? _labelBytes; // the captured Nutrition Facts photo
  Uint8List? _frontBytes; // optional front-of-package photo (held only)

  bool _saving = false;
  Food? _savedFood;

  @override
  void initState() {
    super.initState();
    // The B1 CTA enables once a name is typed.
    _name.controller.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name.controller.removeListener(_onNameChanged);
    for (final f in _allFields) {
      f.dispose();
    }
    super.dispose();
  }

  void _onNameChanged() {
    if (_step == _Step.hub) setState(() {});
  }

  // ===== flow transitions =====

  void _openCapture(_Target target) {
    setState(() {
      _target = target;
      _step = _Step.capture;
    });
  }

  void _onCaptured(Uint8List bytes) {
    if (_target == _Target.front) {
      setState(() {
        _frontBytes = bytes;
        _step = _Step.hub;
      });
      _snack('Front photo added');
      return;
    }
    _labelBytes = bytes;
    setState(() => _step = _Step.reading);
    _readLabel(bytes);
  }

  Future<void> _readLabel(Uint8List bytes) async {
    try {
      final result = await ref.read(apiProvider).extractLabel(
            imageBase64: base64Encode(bytes),
          );
      if (!mounted) return;
      _applyExtraction(result);
      setState(() => _step = _Step.check);
    } catch (_) {
      if (!mounted) return;
      // 503 / network / parse failure → manual entry with empty fields.
      _applyExtraction(LabelExtraction.empty);
      setState(() => _step = _Step.check);
      _snack("Couldn't read the label — enter the details");
    }
  }

  /// Skip the camera entirely (camera unavailable) and go straight to manual entry.
  void _skipToManual() {
    _applyExtraction(LabelExtraction.empty);
    setState(() => _step = _Step.check);
  }

  void _applyExtraction(LabelExtraction e) {
    // The hub name takes precedence if the user already typed one.
    final typedName = _name.text;
    _name.seed(e.name);
    if (typedName.isNotEmpty && _name.isEmpty) {
      _name.controller.text = typedName;
    }
    _brand.seed(e.brand);
    _servingLabel.seed(e.servingSizeLabel);
    _servingGrams.seed(e.servingSizeGrams);
    _calories.seed(e.calories);
    _protein.seed(e.protein);
    _carbs.seed(e.carbs);
    _fat.seed(e.fat);
  }

  // ===== save (B4 → B5) =====

  /// Per-serving → per-100 g. Guards a missing/zero serving size by treating the
  /// serving as 100 g (so the per-serving number is used as-is).
  double _per100g(double perServing) {
    final grams = _servingGrams.number ?? 0;
    if (grams <= 0) return perServing;
    return perServing * 100 / grams;
  }

  Future<void> _save() async {
    if (_name.isEmpty || _calories.number == null) {
      _snack('Name and calories are required');
      return;
    }
    setState(() => _saving = true);
    final grams = _servingGrams.number;
    try {
      final food = await ref.read(apiProvider).createUserFood({
        'name': _name.text,
        'brand': _brand.isEmpty ? null : _brand.text,
        // Send the scanned barcode so the next scan of this product matches.
        'barcode': widget.initialBarcode,
        'servingSizeGrams': (grams != null && grams > 0) ? grams : null,
        'servingSizeLabel': _servingLabel.isEmpty ? null : _servingLabel.text,
        'caloriesPer100g': _per100g(_calories.number ?? 0),
        'proteinPer100g': _per100g(_protein.number ?? 0),
        'carbsPer100g': _per100g(_carbs.number ?? 0),
        'fatPer100g': _per100g(_fat.number ?? 0),
      });
      if (!mounted) return;
      setState(() {
        _savedFood = food;
        _saving = false;
        _step = _Step.saved;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not save: $e');
    }
  }

  void _logToDiary() {
    final food = _savedFood;
    if (food == null) return;
    final api = ref.read(apiProvider);
    ref.read(addSessionProvider.notifier).loadRows(
      Meal.forTimeOfDay(DateTime.now()),
      AddSource.manual,
      [api.reviewRowFromFood(food, id: 'new_0')],
    );
    context.go('/add/review');
  }

  // ===== editing =====

  Future<void> _editField(
    _Field field,
    String label, {
    bool number = false,
  }) async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FieldEditor(
        label: label,
        initial: field.controller.text,
        number: number,
      ),
    );
    if (saved == null) return;
    setState(() {
      field.controller.text = saved.trim();
      field.edited = true; // an edit is a confirmation
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  // ===== build =====

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _Step.hub => _buildHub(context),
      _Step.capture => _LabelCamera(
          target: _target,
          onCapture: _onCaptured,
          onClose: () => setState(() => _step = _Step.hub),
          onManual: _target == _Target.label ? _skipToManual : null,
        ),
      _Step.reading => _ReadingView(onBack: () => setState(() => _step = _Step.hub)),
      _Step.check => _buildCheck(context),
      _Step.saved => _buildSaved(context),
    };
  }

  // ----- B1: capture hub -----

  Widget _buildHub(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    final canContinue = _name.text.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Add a new food')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text(
            'Give it a name, then snap the Nutrition Facts panel. A package photo is optional.',
            style: TextStyle(color: t.subtle, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 20),

          // (1) Name — required white card with a grove border.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: grove, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NAME',
                    style: TextStyle(
                        color: grove,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                TextField(
                  controller: _name.controller,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(
                      color: t.ink, fontSize: 17, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'e.g. Protein Granola',
                    hintStyle: TextStyle(color: t.muted, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // (2) Nutrition Facts panel — required.
          _CaptureCard(
            title: 'Nutrition Facts panel',
            caption: 'Tap to capture — fills calories & macros',
            icon: Icons.center_focus_strong,
            badgeLabel: 'REQUIRED',
            badgeBg: t.checkBg,
            badgeFg: t.checkFg,
            captured: _labelBytes != null,
            dashed: false,
            onTap: () => _openCapture(_Target.label),
          ),
          const SizedBox(height: 12),

          // (3) Front of package — optional, never blocks, not persisted.
          _CaptureCard(
            title: 'Front of package',
            caption: 'Optional — helps you recognise it later',
            icon: Icons.image_outlined,
            badgeLabel: 'OPTIONAL',
            badgeBg: t.noMatchBg,
            badgeFg: t.muted,
            captured: _frontBytes != null,
            dashed: true,
            onTap: () => _openCapture(_Target.front),
          ),
          const SizedBox(height: 16),

          // (4) Tip callout.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _tipBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: t.honey),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hold steady and fill the frame with the Nutrition Facts panel — '
                    'good light means fewer fixes.',
                    style: TextStyle(
                        color: const Color(0xFF7A5A1E),
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: canContinue ? () => _openCapture(_Target.label) : null,
              style: FilledButton.styleFrom(
                backgroundColor: grove,
                disabledBackgroundColor: grove.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Capture the label',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  // ----- B4: check & save -----

  Widget _buildCheck(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check the details'),
        leading: BackButton(onPressed: () => setState(() => _step = _Step.hub)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text(
            'From your photos — tap any field to fix.',
            style: TextStyle(color: t.subtle, fontSize: 14),
          ),
          const SizedBox(height: 18),

          // Name (required).
          _EditableField(
            label: 'NAME',
            value: _name.text.isEmpty ? 'Add a name' : _name.text,
            placeholder: _name.isEmpty,
            state: _stateOf(_name),
            onTap: () => _editField(_name, 'Name'),
          ),
          const SizedBox(height: 12),

          // Brand + Serving row.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _EditableField(
                  label: 'BRAND',
                  value: _brand.text.isEmpty ? 'Optional' : _brand.text,
                  placeholder: _brand.isEmpty,
                  state: _stateOf(_brand),
                  onTap: () => _editField(_brand, 'Brand'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _EditableField(
                  label: 'SERVING',
                  value:
                      _servingLabel.text.isEmpty ? 'e.g. 1 cup (45 g)' : _servingLabel.text,
                  placeholder: _servingLabel.isEmpty,
                  // Serving uses the Estimated treatment per spec.
                  state: _servingLabel.edited
                      ? _FieldUi.edited
                      : _FieldUi.estimated,
                  onTap: () => _editField(_servingLabel, 'Serving (label)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Serving size in grams (drives the per-100 g conversion).
          _EditableField(
            label: 'SERVING SIZE (G)',
            value: _servingGrams.text.isEmpty ? 'e.g. 45' : _servingGrams.text,
            placeholder: _servingGrams.isEmpty,
            state: _stateOf(_servingGrams),
            onTap: () => _editField(_servingGrams, 'Serving size (g)', number: true),
          ),
          const SizedBox(height: 12),

          // Calories (required) — per serving.
          _EditableField(
            label: 'CALORIES (PER SERVING)',
            value: _calories.text.isEmpty ? 'Required' : '${_calories.text} kcal',
            placeholder: _calories.isEmpty,
            state: _stateOf(_calories),
            big: true,
            onTap: () => _editField(_calories, 'Calories (per serving)', number: true),
          ),
          const SizedBox(height: 12),

          // Macros grid (per serving).
          Row(
            children: [
              Expanded(
                child: _MacroCell(
                  label: 'PROTEIN',
                  value: _protein.text,
                  color: _proteinColor,
                  state: _stateOf(_protein),
                  onTap: () => _editField(_protein, 'Protein (g)', number: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MacroCell(
                  label: 'CARBS',
                  value: _carbs.text,
                  color: _carbsColor,
                  state: _stateOf(_carbs),
                  onTap: () => _editField(_carbs, 'Carbs (g)', number: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MacroCell(
                  label: 'FAT',
                  value: _fat.text,
                  color: _fatColor,
                  state: _stateOf(_fat),
                  onTap: () => _editField(_fat, 'Fat (g)', number: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: grove,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save food',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  _FieldUi _stateOf(_Field f) {
    if (f.edited) return _FieldUi.edited;
    return switch (f.confidence) {
      ConfidenceTier.verified => _FieldUi.verified,
      ConfidenceTier.estimated => _FieldUi.estimated,
      _ => _FieldUi.needsInput,
    };
  }

  // ----- B5: saved -----

  Widget _buildSaved(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    final food = _savedFood!;
    final perServing = (food.servingSizeGrams ?? 100) > 0
        ? food.servingSizeGrams ?? 100
        : 100.0;
    final kcal = food.caloriesPer100g * perServing / 100.0;
    final summary = [
      if (food.brand != null && food.brand!.isNotEmpty) food.brand!,
      '${kcal.round()} kcal / ${(food.proteinPer100g * perServing / 100).round()} g protein',
    ].join('  ·  ');

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: grove, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Added to your foods',
                  style: TextStyle(
                      color: t.ink, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                "Next time it'll match instantly — by name or barcode.",
                textAlign: TextAlign.center,
                style: TextStyle(color: t.subtle, fontSize: 14, height: 1.35),
              ),
              const SizedBox(height: 24),

              // Summary card.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(food.name,
                        style: TextStyle(
                            color: t.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(summary,
                        style: TextStyle(color: t.muted, fontSize: 13)),
                  ],
                ),
              ),

              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _logToDiary,
                  style: FilledButton.styleFrom(
                    backgroundColor: grove,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Log to diary',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => context.go('/'),
                  style: TextButton.styleFrom(foregroundColor: t.subtle),
                  child: const Text('Done',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ B1 capture cards ============================

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.title,
    required this.caption,
    required this.icon,
    required this.badgeLabel,
    required this.badgeBg,
    required this.badgeFg,
    required this.captured,
    required this.dashed,
    required this.onTap,
  });
  final String title;
  final String caption;
  final IconData icon;
  final String badgeLabel;
  final Color badgeBg;
  final Color badgeFg;
  final bool captured;
  final bool dashed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: captured ? t.verifiedBg : t.paper,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(captured ? Icons.check : icon,
                color: captured ? t.verifiedFg : t.subtle, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          style: TextStyle(
                              color: t.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                    _Badge(label: badgeLabel, bg: badgeBg, fg: badgeFg),
                  ],
                ),
                const SizedBox(height: 2),
                Text(captured ? 'Captured — tap to retake' : caption,
                    style: TextStyle(color: t.muted, fontSize: 12.5)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: t.muted),
        ],
      ),
    );

    final radius = BorderRadius.circular(16);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: dashed
            ? CustomPaint(
                painter: _DashedBorderPainter(
                    color: t.muted.withValues(alpha: 0.7), radius: 16),
                child: content,
              )
            : Container(
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: radius,
                  border: Border.all(color: t.hairline),
                ),
                child: content,
              ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 6.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(
            metric.extractPath(dist, dist + dash), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ============================ B2 label camera ============================

class _LabelCamera extends StatefulWidget {
  const _LabelCamera({
    required this.target,
    required this.onCapture,
    required this.onClose,
    this.onManual,
  });
  final _Target target;
  final void Function(Uint8List bytes) onCapture;
  final VoidCallback onClose;
  final VoidCallback? onManual;

  @override
  State<_LabelCamera> createState() => _LabelCameraState();
}

class _LabelCameraState extends State<_LabelCamera> {
  CameraController? _controller;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _error = 'No camera available');
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(back, ResolutionPreset.high,
          enableAudio: false);
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _controller = ctrl);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _shutter() async {
    final ctrl = _controller;
    if (ctrl == null || _capturing || !ctrl.value.isInitialized) return;
    setState(() => _capturing = true);
    try {
      final file = await ctrl.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      widget.onCapture(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Capture failed — try again')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final title = widget.target == _Target.label
        ? 'Capture the label'
        : 'Front of package';
    final hint = widget.target == _Target.label
        ? 'Line up the Nutrition Facts panel'
        : 'Frame the front of the package';

    if (_error != null) {
      return _CameraError(
          message: _error!, onManual: widget.onManual, onClose: widget.onClose);
    }

    return Scaffold(
      backgroundColor: _shell,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ctrl != null && ctrl.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: ctrl.value.previewSize?.height ?? 1080,
                height: ctrl.value.previewSize?.width ?? 1920,
                child: CameraPreview(ctrl),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: _reticle)),

          // Portrait label guide + dim mask.
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _LabelGuidePainter())),
          ),

          // Top chrome: close + title.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _CircleControl(icon: Icons.close, onTap: widget.onClose),
                  Expanded(
                    child: Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),

          // Hint.
          Positioned(
            left: 24,
            right: 24,
            bottom: 150,
            child: Text(hint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                )),
          ),

          // Shutter.
          Positioned(
            bottom: 44,
            left: 0,
            right: 0,
            child: Center(child: _Shutter(busy: _capturing, onTap: _shutter)),
          ),
        ],
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 4),
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(strokeWidth: 2, color: _shell),
              )
            : null,
      ),
    );
  }
}

class _CircleControl extends StatelessWidget {
  const _CircleControl({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _LabelGuidePainter extends CustomPainter {
  const _LabelGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Portrait, label-shaped window centred a touch above the middle.
    final w = size.width * 0.62;
    final h = w * 1.4;
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: w,
      height: h,
    );
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(16));

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF080B06).withValues(alpha: 0.6));
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // Corner brackets.
    final p = Paint()
      ..color = _reticle
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    final l = window.left, t = window.top, r = window.right, b = window.bottom;
    final path = Path()
      ..moveTo(l, t + len)..lineTo(l, t + 12)..arcToPoint(Offset(l + 12, t), radius: const Radius.circular(12))..lineTo(l + len, t)
      ..moveTo(r - len, t)..lineTo(r - 12, t)..arcToPoint(Offset(r, t + 12), radius: const Radius.circular(12))..lineTo(r, t + len)
      ..moveTo(r, b - len)..lineTo(r, b - 12)..arcToPoint(Offset(r - 12, b), radius: const Radius.circular(12))..lineTo(r - len, b)
      ..moveTo(l + len, b)..lineTo(l + 12, b)..arcToPoint(Offset(l, b - 12), radius: const Radius.circular(12))..lineTo(l, b - len);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_LabelGuidePainter old) => false;
}

class _CameraError extends StatelessWidget {
  const _CameraError(
      {required this.message, required this.onManual, required this.onClose});
  final String message;
  final VoidCallback? onManual;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: onClose)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_camera_outlined, color: t.subtle, size: 44),
              const SizedBox(height: 16),
              Text('Camera unavailable',
                  style: TextStyle(
                      color: t.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'You can still add the food by entering the details yourself.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.subtle, fontSize: 13),
              ),
              if (onManual != null) ...[
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: onManual,
                    style: FilledButton.styleFrom(
                      backgroundColor: grove,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Enter details manually',
                        style:
                            TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ B3 reading view ============================

class _ReadingView extends StatelessWidget {
  const _ReadingView({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add a new food'),
        leading: BackButton(onPressed: onBack),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: grove),
              ),
              const SizedBox(width: 12),
              Text('Reading the label…',
                  style: TextStyle(
                      color: t.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 24),
          for (final h in const [56.0, 56.0, 80.0, 90.0])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _Shimmer(height: h),
            ),
        ],
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.height});
  final double height;
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(t.card, t.hairline, _c.value),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.hairline),
        ),
      ),
    );
  }
}

// ============================ B4 editable fields ============================

/// Visual treatment for a checkable field.
enum _FieldUi { verified, estimated, edited, needsInput }

extension on _FieldUi {
  /// (glyph, label); null glyph means no chip.
  (String?, String) get chip => switch (this) {
        _FieldUi.verified => ('✓', 'read'),
        _FieldUi.estimated => ('≈', 'check'),
        _FieldUi.edited => ('✓', 'edited'),
        _FieldUi.needsInput => (null, 'add'),
      };
}

class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.state,
    required this.onTap,
    this.big = false,
  });
  final String label;
  final String value;
  final bool placeholder;
  final _FieldUi state;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final estimated = state == _FieldUi.estimated;
    final needs = state == _FieldUi.needsInput;
    final borderColor = estimated
        ? t.estimatedFg.withValues(alpha: 0.55)
        : needs
            ? t.checkFg.withValues(alpha: 0.5)
            : t.hairline;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 12, 12),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: borderColor, width: (estimated || needs) ? 1.4 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            color: t.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6)),
                  ),
                  _ConfTag(state: state),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: big
                    ? displayNumber(context, size: 26)
                    : TextStyle(
                        color: placeholder ? t.muted : t.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfTag extends StatelessWidget {
  const _ConfTag({required this.state});
  final _FieldUi state;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final (glyph, label) = state.chip;
    final (bg, fg) = switch (state) {
      _FieldUi.verified => (t.verifiedBg, t.verifiedFg),
      _FieldUi.estimated => (t.estimatedBg, t.estimatedFg),
      _FieldUi.edited => (t.verifiedBg, t.verifiedFg),
      _FieldUi.needsInput => (t.checkBg, t.checkFg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            Text(glyph,
                style: TextStyle(
                    color: fg, fontSize: 10, fontWeight: FontWeight.w800)),
            const SizedBox(width: 3),
          ],
          Text(label,
              style:
                  TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MacroCell extends StatelessWidget {
  const _MacroCell({
    required this.label,
    required this.value,
    required this.color,
    required this.state,
    required this.onTap,
  });
  final String label;
  final String value;
  final Color color;
  final _FieldUi state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final estimated = state == _FieldUi.estimated;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: estimated
                  ? t.estimatedFg.withValues(alpha: 0.55)
                  : color.withValues(alpha: 0.25),
              width: estimated ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4)),
              const SizedBox(height: 6),
              Text(value.isEmpty ? '—' : '$value g',
                  style: TextStyle(
                      color: value.isEmpty ? t.muted : t.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              _ConfTag(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ field editor sheet ============================

class _FieldEditor extends StatefulWidget {
  const _FieldEditor({
    required this.label,
    required this.initial,
    required this.number,
  });
  final String label;
  final String initial;
  final bool number;

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_c.text);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
              style: TextStyle(
                  color: t.ink, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: widget.number
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            textCapitalization: widget.number
                ? TextCapitalization.none
                : TextCapitalization.words,
            inputFormatters: widget.number
                ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                : null,
            onSubmitted: (_) => _done(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: grove, width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _done,
              style: FilledButton.styleFrom(
                backgroundColor: grove,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Done',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
