import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../models.dart';
import '../providers.dart';
import '../settings.dart';
import '../theme.dart';

// Camera-shell tokens from the scan handoff (dark viewfinder + lighter reticle green).
const _shell = Color(0xFF11150F);
const _reticle = Color(0xFF7BDCAB);

/// Barcode scan — the hero path. State machine per the design handoff:
/// acquiring → locked (looking up) → match (result sheet) | notFound | permissionDenied.
/// Uses flutter_zxing (zxing-cpp) for the camera + decode — NOT Google MLKit, whose
/// barcode client null-crashes on some devices. A match adds to a meal in one tap.
enum _ScanState { acquiring, locked, match, notFound, permissionDenied }

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  _ScanState _state = _ScanState.acquiring;
  CameraController? _camera;
  bool _torchOn = false;

  String? _code; // last scanned barcode
  Food? _food; // resolved match (A3)
  bool _adding = false;

  // Result-sheet quantity controls.
  double _qty = 1;
  Meal _meal = Meal.snacks;

  // Multi-scan dev mode: collect unique codes across frames, then batch-review.
  final Set<String> _scanned = <String>{};

  bool get _hasServing => (_food?.servingSizeGrams ?? 0) > 0;
  double get _grams => _hasServing ? _qty * _food!.servingSizeGrams! : _qty;
  double get _kcal => (_food?.caloriesPer100g ?? 0) * _grams / 100.0;
  double _macro(double per100g) => per100g * _grams / 100.0;

  // ===== detection =====

  void _onScan(Code code) {
    final text = code.text;
    if (text == null || text.isEmpty) return;
    if (_state != _ScanState.acquiring) return;
    setState(() {
      _state = _ScanState.locked;
      _code = text;
    });
    _lookup(text);
  }

  Future<void> _lookup(String code) async {
    try {
      final food = await ref.read(apiProvider).getFoodByBarcode(code);
      if (!mounted) return;
      setState(() {
        _food = food;
        _qty = (food.servingSizeGrams ?? 0) > 0 ? 1 : 100;
        _meal = Meal.forTimeOfDay(DateTime.now());
        _state = _ScanState.match;
      });
    } on NotFoundException {
      if (mounted) setState(() => _state = _ScanState.notFound);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Lookup failed — try again.');
      setState(() => _state = _ScanState.acquiring);
    }
  }

  void _onMultiScan(Codes codes) {
    var added = false;
    for (final c in codes.codes) {
      final t = c.text;
      if (t != null && t.isNotEmpty && _scanned.add(t)) added = true;
    }
    if (added && mounted) setState(() {});
  }

  /// Multi-scan: resolve all collected codes and hand off to the review surface (E2).
  Future<void> _reviewScanned() async {
    if (_adding || _scanned.isEmpty) return;
    setState(() => _adding = true);
    final api = ref.read(apiProvider);
    final rows = <ReviewRow>[];
    var i = 0;
    for (final code in _scanned) {
      try {
        rows.add(api.reviewRowFromFood(await api.getFoodByBarcode(code), id: 'scan_${i++}'));
      } on NotFoundException {
        rows.add(ReviewRow(
          id: 'scan_${i++}', rawText: 'Barcode $code', match: null,
          candidates: const [], quantity: 1, unit: QuantityUnit.servings,
          grams: 0, calories: 0, tier: ConfidenceTier.noMatch));
      } catch (_) {/* skip transient */}
    }
    if (!mounted) return;
    if (rows.isEmpty) {
      setState(() => _adding = false);
      _showSnack('Could not resolve any of the scanned barcodes.');
      return;
    }
    ref.read(addSessionProvider.notifier)
        .loadRows(Meal.forTimeOfDay(DateTime.now()), AddSource.scan, rows);
    context.pushReplacement('/add/review');
  }

  // ===== result-sheet actions (A3) =====

  Future<void> _add() async {
    final food = _food;
    if (food == null || _adding) return;
    setState(() => _adding = true);
    try {
      await ref.read(apiProvider).addDiaryEntry(
            foodId: food.id,
            date: ref.read(selectedDateProvider),
            meal: _meal,
            quantity: _grams,
            unit: QuantityUnit.grams,
          );
      ref.invalidate(diaryProvider);
      if (!mounted) return;
      context.go('/');
      _showSnack('Added ${food.name} to ${_meal.label}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      _showSnack('Could not add — try again.');
    }
  }

  void _scanAnother() => setState(() {
        _state = _ScanState.acquiring;
        _food = null;
        _code = null;
        _qty = 1;
      });

  void _step(double delta) {
    final step = _hasServing ? 1.0 : 10.0;
    final min = _hasServing ? 0.5 : 10.0;
    setState(() => _qty = (_qty + delta * step).clamp(min, 9999).toDouble());
  }

  Future<void> _pickMeal() async {
    final picked = await showModalBottomSheet<Meal>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in Meal.values)
              ListTile(
                leading: Icon(m == _meal ? Icons.check : Icons.restaurant_menu,
                    color: m == _meal ? Theme.of(ctx).colorScheme.primary : null),
                title: Text(m.label),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _meal = picked);
  }

  // ===== misc =====

  Future<void> _toggleTorch() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      await cam.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {/* device rejected torch */}
  }

  void _onCameraError(Object? error) {
    final s = error?.toString().toLowerCase() ?? '';
    if ((s.contains('permission') || s.contains('denied') || s.contains('access')) &&
        mounted &&
        _state == _ScanState.acquiring) {
      setState(() => _state = _ScanState.permissionDenied);
    }
  }

  /// Pick a photo from the gallery and decode a barcode out of it (zxing-cpp),
  /// so a saved image works when the live camera isn't handy.
  Future<void> _pickFromGallery() async {
    if (_state != _ScanState.acquiring) return;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      final code = await zx.readBarcodeImagePath(
        picked,
        DecodeParams(format: Format.any, tryHarder: true, tryInverted: true),
      );
      if (!mounted) return;
      final text = code.text;
      if (code.isValid && text != null && text.isNotEmpty) {
        setState(() {
          _state = _ScanState.locked;
          _code = text;
        });
        _lookup(text);
      } else {
        _showSnack('No barcode found in that image.');
      }
    } catch (_) {
      if (mounted) _showSnack("Couldn't read that image.");
    }
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'e.g. 3017620422003'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Look up'),
          ),
        ],
      ),
    );
    if (code != null && code.isNotEmpty && mounted) {
      setState(() {
        _state = _ScanState.locked;
        _code = code;
      });
      _lookup(code);
    }
  }

  void _close() => context.canPop() ? context.pop() : context.go('/');
  void _showSnack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ===== build =====

  @override
  Widget build(BuildContext context) {
    final multiScan = ref.watch(devSettingsProvider).multiScan;

    if (_state == _ScanState.permissionDenied) {
      return _PermissionDeniedView(onManual: _manualEntry, onBack: _close);
    }

    final locked = _state == _ScanState.locked;
    final showSheet = _state == _ScanState.match || _state == _ScanState.notFound;

    return Scaffold(
      backgroundColor: _shell,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          // Wide, barcode-shaped reticle (~218:128), centred a touch above middle.
          final w = size.width * 0.64;
          final h = w * 0.587;
          final window = Rect.fromCenter(
            center: Offset(size.width / 2, size.height * 0.40),
            width: w,
            height: h,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera + decoder. Single mode → onScan; dev multi mode → onMultiScan.
              ReaderWidget(
                onScan: multiScan ? null : _onScan,
                onMultiScan: multiScan ? _onMultiScan : null,
                isMultiScan: multiScan,
                onControllerCreated: (controller, error) {
                  _camera = controller;
                  _onCameraError(error);
                },
                codeFormat: Format.any,
                tryHarder: true,
                tryInverted: true,
                showScannerOverlay: false,
                showFlashlight: false,
                showToggleCamera: false,
                showGallery: false,
                scanDelaySuccess: const Duration(seconds: 2),
                cropPercent: 0.9,
                loading: const DecoratedBox(
                  decoration: BoxDecoration(color: _shell),
                  child: Center(child: CircularProgressIndicator(color: _reticle)),
                ),
              ),

              // Reticle + dim mask (brackets while acquiring, solid frame when locked).
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ReticlePainter(
                      window: window,
                      locked: locked || showSheet,
                      dim: showSheet ? 0.66 : (locked ? 0.6 : 0.5),
                    ),
                  ),
                ),
              ),

              // Sweeping scan line (acquiring only).
              if (_state == _ScanState.acquiring && !multiScan)
                Positioned.fromRect(
                  rect: window,
                  child: const IgnorePointer(child: _ScanLine()),
                ),

              // ✓ badge at the reticle's top-right when locked/matched.
              if (locked || _state == _ScanState.match)
                Positioned(
                  left: window.right - 15,
                  top: window.top - 15,
                  child: const _CheckBadge(),
                ),

              // Top chrome: close · title · flash.
              _TopBar(
                title: multiScan ? 'Scan barcodes' : 'Scan a barcode',
                torchOn: _torchOn,
                onClose: _close,
                onTorch: _toggleTorch,
              ),

              // Hint under the reticle.
              if (!showSheet)
                Positioned(
                  top: size.height * 0.6,
                  left: 24,
                  right: 24,
                  child: Text(
                    multiScan
                        ? 'Scan each barcode — tap Review when done'
                        : locked
                            ? ''
                            : 'Point at a barcode',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                    ),
                  ),
                ),

              // A2: "Looking up <code>" pill.
              if (locked)
                Positioned(
                  top: size.height * 0.6,
                  left: 0,
                  right: 0,
                  child: Center(child: _LookingUpPill(code: _code ?? '')),
                ),

              // A1: gallery + manual-entry controls (single mode, acquiring).
              if (_state == _ScanState.acquiring && !multiScan) ...[
                Positioned(
                  bottom: 26,
                  left: 24,
                  child: _CircleControl(
                    icon: Icons.photo_library_outlined,
                    onTap: _pickFromGallery,
                  ),
                ),
                Positioned(
                  bottom: 28,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _GhostPill(
                      icon: Icons.keyboard,
                      label: 'Enter code manually',
                      onTap: _manualEntry,
                    ),
                  ),
                ),
              ],

              // Dev multi-scan tally + review.
              if (multiScan && _scanned.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 28,
                  child: _MultiScanBar(
                    count: _scanned.length,
                    busy: _adding,
                    onReview: _reviewScanned,
                    onClear: () => setState(_scanned.clear),
                  ),
                ),

              // A3 / A4: result sheet rises over the dimmed camera.
              if (_state == _ScanState.match)
                _ResultSheet(
                  food: _food!,
                  qty: _qty,
                  hasServing: _hasServing,
                  grams: _grams,
                  kcal: _kcal,
                  macro: _macro,
                  meal: _meal,
                  adding: _adding,
                  onStep: _step,
                  onPickMeal: _pickMeal,
                  onAdd: _add,
                  onScanAnother: _scanAnother,
                ),
              if (_state == _ScanState.notFound)
                _NotFoundSheet(
                  code: _code ?? '',
                  onAddFromLabel: () =>
                      context.pushReplacement('/food/new', extra: _code),
                  onSearch: () => context.pushReplacement('/search'),
                  onManual: () => context.pushReplacement('/food/new', extra: _code),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ============================ chrome ============================

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.torchOn,
    required this.onClose,
    required this.onTorch,
  });
  final String title;
  final bool torchOn;
  final VoidCallback onClose;
  final VoidCallback onTorch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _CircleControl(icon: Icons.close, onTap: onClose),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            _CircleControl(
              icon: torchOn ? Icons.flash_on : Icons.flash_off,
              onTap: onTorch,
            ),
          ],
        ),
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

class _GhostPill extends StatelessWidget {
  const _GhostPill({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LookingUpPill extends StatelessWidget {
  const _LookingUpPill({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _reticle),
          ),
          const SizedBox(width: 10),
          Text('Looking up ',
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          Text(
            code,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        color: Color(0xFF2F8F5B),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, color: Colors.white, size: 18),
    );
  }
}

// ============================ reticle paint ============================

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.window, required this.locked, required this.dim});
  final Rect window;
  final bool locked;
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(18));
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromRGBO(8, 11, 6, dim));
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    if (locked) {
      // Solid frame.
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = _reticle
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    } else {
      // L-shaped corner brackets.
      final p = Paint()
        ..color = _reticle
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      const len = 24.0;
      final l = window.left, t = window.top, r = window.right, b = window.bottom;
      final path = Path()
        ..moveTo(l, t + len)..lineTo(l, t + 12)..arcToPoint(Offset(l + 12, t), radius: const Radius.circular(12))..lineTo(l + len, t)
        ..moveTo(r - len, t)..lineTo(r - 12, t)..arcToPoint(Offset(r, t + 12), radius: const Radius.circular(12))..lineTo(r, t + len)
        ..moveTo(r, b - len)..lineTo(r, b - 12)..arcToPoint(Offset(r - 12, b), radius: const Radius.circular(12))..lineTo(r - len, b)
        ..moveTo(l + len, b)..lineTo(l + 12, b)..arcToPoint(Offset(l, b - 12), radius: const Radius.circular(12))..lineTo(l, b - len);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter old) =>
      old.window != window || old.locked != locked || old.dim != dim;
}

class _ScanLine extends StatefulWidget {
  const _ScanLine();
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Align(
        alignment: Alignment(0, _c.value * 2 - 1),
        child: Container(
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.transparent, _reticle, Colors.transparent],
            ),
            boxShadow: [BoxShadow(color: _reticle.withValues(alpha: 0.8), blurRadius: 10)],
          ),
        ),
      ),
    );
  }
}

// ============================ A3 result sheet ============================

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({
    required this.food,
    required this.qty,
    required this.hasServing,
    required this.grams,
    required this.kcal,
    required this.macro,
    required this.meal,
    required this.adding,
    required this.onStep,
    required this.onPickMeal,
    required this.onAdd,
    required this.onScanAnother,
  });

  final Food food;
  final double qty;
  final bool hasServing;
  final double grams;
  final double kcal;
  final double Function(double per100g) macro;
  final Meal meal;
  final bool adding;
  final void Function(double delta) onStep;
  final VoidCallback onPickMeal;
  final VoidCallback onAdd;
  final VoidCallback onScanAnother;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    final unitLabel = hasServing
        ? '${food.servingSizeLabel ?? 'serving'} · ${food.servingSizeGrams!.round()} g'
        : '${grams.round()} g';
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 40, offset: Offset(0, -16))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFDFE4DC),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _ConfChip(tier: ConfidenceTier.verified, label: 'Verified'),
                    const SizedBox(width: 8),
                    Text('barcode match',
                        style: TextStyle(color: t.muted, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(food.name,
                    style: TextStyle(
                        color: t.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                if (food.brand != null || food.servingSizeGrams != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (food.brand != null) food.brand!,
                        if (food.servingSizeGrams != null) '${food.servingSizeGrams!.round()} g',
                      ].join(' · '),
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${kcal.round()}', style: displayNumber(context, size: 30)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5, left: 4),
                      child: Text('kcal', style: TextStyle(color: t.subtle, fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    const Spacer(),
                    _MacroChip(label: 'P', value: macro(food.proteinPer100g), color: const Color(0xFFC25A4E)),
                    const SizedBox(width: 6),
                    _MacroChip(label: 'C', value: macro(food.carbsPer100g), color: const Color(0xFFBF8A23)),
                    const SizedBox(width: 6),
                    _MacroChip(label: 'F', value: macro(food.fatPer100g), color: const Color(0xFF5A66B8)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Stepper(value: qty, hasServing: hasServing, onStep: onStep),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E7DF)),
                        ),
                        child: Text(unitLabel,
                            style: TextStyle(color: t.subtle, fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onPickMeal,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: t.card,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFE2E7DF)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.restaurant_menu, size: 16),
                            const SizedBox(width: 6),
                            Text(meal.label,
                                style: TextStyle(color: t.ink, fontSize: 13, fontWeight: FontWeight.w700)),
                            const Icon(Icons.arrow_drop_down, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: adding ? null : onAdd,
                          style: FilledButton.styleFrom(
                            backgroundColor: grove,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: adding
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Add',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton.icon(
                    onPressed: onScanAnother,
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Scan another'),
                    style: TextButton.styleFrom(foregroundColor: grove),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfChip extends StatelessWidget {
  const _ConfChip({required this.tier, required this.label});
  final ConfidenceTier tier;
  final String label;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final (bg, fg, glyph) = t.confidence(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(glyph, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  const _MacroChip({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        Text('${value.round()}g',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.hasServing, required this.onStep});
  final double value;
  final bool hasServing;
  final void Function(double delta) onStep;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final label = hasServing
        ? (value == value.roundToDouble() ? value.round().toString() : value.toString())
        : '${value.round()}g';
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E7DF)),
      ),
      child: Row(
        children: [
          _StepBtn(icon: Icons.remove, onTap: () => onStep(-1)),
          Container(
            constraints: const BoxConstraints(minWidth: 40),
            alignment: Alignment.center,
            child: Text(label, style: tabular(context, size: 15, weight: FontWeight.w800)),
          ),
          _StepBtn(icon: Icons.add, onTap: () => onStep(1)),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(width: 40, height: 44, child: Icon(icon, size: 20)),
    );
  }
}

// ============================ A4 not-found sheet ============================

class _NotFoundSheet extends StatelessWidget {
  const _NotFoundSheet({
    required this.code,
    required this.onAddFromLabel,
    required this.onSearch,
    required this.onManual,
  });
  final String code;
  final VoidCallback onAddFromLabel;
  final VoidCallback onSearch;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 40, offset: Offset(0, -16))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38, height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFDFE4DC), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: t.estimatedBg, borderRadius: BorderRadius.circular(16)),
                  child: Icon(Icons.help_outline, color: t.estimatedFg),
                ),
                const SizedBox(height: 12),
                Text("We don't have this one yet",
                    style: TextStyle(color: t.ink, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Barcode '),
                  TextSpan(text: code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                  const TextSpan(text: '. Add it once and it\'s saved for next time.'),
                ]), style: TextStyle(color: t.subtle, fontSize: 13)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: onAddFromLabel,
                    style: FilledButton.styleFrom(
                      backgroundColor: grove,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.center_focus_strong, size: 18),
                    label: const Text('Add it from the label',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: onSearch,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Search by name'),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: onManual,
                    style: TextButton.styleFrom(foregroundColor: t.subtle),
                    child: const Text('Enter nutrition manually'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================ A5 permission ============================

class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView({required this.onManual, required this.onBack});
  final VoidCallback onManual;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: onBack)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84, height: 84,
                decoration: BoxDecoration(color: const Color(0xFFEEF2EC), borderRadius: BorderRadius.circular(24)),
                child: Icon(Icons.photo_camera_outlined, color: t.subtle, size: 38),
              ),
              const SizedBox(height: 18),
              Text('Camera access is off',
                  style: TextStyle(color: t.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Sitos needs the camera to scan barcodes. You can still log food by typing or searching.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.subtle, fontSize: 13),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: onManual,
                  style: FilledButton.styleFrom(
                    backgroundColor: grove,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Enter a barcode',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ dev multi-scan bar ============================

class _MultiScanBar extends StatelessWidget {
  const _MultiScanBar({
    required this.count,
    required this.busy,
    required this.onReview,
    required this.onClear,
  });
  final int count;
  final bool busy;
  final VoidCallback onReview;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(30),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Clear',
              onPressed: busy ? null : onClear,
            ),
            Expanded(
              child: Text(count == 1 ? '1 barcode' : '$count barcodes',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            FilledButton.icon(
              onPressed: busy ? null : onReview,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text('Review $count'),
            ),
          ],
        ),
      ),
    );
  }
}
