import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import '../theme.dart';

/// E6 · Portion editor. Fast switching between count+size / grams / servings.
/// Setting a real portion promotes the row's confidence to Verified.
Future<void> showPortionEditor(
    BuildContext context, WidgetRef ref, ReviewRow row) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: const Color(0x52151F1A),
    builder: (_) => _PortionEditor(row: row, ref: ref),
  );
}

// TODO: size vocab + default unit should come from the food DB (per-food).
const _sizeMult = {'small': 0.7, 'medium': 1.0, 'large': 1.4};

class _PortionEditor extends StatefulWidget {
  const _PortionEditor({required this.row, required this.ref});
  final ReviewRow row;
  final WidgetRef ref;

  @override
  State<_PortionEditor> createState() => _PortionEditorState();
}

class _PortionEditorState extends State<_PortionEditor> {
  late QuantityUnit _unit = widget.row.unit;
  late double _value =
      widget.row.unit == QuantityUnit.grams ? widget.row.grams : widget.row.quantity;
  late String _size = widget.row.sizeLabel ?? 'medium';

  // Guard against null AND a zero/negative serving size (bad DB data) → no div-by-zero/NaN.
  double get _base {
    final b = widget.row.match?.servingSizeGrams;
    return (b == null || b <= 0) ? 100.0 : b;
  }

  double get _grams => switch (_unit) {
        QuantityUnit.grams => _value,
        QuantityUnit.servings => _value * _base,
        QuantityUnit.countSize => _value * _base * (_sizeMult[_size] ?? 1.0),
      };

  double get _kcal => (widget.row.match?.caloriesPer100g ?? 0) * _grams / 100.0;

  double get _step => switch (_unit) {
        QuantityUnit.grams => 10,
        QuantityUnit.servings => 0.5,
        QuantityUnit.countSize => 1,
      };

  void _switchUnit(QuantityUnit u) {
    // Preserve grams across the switch.
    final g = _grams;
    setState(() {
      _unit = u;
      _value = switch (u) {
        QuantityUnit.grams => g.roundToDouble(),
        QuantityUnit.servings => (g / _base),
        QuantityUnit.countSize => (g / (_base * (_sizeMult[_size] ?? 1.0))),
      };
      if (u == QuantityUnit.countSize) {
        _value = _value.roundToDouble().clamp(1.0, 999.0).toDouble();
      }
    });
  }

  void _save() {
    widget.ref.read(addSessionProvider.notifier).replaceRow(
          widget.row.copyWith(
            quantity: _unit == QuantityUnit.grams ? _grams : _value,
            unit: _unit,
            sizeLabel: _unit == QuantityUnit.countSize ? _size : null,
            grams: _grams,
            calories: _kcal,
            // A real portion = verified, but only if we actually have a matched food.
            tier: widget.row.match != null
                ? ConfidenceTier.verified
                : widget.row.tier,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    final scheme = Theme.of(context).colorScheme;
    final food = widget.row.match;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE0E5DD),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text(food?.name ?? 'Portion',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text('${(food?.caloriesPer100g ?? 0).round()} kcal / 100 g',
              style: TextStyle(color: tokens.muted, fontSize: 12)),
          const SizedBox(height: 16),
          SegmentedButton<QuantityUnit>(
            segments: const [
              ButtonSegment(value: QuantityUnit.countSize, label: Text('Count+size')),
              ButtonSegment(value: QuantityUnit.grams, label: Text('Grams')),
              ButtonSegment(value: QuantityUnit.servings, label: Text('Servings')),
            ],
            selected: {_unit},
            onSelectionChanged: (s) => _switchUnit(s.first),
          ),
          const SizedBox(height: 20),
          // Stepper.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepBtn(icon: Icons.remove, onTap: () {
                setState(() => _value = (_value - _step).clamp(_step, 99999.0).toDouble());
              }),
              const SizedBox(width: 24),
              SizedBox(
                width: 96,
                child: Text(
                  _unit == QuantityUnit.servings
                      ? _value.toStringAsFixed(1)
                      : _value.round().toString(),
                  textAlign: TextAlign.center,
                  style: displayNumber(context, size: 34),
                ),
              ),
              const SizedBox(width: 24),
              _StepBtn(icon: Icons.add, onTap: () {
                setState(() => _value = _value + _step);
              }),
            ],
          ),
          if (_unit == QuantityUnit.countSize) ...[
            const SizedBox(height: 16),
            Center(
              child: Wrap(
                spacing: 8,
                children: [
                  for (final s in _sizeMult.keys)
                    ChoiceChip(
                      label: Text(s),
                      selected: _size == s,
                      onSelected: (_) => setState(() => _size = s),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_grams.round()} g',
                    style: tabular(context, size: 16, color: scheme.onPrimaryContainer)),
                Text('${_kcal.round()} kcal',
                    style: tabular(context, size: 16, color: scheme.onPrimaryContainer)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Save portion'),
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    return Material(
      color: tokens.card,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: tokens.hairline),
          ),
          child: Icon(icon, color: tokens.ink),
        ),
      ),
    );
  }
}
