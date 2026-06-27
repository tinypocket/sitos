import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../providers.dart';

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
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Calorie goal',
            onPressed: () => context.push('/goal'),
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
                    const Divider(height: 1),
                    if (day.entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text('No foods logged yet.\nTap scan to add one.',
                              textAlign: TextAlign.center),
                        ),
                      )
                    else
                      ...day.entries.map((e) => _EntryTile(entry: e, ref: ref)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'search',
            onPressed: () => context.push('/search'),
            child: const Icon(Icons.search),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: () => context.push('/scan'),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan'),
          ),
        ],
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
                    value: progress,
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
                _MacroRow(label: 'Protein', grams: day.totalProtein),
                _MacroRow(label: 'Carbs', grams: day.totalCarbs),
                _MacroRow(label: 'Fat', grams: day.totalFat),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.label, required this.grams});
  final String label;
  final double grams;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 13))),
            Text('${grams.toStringAsFixed(1)} g', style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
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
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}
