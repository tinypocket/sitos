import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:go_router/go_router.dart';

import '../api_client.dart';
import '../providers.dart';

/// Camera barcode scanner. Uses flutter_zxing (zxing-cpp native decoder) — NOT
/// Google MLKit, whose barcode client null-crashes on some devices. The camera +
/// decoder come from flutter_zxing, but ALL of the chrome (framing window, scan
/// line, hint, torch) is our own custom overlay for an on-brand, modern look.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _busy = false;
  CameraController? _camera;
  bool _torchOn = false;

  void _onScan(Code code) {
    final text = code.text;
    if (_busy || text == null || text.isEmpty) return;
    _lookup(text);
  }

  /// Shared resolution path for both camera scans and manual entry.
  Future<void> _lookup(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final food = await ref.read(apiProvider).getFoodByBarcode(code);
      if (!mounted) return;
      context.pushReplacement('/food', extra: food);
    } on NotFoundException {
      if (!mounted) return;
      _showSnack('No match for $code — add it manually.');
      context.pushReplacement('/food/new', extra: code);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Lookup failed: $e');
      setState(() => _busy = false);
    }
  }

  Future<void> _toggleTorch() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      await cam.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {/* some devices reject torch — ignore */}
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
    if (code != null && code.isNotEmpty) await _lookup(code);
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Flashlight',
            onPressed: _toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Enter barcode manually',
            onPressed: _busy ? null : _manualEntry,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          // Wide, barcode-shaped framing window, centred and lifted slightly.
          final w = size.width * 0.82;
          final h = w * 0.60;
          final window = Rect.fromLTWH(
            (size.width - w) / 2,
            (size.height - h) / 2 - size.height * 0.05,
            w,
            h,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              // Bare camera + decoder — no flutter_zxing chrome.
              ReaderWidget(
                onScan: _onScan,
                onControllerCreated: (controller, error) => _camera = controller,
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
                  decoration: BoxDecoration(color: Colors.black),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              // Dimmed surround + grove corner brackets around the window.
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScannerFramePainter(window: window, accent: accent),
                ),
              ),
              // Animated scan line inside the window.
              Positioned.fromRect(
                rect: window,
                child: IgnorePointer(child: _ScanLine(color: accent)),
              ),
              // Hint just above the window.
              Positioned(
                top: window.top - 44,
                left: 24,
                right: 24,
                child: const Text(
                  'Point the camera at a barcode',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                  ),
                ),
              ),
              if (_busy)
                const ColoredBox(
                  color: Colors.black45,
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Paints a dimmed scrim with a transparent rounded window and grove L-brackets.
class _ScannerFramePainter extends CustomPainter {
  _ScannerFramePainter({required this.window, required this.accent});

  final Rect window;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(22));
    // Punch a transparent hole in the scrim so the camera shows through.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // Corner brackets.
    final p = Paint()
      ..color = accent
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 30.0;
    final l = window.left, t = window.top, r = window.right, b = window.bottom;
    final path = Path()
      // top-left
      ..moveTo(l, t + len)..lineTo(l, t + 14)..arcToPoint(Offset(l + 14, t), radius: const Radius.circular(14))..lineTo(l + len, t)
      // top-right
      ..moveTo(r - len, t)..lineTo(r - 14, t)..arcToPoint(Offset(r, t + 14), radius: const Radius.circular(14))..lineTo(r, t + len)
      // bottom-right
      ..moveTo(r, b - len)..lineTo(r, b - 14)..arcToPoint(Offset(r - 14, b), radius: const Radius.circular(14))..lineTo(r - len, b)
      // bottom-left
      ..moveTo(l + len, b)..lineTo(l + 14, b)..arcToPoint(Offset(l, b - 14), radius: const Radius.circular(14))..lineTo(l, b - len);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_ScannerFramePainter old) =>
      old.window != window || old.accent != accent;
}

/// A thin glowing line that sweeps up and down inside the scan window.
class _ScanLine extends StatefulWidget {
  const _ScanLine({required this.color});

  final Color color;

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Align(
        alignment: Alignment(0, _controller.value * 2 - 1),
        child: Container(
          height: 2.5,
          margin: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.7),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
