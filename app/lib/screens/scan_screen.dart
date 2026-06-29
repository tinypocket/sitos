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
    return Scaffold(
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
            scanDelaySuccess: const Duration(seconds: 2),
            loading: const DecoratedBox(
              decoration: BoxDecoration(color: Colors.black),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          if (_busy) const CircularProgressIndicator(),
        ],
      ),
    );
  }
}
