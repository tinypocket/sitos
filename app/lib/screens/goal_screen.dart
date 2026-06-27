import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class GoalScreen extends ConsumerStatefulWidget {
  const GoalScreen({super.key});

  @override
  ConsumerState<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends ConsumerState<GoalScreen> {
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    for (final c in [_calories, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _intOrNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  Future<void> _save() async {
    final target = int.tryParse(_calories.text.trim());
    if (target == null || target <= 0) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).setGoal(
            dailyCalorieTarget: target,
            proteinTargetGrams: _intOrNull(_protein),
            carbsTargetGrams: _intOrNull(_carbs),
            fatTargetGrams: _intOrNull(_fat),
          );
      ref.invalidate(goalProvider);
      ref.invalidate(diaryProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = ref.watch(goalProvider);
    // Seed the fields once from the existing goal.
    goal.whenData((g) {
      if (!_loaded && g != null) {
        _calories.text = g.dailyCalorieTarget.toString();
        _protein.text = g.proteinTargetGrams?.toString() ?? '';
        _carbs.text = g.carbsTargetGrams?.toString() ?? '';
        _fat.text = g.fatTargetGrams?.toString() ?? '';
        _loaded = true;
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Daily calorie target'),
          const SizedBox(height: 8),
          _numField(_calories, 'Calories', suffix: 'kcal'),
          const SizedBox(height: 24),
          Text('Macro targets (optional)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _numField(_protein, 'Protein', suffix: 'g')),
              const SizedBox(width: 12),
              Expanded(child: _numField(_carbs, 'Carbs', suffix: 'g')),
              const SizedBox(width: 12),
              Expanded(child: _numField(_fat, 'Fat', suffix: 'g')),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController c, String label, {required String suffix}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixText: suffix,
      ),
    );
  }
}
