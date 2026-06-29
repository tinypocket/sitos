import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dev = ref.watch(devSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Daily goal'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/goal'),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 4),
            child: Text(
              'Developer',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.qr_code_scanner_outlined),
            title: const Text('Multi-barcode scan'),
            subtitle: const Text(
              'Experimental — collect several barcodes in one session, then review and log them together.',
            ),
            value: dev.multiScan,
            onChanged: (v) =>
                ref.read(devSettingsProvider.notifier).setMultiScan(v),
          ),
        ],
      ),
    );
  }
}
