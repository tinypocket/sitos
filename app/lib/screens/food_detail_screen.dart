import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../providers.dart';

/// Shows a food's nutrition and lets the user log a quantity to the selected day.
class FoodDetailScreen extends ConsumerStatefulWidget {
  const FoodDetailScreen({super.key, required this.food});
  final Food food;

  @override
  ConsumerState<FoodDetailScreen> createState() => _FoodDetailScreenState();
}

class _FoodDetailScreenState extends ConsumerState<FoodDetailScreen> {
  late QuantityUnit _unit =
      widget.food.servingSizeGrams != null ? QuantityUnit.servings : QuantityUnit.grams;
  final _qtyController = TextEditingController(text: '1');
  bool _saving = false;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  double get _quantity => double.tryParse(_qtyController.text) ?? 0;

  /// Grams the current quantity resolves to (mirrors server DiaryEntry.ResolveGrams).
  double get _grams => _unit == QuantityUnit.grams
      ? _quantity
      : _quantity * (widget.food.servingSizeGrams ?? 100);

  double _scaled(double per100g) => per100g * _grams / 100;

  Future<void> _log() async {
    if (_quantity <= 0) return;
    setState(() => _saving = true);
    try {
      final date = ref.read(selectedDateProvider);
      await ref.read(apiProvider).addDiaryEntry(
            foodId: widget.food.id,
            date: date,
            quantity: _quantity,
            unit: _unit,
          );
      ref.invalidate(diaryProvider);
      if (!mounted) return;
      context.go('/'); // back to the diary
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not log: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.food;
    final hasServing = f.servingSizeGrams != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Add food')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(f.name, style: Theme.of(context).textTheme.headlineSmall),
          if (f.brand != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(f.brand!, style: Theme.of(context).textTheme.bodyMedium),
            ),
          const SizedBox(height: 24),

          // Quantity + unit.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<QuantityUnit>(
                segments: [
                  ButtonSegment(
                    value: QuantityUnit.servings,
                    label: const Text('serving'),
                    enabled: hasServing,
                  ),
                  const ButtonSegment(value: QuantityUnit.grams, label: Text('grams')),
                ],
                selected: {_unit},
                onSelectionChanged: (s) => setState(() => _unit = s.first),
              ),
            ],
          ),
          if (hasServing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Serving: ${f.servingSizeLabel ?? '${f.servingSizeGrams!.round()} g'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 24),

          // Live nutrition for the chosen amount.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _NutriRow('Calories', '${_scaled(f.caloriesPer100g).round()} kcal',
                      emphasize: true),
                  _NutriRow('Protein', '${_scaled(f.proteinPer100g).toStringAsFixed(1)} g'),
                  _NutriRow('Carbs', '${_scaled(f.carbsPer100g).toStringAsFixed(1)} g'),
                  _NutriRow('Fat', '${_scaled(f.fatPer100g).toStringAsFixed(1)} g'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: (_quantity > 0 && !_saving) ? _log : null,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add),
            label: const Text('Add to diary'),
          ),
        ],
      ),
    );
  }
}

class _NutriRow extends StatelessWidget {
  const _NutriRow(this.label, this.value, {this.emphasize = false});
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
