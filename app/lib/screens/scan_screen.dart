import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:go_router/go_router.dart';

import '../api_client.dart';
import '../providers.dart';

/// Camera barcode scanner. Uses flutter_zxing (zxing-cpp native decoder) — NOT
/// Google MLKit, whose barcode client null-crashes on some devices. On a scan it
/// resolves the barcode via the API (cache → providers) and opens the food detail.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _busy = false;

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
      // Replace the scanner with the detail screen so Back returns to the diary.
      context.pushReplacement('/food', extra: food);
    } on NotFoundException {
      if (!mounted) return;
      // Unknown barcode — let the user add it, prefilling the code they entered.
      _showSnack('No match for $code — add it manually.');
      context.pushReplacement('/food/new', extra: code);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Lookup failed: $e');
      setState(() => _busy = false); // let them try again
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
    if (code != null && code.isNotEmpty) await _lookup(code);
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Enter barcode manually',
            onPressed: _busy ? null : _manualEntry,
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          ReaderWidget(
            onScan: _onScan,
            codeFormat: Format.any,
            tryHarder: true,
            tryInverted: true,
            showGallery: false,
            showToggleCamera: false,
            scanDelaySuccess: const Duration(seconds: 2),
            // Modern, on-brand overlay: grove rounded corner-brackets + dimmed surround.
            scannerOverlay: ScannerOverlayBorder(
              borderColor: green,
              borderWidth: 6,
              borderRadius: 24,
              borderLength: 40,
              cutOutSize: 0.66,
              overlayColor: Colors.black.withValues(alpha: 0.55),
            ),
            // Flashlight as a centered translucent pill, not a square black box.
            actionButtonsAlignment: Alignment.bottomCenter,
            actionButtonsPadding: const EdgeInsets.only(bottom: 40),
            actionButtonsBackgroundColor: Colors.black.withValues(alpha: 0.45),
            actionButtonsBackgroundBorderRadius: BorderRadius.circular(30),
            flashOnIcon: const Icon(Icons.flash_on, color: Colors.white),
            flashOffIcon: const Icon(Icons.flash_off, color: Colors.white),
            flashAlwaysIcon: const Icon(Icons.flash_on, color: Colors.white),
            flashAutoIcon: const Icon(Icons.flash_auto, color: Colors.white),
            loading: const DecoratedBox(
              decoration: BoxDecoration(color: Colors.black),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          // Animated grove scan line sweeping inside the cut-out window.
          IgnorePointer(child: _ScanLine(color: green, sizeFraction: 0.66)),
          // Hint above the cut-out window.
          const Align(
            alignment: Alignment(0, -0.34),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Point the camera at a barcode',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                ),
              ),
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Colors.black45,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// A thin glowing line that sweeps up and down inside the scan window,
/// sized to match the cut-out so it tracks the framing brackets.
class _ScanLine extends StatefulWidget {
  const _ScanLine({required this.color, required this.sizeFraction});

  final Color color;
  final double sizeFraction;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = widget.sizeFraction *
            (constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth
                : constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Align(
                alignment: Alignment(0, _controller.value * 2 - 1),
                child: Container(
                  height: 2.5,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
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
            ),
          ),
        );
      },
    );
  }
}
