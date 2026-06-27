import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';

/// Form for adding a user-contributed food (POST /api/foods). Reachable from search
/// and from a failed scan (which prefills the [initialBarcode]). On success it routes
/// to the food detail screen so the user can immediately log the new food.
class AddFoodScreen extends ConsumerStatefulWidget {
  const AddFoodScreen({super.key, this.initialBarcode});
  final String? initialBarcode;

  @override
  ConsumerState<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends ConsumerState<AddFoodScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  late final _barcode = TextEditingController(text: widget.initialBarcode ?? '');
  final _servingGrams = TextEditingController();
  final _servingLabel = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name, _brand, _barcode, _servingGrams, _servingLabel,
      _calories, _protein, _carbs, _fat
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final food = await ref.read(apiProvider).createUserFood({
        'name': _name.text.trim(),
        'brand': _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        'servingSizeGrams':
            _servingGrams.text.trim().isEmpty ? null : _num(_servingGrams),
        'servingSizeLabel':
            _servingLabel.text.trim().isEmpty ? null : _servingLabel.text.trim(),
        'caloriesPer100g': _num(_calories),
        'proteinPer100g': _num(_protein),
        'carbsPer100g': _num(_carbs),
        'fatPer100g': _num(_fat),
      });
      if (!mounted) return;
      // Replace so Back from detail returns to the diary, not this form.
      context.pushReplacement('/food', extra: food);
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
      appBar: AppBar(title: const Text('Add a food')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _text(_name, 'Name *', required: true),
            _text(_brand, 'Brand'),
            _text(_barcode, 'Barcode', keyboard: TextInputType.number),
            const SizedBox(height: 8),
            Text('Per 100 g', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _text(_calories, 'Calories (kcal) *',
                keyboard: _decimal, required: true, number: true),
            Row(children: [
              Expanded(child: _text(_protein, 'Protein (g)', keyboard: _decimal, number: true)),
              const SizedBox(width: 12),
              Expanded(child: _text(_carbs, 'Carbs (g)', keyboard: _decimal, number: true)),
              const SizedBox(width: 12),
              Expanded(child: _text(_fat, 'Fat (g)', keyboard: _decimal, number: true)),
            ]),
            const SizedBox(height: 8),
            Text('Serving (optional)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _text(_servingGrams, 'Serving size (g)', keyboard: _decimal, number: true),
            _text(_servingLabel, 'Serving label (e.g. "1 cup")'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Save & log'),
            ),
          ],
        ),
      ),
    );
  }

  static const _decimal = TextInputType.numberWithOptions(decimal: true);

  Widget _text(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    bool required = false,
    bool number = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) return 'Required';
          if (number && v != null && v.trim().isNotEmpty && double.tryParse(v.trim()) == null) {
            return 'Enter a number';
          }
          return null;
        },
      ),
    );
  }
}
