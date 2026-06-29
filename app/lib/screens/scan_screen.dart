import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api_client.dart';
import '../providers.dart';

/// Camera barcode scanner. On a successful scan it resolves the barcode via the
/// API (cache → providers) and navigates to the food detail screen to log it.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    // Start the camera ourselves so a permission/MLKit failure is caught and shown
    // gracefully, instead of surfacing as a raw native crash dialog.
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  bool _busy = false;
  String? _startError;
  String? _startDetail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (mounted) setState(() {
      _startError = null;
      _startDetail = null;
    });
    try {
      await _controller.start();
    } catch (e) {
      final detail =
          e is MobileScannerException ? e.errorDetails?.details?.toString() : null;
      if (mounted) setState(() {
        _startError = '$e';
        _startDetail = detail;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    await _lookup(code);
  }

  /// Shared resolution path for both camera scans and manual entry.
  Future<void> _lookup(String code) async {
    setState(() => _busy = true);
    await _controller.stop();

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
      await _resume();
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

  Future<void> _resume() async {
    await _controller.start();
    if (mounted) setState(() => _busy = false);
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Enter barcode manually',
            onPressed: _busy ? null : _manualEntry,
          ),
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: _startError != null
          ? _CameraError(
              message: _startError!,
              detail: _startDetail,
              onRetry: _start,
              onManual: _manualEntry)
          : Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  // Catch errors that happen AFTER start (during streaming/detection),
                  // which our manual-start try/catch wouldn't see, and surface the cause.
                  errorBuilder: (context, error) => _CameraError(
                    message: error.toString(),
                    detail: error.errorDetails?.details?.toString(),
                    onRetry: _start,
                    onManual: _manualEntry,
                  ),
                ),
                // Simple reticle to guide aiming.
                Container(
                  width: 240,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                if (_busy) const CircularProgressIndicator(),
              ],
            ),
    );
  }
}

/// Shown when the camera can't start (permission denied, or a device/MLKit error).
/// Keeps the user moving: retry, or type the barcode instead.
class _CameraError extends StatelessWidget {
  const _CameraError(
      {required this.message,
      this.detail,
      required this.onRetry,
      required this.onManual});
  final String message;
  final String? detail;
  final VoidCallback onRetry;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 44),
            const SizedBox(height: 14),
            const Text(
              'Couldn’t start the camera.\nCheck camera permission, or enter the barcode by hand.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            // Surface the underlying error for diagnostics.
            SelectableText(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: SelectableText(
                    detail!,
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                FilledButton.icon(
                  onPressed: onManual,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Enter manually'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
