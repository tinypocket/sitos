import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../auth_service.dart';
import '../models.dart';
import '../providers.dart';
import 'add_entry_sheet.dart';

class DiaryScreen extends ConsumerWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final diary = ref.watch(diaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sitos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Recipes',
            onPressed: () => context.push('/recipes'),
          ),
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Goals',
            onPressed: () => context.push('/goal'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
          if (AuthService.enabled)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
              onPressed: () => AuthService.instance.signOut(),
            ),
        ],
      ),
      body: Column(
        children: [
          _DateBar(date: date, ref: ref),
          Expanded(
            child: diary.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                message: 'Could not load your diary.\n$e',
                onRetry: () => ref.invalidate(diaryProvider),
              ),
              data: (day) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(diaryProvider),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    _CalorieSummary(day: day),
                    const _RecentFoodsStrip(),
                    const Divider(height: 1),
                    if (day.entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text('No foods logged yet.\nTap + to add one.',
                              textAlign: TextAlign.center),
                        ),
                      )
                    else
                      // Group by meal; show a header + subtotal for each non-empty meal.
                      for (final meal in Meal.values)
                        if (day.entries.any((e) => e.meal == meal)) ...[
                          _MealHeader(
                              meal: meal,
                              entries: day.entries.where((e) => e.meal == meal).toList()),
                          ...day.entries
                              .where((e) => e.meal == meal)
                              .map((e) => _EntryTile(entry: e, ref: ref)),
                        ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      // E1 · center + opens the add-entry sheet; long-press jumps straight to Scan.
      floatingActionButton: GestureDetector(
        onLongPress: () => context.push('/scan'),
        child: FloatingActionButton(
          heroTag: 'add',
          tooltip: 'Add food',
          onPressed: () => showAddEntrySheet(context),
          child: const Icon(Icons.add),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 64,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.today),
              tooltip: 'Diary',
              onPressed: () {},
            ),
            const SizedBox(width: 48), // notch gap for the FAB
            IconButton(
              icon: const Icon(Icons.menu_book_outlined),
              tooltip: 'Recipes',
              onPressed: () => context.push('/recipes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateBar extends StatelessWidget {
  const _DateBar({required this.date, required this.ref});
  final DateTime date;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday =
        date.year == today.year && date.month == today.month && date.day == today.day;
    final label = isToday ? 'Today' : DateFormat('EEE, MMM d').format(date);

    void shift(int days) =>
        ref.read(selectedDateProvider.notifier).set(date.add(Duration(days: days)));

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            onPressed: isToday ? null : () => shift(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _CalorieSummary extends StatelessWidget {
  const _CalorieSummary({required this.day});
  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final goal = day.goalCalories;
    final consumed = day.totalCalories;
    final progress = (goal != null && goal > 0) ? (consumed / goal).clamp(0.0, 1.0) : null;
    final remaining = goal != null ? (goal - consumed) : null;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: CircularProgressIndicator(
                    // No goal yet → show a static empty ring, not a spinner
                    // (null value makes CircularProgressIndicator indeterminate).
                    value: progress ?? 0,
                    strokeWidth: 9,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${consumed.round()}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Text('kcal', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (goal != null)
                  Text(
                    remaining! >= 0
                        ? '${remaining.round()} kcal left of $goal'
                        : '${(-remaining).round()} kcal over $goal',
                    style: Theme.of(context).textTheme.titleMedium,
                  )
                else
                  const Text('Set a calorie goal to track progress'),
                const SizedBox(height: 8),
                _MacroRow(label: 'Protein', grams: day.totalProtein, target: day.goalProtein),
                _MacroRow(label: 'Carbs', grams: day.totalCarbs, target: day.goalCarbs),
                _MacroRow(label: 'Fat', grams: day.totalFat, target: day.goalFat),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.label, required this.grams, this.target});
  final String label;
  final double grams;
  final int? target;

  @override
  Widget build(BuildContext context) {
    final hasTarget = target != null && target! > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: hasTarget
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${grams.round()} / $target g', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (grams / target!).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  )
                : Text('${grams.toStringAsFixed(1)} g', style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.ref});
  final DiaryEntry entry;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final unit = entry.unit == QuantityUnit.grams ? 'g' : 'serving(s)';
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) async {
        await ref.read(apiProvider).deleteDiaryEntry(entry.id);
        ref.invalidate(diaryProvider);
      },
      child: ListTile(
        title: Text(entry.food.name),
        subtitle: Text('${entry.quantity.toStringAsFixed(0)} $unit'
            '${entry.food.brand != null ? ' · ${entry.food.brand}' : ''}'),
        trailing: Text('${entry.calories.round()} kcal'),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _EditEntrySheet(entry: entry, ref: ref),
        ),
      ),
    );
  }
}

class _MealHeader extends StatelessWidget {
  const _MealHeader({required this.meal, required this.entries});
  final Meal meal;
  final List<DiaryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final kcal = entries.fold<double>(0, (s, e) => s + e.calories);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(meal.label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Text('${kcal.round()} kcal', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

/// Horizontal strip of recently logged foods for one-tap re-add.
class _RecentFoodsStrip extends ConsumerWidget {
  const _RecentFoodsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentFoodsProvider);
    return recent.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (foods) {
        if (foods.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Recent', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: foods.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(foods[i].name, overflow: TextOverflow.ellipsis),
                  onPressed: () => context.push('/food', extra: foods[i]),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

/// Bottom sheet to edit a logged entry's quantity/unit (PUT /api/diary/{id}).
class _EditEntrySheet extends StatefulWidget {
  const _EditEntrySheet({required this.entry, required this.ref});
  final DiaryEntry entry;
  final WidgetRef ref;

  @override
  State<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<_EditEntrySheet> {
  late final _qty =
      TextEditingController(text: widget.entry.quantity.toStringAsFixed(0));
  late QuantityUnit _unit = widget.entry.unit;
  late Meal _meal = widget.entry.meal;
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final q = double.tryParse(_qty.text.trim());
    if (q == null || q <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.ref.read(apiProvider).updateDiaryEntry(
            id: widget.entry.id,
            foodId: widget.entry.food.id,
            date: widget.entry.date,
            meal: _meal,
            quantity: q,
            unit: _unit,
          );
      widget.ref.invalidate(diaryProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasServing = widget.entry.food.servingSizeGrams != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.entry.food.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final m in Meal.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: _meal == m,
                  onSelected: (_) => setState(() => _meal = m),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
