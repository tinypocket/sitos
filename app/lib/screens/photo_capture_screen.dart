import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../providers.dart';
import '../settings.dart';
import '../theme.dart';

// Capture-shell tokens (dark viewfinder + lighter reticle green) — shared with
// the scan + add-food camera surfaces.
const _shell = Color(0xFF11150F);
const _reticle = Color(0xFF7BDCAB);

/// E4 · Photo capture (meal → ingredients). Snap a plate (or pick from the
/// gallery), choose a depth — Breakdown (many ingredient rows) or Estimate (one
/// dish row) — and the AI parses it into the shared review surface (E2). On an
/// empty result a no-food edge screen offers Retake / Type it / Search.
///
/// One screen, internal phase machine so the captured bytes and the parse share
/// state without route plumbing. Route: `/add/photo`.
enum _Phase { capture, processing, noFood }

class PhotoCaptureScreen extends ConsumerStatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  ConsumerState<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  _Phase _phase = _Phase.capture;
  CameraController? _controller;
  bool _busy = false;
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
      final ctrl =
          CameraController(back, ResolutionPreset.high, enableAudio: false);
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

  // ===== capture =====

  Future<void> _shutter() async {
    final ctrl = _controller;
    if (ctrl == null || _busy || !ctrl.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final file = await ctrl.takePicture();
      final bytes = await file.readAsBytes();
      await _process(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Capture failed — try again');
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      await _process(bytes);
    } catch (e) {
      if (!mounted) return;
      _snack("Couldn't open the gallery");
    }
  }

  Future<void> _process(Uint8List bytes) async {
    setState(() {
      _phase = _Phase.processing;
      _busy = true;
    });
    final depth = ref.read(photoDepthProvider);
    try {
      final rows = await ref.read(apiProvider).parsePhoto(
            imageBase64: base64Encode(bytes),
            mode: depth.mode,
          );
      if (!mounted) return;
      if (rows.isEmpty) {
        setState(() {
          _phase = _Phase.noFood;
          _busy = false;
        });
        return;
      }
      ref.read(addSessionProvider.notifier).loadRows(
            Meal.forTimeOfDay(DateTime.now()),
            AddSource.photo,
            rows,
          );
      context.go('/add/review');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.capture;
        _busy = false;
      });
      _snack("Couldn't read your plate — try again");
    }
  }

  // ===== misc =====

  void _retake() => setState(() {
        _phase = _Phase.capture;
        _busy = false;
      });

  void _close() => context.canPop() ? context.pop() : context.go('/');
  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ===== build =====

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _CameraErrorView(
        message: _error!,
        onClose: _close,
        onType: () => context.pushReplacement('/add/smart'),
        onSearch: () => context.pushReplacement('/search'),
      );
    }
    return switch (_phase) {
      _Phase.processing => const _ProcessingView(),
      _Phase.noFood => _NoFoodView(
          onRetake: _retake,
          onType: () => context.pushReplacement('/add/smart'),
          onSearch: () => context.pushReplacement('/search'),
        ),
      _Phase.capture => _buildCapture(context),
    };
  }

  Widget _buildCapture(BuildContext context) {
    final ctrl = _controller;
    final depth = ref.watch(photoDepthProvider);
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

          // Square-ish meal framing guide + dim mask.
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _MealGuidePainter())),
          ),

          // Top chrome: close + title.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _CircleControl(icon: Icons.close, onTap: _close),
                  const Expanded(
                    child: Text('Snap your meal',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),

          // Hint above the controls.
          const Positioned(
            left: 24,
            right: 24,
            bottom: 188,
            child: Text(
              'Fill the frame with your plate',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
              ),
            ),
          ),

          // Depth toggle (Breakdown | Estimate) — remembers the last choice.
          Positioned(
            left: 0,
            right: 0,
            bottom: 132,
            child: Center(
              child: _DepthToggle(
                value: depth,
                onChanged: (d) => ref.read(photoDepthProvider.notifier).set(d),
              ),
            ),
          ),

          // Bottom controls: gallery · shutter.
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Row(
                children: [
                  _GalleryButton(onTap: _busy ? null : _pickFromGallery),
                  const Spacer(),
                  _Shutter(busy: _busy, onTap: _shutter),
                  const Spacer(),
                  // Balance the row against the gallery button.
                  const SizedBox(width: 52),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ depth toggle ============================

class _DepthToggle extends StatelessWidget {
  const _DepthToggle({required this.value, required this.onChanged});
  final PhotoDepth value;
  final ValueChanged<PhotoDepth> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final d in PhotoDepth.values) _segment(d),
        ],
      ),
    );
  }

  Widget _segment(PhotoDepth d) {
    final selected = d == value;
    return GestureDetector(
      onTap: selected ? null : () => onChanged(d),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _reticle : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          d.label,
          style: TextStyle(
            color: selected ? _shell : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ============================ bottom controls ============================

class _Shutter extends StatelessWidget {
  const _Shutter({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 4),
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2, color: _shell),
              )
            : null,
      ),
    );
  }
}

class _GalleryButton extends StatelessWidget {
  const _GalleryButton({required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: const SizedBox(
          width: 52,
          height: 52,
          child: Icon(Icons.photo_library_outlined, color: Colors.white, size: 24),
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

class _MealGuidePainter extends CustomPainter {
  const _MealGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Square meal window centred a touch above the middle.
    final w = size.width * 0.78;
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.4),
      width: w,
      height: w,
    );
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(24));

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size,
        Paint()..color = const Color(0xFF080B06).withValues(alpha: 0.55));
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // Corner brackets.
    final p = Paint()
      ..color = _reticle
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 30.0;
    final l = window.left, t = window.top, r = window.right, b = window.bottom;
    final path = Path()
      ..moveTo(l, t + len)..lineTo(l, t + 14)..arcToPoint(Offset(l + 14, t), radius: const Radius.circular(14))..lineTo(l + len, t)
      ..moveTo(r - len, t)..lineTo(r - 14, t)..arcToPoint(Offset(r, t + 14), radius: const Radius.circular(14))..lineTo(r, t + len)
      ..moveTo(r, b - len)..lineTo(r, b - 14)..arcToPoint(Offset(r - 14, b), radius: const Radius.circular(14))..lineTo(r - len, b)
      ..moveTo(l + len, b)..lineTo(l + 14, b)..arcToPoint(Offset(l, b - 14), radius: const Radius.circular(14))..lineTo(l, b - len);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_MealGuidePainter old) => false;
}

// ============================ processing ============================

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _shell,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(strokeWidth: 3, color: _reticle),
            ),
            SizedBox(height: 20),
            Text('Reading your plate…',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Spotting ingredients and portions',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ============================ no-food edge screen ============================

class _NoFoodView extends StatelessWidget {
  const _NoFoodView({
    required this.onRetake,
    required this.onType,
    required this.onSearch,
  });
  final VoidCallback onRetake;
  final VoidCallback onType;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: onRetake)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                    color: t.noMatchBg, borderRadius: BorderRadius.circular(24)),
                child: Icon(Icons.no_food_outlined, color: t.muted, size: 38),
              ),
              const SizedBox(height: 18),
              Text('No food detected',
                  style: TextStyle(
                      color: t.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                "We couldn't spot a meal in that photo. Try again with the plate "
                'filling the frame, or add it another way.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.subtle, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: onRetake,
                  style: FilledButton.styleFrom(
                    backgroundColor: grove,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Retake',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onType,
                  icon: const Icon(Icons.keyboard_outlined, size: 18),
                  label: const Text('Type it'),
                ),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: onSearch,
                style: TextButton.styleFrom(foregroundColor: t.subtle),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Search'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ camera error ============================

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({
    required this.message,
    required this.onClose,
    required this.onType,
    required this.onSearch,
  });
  final String message;
  final VoidCallback onClose;
  final VoidCallback onType;
  final VoidCallback onSearch;

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
                'You can still log your meal by typing it or searching.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.subtle, fontSize: 13),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: onType,
                  style: FilledButton.styleFrom(
                    backgroundColor: grove,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Type it',
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
                  label: const Text('Search'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
