import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../providers.dart';
import '../theme.dart';

/// E3 · Smart Add. Type (or dictate) a free-text food list → parse → E2 review.
class SmartAddScreen extends ConsumerStatefulWidget {
  const SmartAddScreen({super.key, this.meal});
  final Meal? meal;

  @override
  ConsumerState<SmartAddScreen> createState() => _SmartAddScreenState();
}

class _SmartAddScreenState extends ConsumerState<SmartAddScreen> {
  final _controller = TextEditingController();
  late final Meal _meal = widget.meal ?? Meal.forTimeOfDay(DateTime.now());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _findFoods() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final notifier = ref.read(addSessionProvider.notifier);
    notifier.start(_meal, AddSource.text);
    notifier.parseText(text); // review screen reacts to parsing → ready
    context.push('/add/review');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Smart add')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('List what you ate — we’ll find each food.',
                  style: TextStyle(color: tokens.subtle, fontSize: 14)),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontSize: 16, height: 1.4),
                decoration: InputDecoration(
                  hintText:
                      'e.g. 5 eggs, 2 tbsp oil, some salt, half a cup of cottage cheese',
                  hintStyle: TextStyle(color: tokens.muted),
                  filled: true,
                  fillColor: tokens.card,
                  contentPadding: const EdgeInsets.all(16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: tokens.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: scheme.primary, width: 1.5),
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  // Mic — on-device dictation (deferred; placeholder for now).
                  Material(
                    color: tokens.card,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('On-device voice input is coming soon.')),
                      ),
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: tokens.hairline),
                        ),
                        child: Icon(Icons.mic_none, color: tokens.subtle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _findFoods,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.search),
                      label: const Text('Find foods'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
