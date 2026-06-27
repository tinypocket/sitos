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
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() => _busy = true);
    await _controller.stop();

    try {
      final food = await ref.read(apiProvider).getFoodByBarcode(code);
      if (!mounted) return;
      // Replace the scanner with the detail screen so Back returns to the diary.
      context.pushReplacement('/food', extra: food);
    } on NotFoundException {
      if (!mounted) return;
      _showSnack('No match for barcode $code. Try adding it manually.');
      await _resume();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Lookup failed: $e');
      await _resume();
    }
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
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
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
