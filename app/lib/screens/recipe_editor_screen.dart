import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import 'search_screen.dart';

/// A locally-edited ingredient. Holds just what's needed to save + display.
class _Draft {
  _Draft(this.foodId, this.foodName, this.quantity, this.unit, this.calories);
  final String foodId;
  final String foodName;
  double quantity;
  QuantityUnit unit;
  double? calories; // for display only
}

/// Create or edit a recipe: name, servings, and a list of ingredients.
class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({super.key, this.recipe});
  final Recipe? recipe;

  @override
  ConsumerState<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends ConsumerState<RecipeEditorScreen> {
  late final _name = TextEditingController(text: widget.recipe?.name ?? '');
  late final _servings =
      TextEditingController(text: (widget.recipe?.servings ?? 2).toString());
  late final List<_Draft> _ingredients = widget.recipe?.ingredients
          .map((i) => _Draft(i.foodId, i.foodName, i.quantity, i.unit, i.calories))
          .toList() ??
      [];
  bool _saving = false;

  bool get _isEdit => widget.recipe != null;

  @override
  void dispose() {
    _name.dispose();
    _servings.dispose();
    super.dispose();
  }

  Future<void> _addIngredient() async {
    final food = await Navigator.of(context).push<Food>(
      MaterialPageRoute(builder: (_) => const SearchScreen(pickMode: true)),
    );
    if (food == null || !mounted) return;
    final result = await _askQuantity(food);
    if (result == null) return;
    setState(() {
      _ingredients.add(_Draft(
        food.id,
        food.name,
        result.$1,
        result.$2,
        food.caloriesPer100g *
            (result.$2 == QuantityUnit.grams
                ? result.$1
                : result.$1 * (food.servingSizeGrams ?? 100)) /
            100,
      ));
    });
  }

  /// Quantity + unit dialog. Returns (quantity, unit).
  Future<(double, QuantityUnit)?> _askQuantity(Food food) async {
    final qty = TextEditingController(text: '100');
    var unit = food.servingSizeGrams != null ? QuantityUnit.servings : QuantityUnit.grams;
    return showDialog<(double, QuantityUnit)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(food.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: qty,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<QuantityUnit>(
                value: unit,
                items: [
                  if (food.servingSizeGrams != null)
                    const DropdownMenuItem(
                        value: QuantityUnit.servings, child: Text('serving')),
                  const DropdownMenuItem(value: QuantityUnit.grams, child: Text('grams')),
                ],
                onChanged: (u) => setLocal(() => unit = u!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final q = double.tryParse(qty.text.trim());
                if (q != null && q > 0) Navigator.pop(ctx, (q, unit));
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final servings = int.tryParse(_servings.text.trim()) ?? 0;
    if (name.isEmpty || servings <= 0 || _ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add a name, servings, and at least one ingredient.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).saveRecipe(
            id: widget.recipe?.id,
            name: name,
            servings: servings,
            ingredients: _ingredients
                .map((d) => (foodId: d.foodId, quantity: d.quantity, unit: d.unit))
                .toList(),
          );
      ref.invalidate(recipesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit recipe' : 'New recipe')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Recipe name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _servings,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Servings (how many portions it makes)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: _addIngredient,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          if (_ingredients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No ingredients yet.'),
            )
          else
            ..._ingredients.asMap().entries.map((e) {
              final d = e.value;
              final unit = d.unit == QuantityUnit.grams ? 'g' : 'serving(s)';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(d.foodName),
                subtitle: Text('${d.quantity.toStringAsFixed(0)} $unit'
                    '${d.calories != null ? ' · ${d.calories!.round()} kcal' : ''}'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _ingredients.removeAt(e.key)),
                ),
              );
            }),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Save recipe'),
          ),
        ],
      ),
    );
  }
}
