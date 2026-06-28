import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/confidence_chip.dart';
import 'portion_editor_sheet.dart';

/// E2 · Review & confirm ★ — the keystone. An input-agnostic surface where
/// AI-proposed rows are confirmed before logging. Reused by smart-add, photo, URL.
class ReviewConfirmScreen extends ConsumerWidget {
  const ReviewConfirmScreen({super.key});

  String _qtyLabel(ReviewRow r) {
    switch (r.unit) {
      case QuantityUnit.grams:
        return '${r.grams.round()} g';
      case QuantityUnit.servings:
        final q = r.quantity == r.quantity.roundToDouble()
            ? r.quantity.round().toString()
            : r.quantity.toStringAsFixed(1);
        return '$q serving${r.quantity == 1 ? '' : 's'}';
      case QuantityUnit.countSize:
        final n = r.quantity.round();
        return r.sizeLabel != null ? '$n ${r.sizeLabel}' : '$n×';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(addSessionProvider);
    final tokens = Theme.of(context).extension<SitosTokens>()!;

    final subline = switch (s.status) {
      AddStatus.parsing => 'Finding foods…',
      AddStatus.error => 'Something went wrong',
      _ when s.flaggedCount > 0 => '${s.flaggedCount} need a check',
      _ when s.rows.isEmpty => 'Nothing to review',
      _ => '${s.committableCount} ready',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review & confirm'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(subline, style: TextStyle(color: tokens.subtle, fontSize: 13)),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _MealSelector(meal: s.meal, ref: ref),
          Expanded(child: _body(context, ref, s, tokens)),
        ],
      ),
      bottomNavigationBar: s.status == AddStatus.ready && s.rows.isNotEmpty
          ? _CommitBar(state: s, ref: ref)
          : null,
    );
  }

  Widget _body(
      BuildContext context, WidgetRef ref, AddSessionState s, SitosTokens tokens) {
    if (s.status == AddStatus.parsing) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(4, (_) => const _SkeletonRow()),
      );
    }
    if (s.status == AddStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: tokens.muted),
              const SizedBox(height: 12),
              Text(s.error ?? 'Could not parse your meal.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: () => context.pop(), child: const Text('Go back')),
            ],
          ),
        ),
      );
    }
    if (s.rows.isEmpty) {
      return Center(
        child: Text('No foods to review.', style: TextStyle(color: tokens.muted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: s.rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final row = s.rows[i];
        return Dismissible(
          key: ValueKey(row.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: tokens.checkBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.delete_outline, color: tokens.checkFg),
          ),
          onDismissed: (_) {
            final removed = ref.read(addSessionProvider.notifier).removeRow(row.id);
            if (removed == null) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text('Removed ${removed.$1.match?.name ?? removed.$1.rawText}'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => ref
                      .read(addSessionProvider.notifier)
                      .insertRow(removed.$1, removed.$2),
                ),
              ));
          },
          child: _RowTile(row: row, qtyLabel: _qtyLabel(row)),
        );
      },
    );
  }
}

class _RowTile extends ConsumerWidget {
  const _RowTile({required this.row, required this.qtyLabel});
  final ReviewRow row;
  final String qtyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    final (_, fg, _) = tokens.confidence(row.tier);
    final isNoMatch = row.tier == ConfidenceTier.noMatch;
    final isCheck = row.tier == ConfidenceTier.checkThis;

    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCheck ? tokens.checkFg : tokens.hairline,
          width: isCheck ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _swap(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ConfidenceChip(row.tier),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.match?.name ?? row.rawText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isNoMatch ? tokens.muted : tokens.ink,
                        decoration:
                            isNoMatch ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: isNoMatch
                          ? null
                          : () => showPortionEditor(context, ref, row),
                      child: Text(
                        isNoMatch ? 'No database match' : qtyLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: row.tier == ConfidenceTier.verified
                              ? tokens.muted
                              : fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isNoMatch)
                Text('—', style: TextStyle(color: tokens.muted))
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${row.calories.round()}',
                        style: tabular(context, size: 15)),
                    Text('kcal',
                        style: TextStyle(fontSize: 10, color: tokens.muted)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _swap(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: const Color(0x52151F1A),
      builder: (_) => _SwapSheet(row: row, ref: ref),
    );
  }
}

class _SwapSheet extends StatelessWidget {
  const _SwapSheet({required this.row, required this.ref});
  final ReviewRow row;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    return Padding(
      padding: EdgeInsets.only(
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Pick the right match',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('for “${row.rawText}”',
                style: TextStyle(color: tokens.muted, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          if (row.candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text('No matches found. Try Search to add it manually.',
                  style: TextStyle(color: tokens.muted)),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in row.candidates)
                    ListTile(
                      title: Text(f.name),
                      subtitle: Text(
                          '${f.caloriesPer100g.round()} kcal/100g${f.brand != null ? ' · ${f.brand}' : ''}'),
                      trailing: row.match?.id == f.id
                          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () {
                        ref.read(addSessionProvider.notifier).replaceRow(_withMatch(row, f));
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static ReviewRow _withMatch(ReviewRow row, Food f) {
    final grams = row.unit == QuantityUnit.grams
        ? row.grams
        : row.quantity * (f.servingSizeGrams ?? 100);
    return row.copyWith(
      match: f,
      grams: grams,
      calories: f.caloriesPer100g * grams / 100.0,
      tier: ConfidenceTier.estimated,
    );
  }
}

class _MealSelector extends StatelessWidget {
  const _MealSelector({required this.meal, required this.ref});
  final Meal meal;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final m in Meal.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(m.label),
                selected: m == meal,
                onSelected: (_) =>
                    ref.read(addSessionProvider.notifier).setMeal(m),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommitBar extends StatefulWidget {
  const _CommitBar({required this.state, required this.ref});
  final AddSessionState state;
  final WidgetRef ref;

  @override
  State<_CommitBar> createState() => _CommitBarState();
}

class _CommitBarState extends State<_CommitBar> {
  bool _busy = false;

  Future<void> _commit() async {
    setState(() => _busy = true);
    final ref = widget.ref;
    final meal = widget.state.meal;
    final date = ref.read(selectedDateProvider);
    try {
      await ref.read(addSessionProvider.notifier).commit(date);
      ref.invalidate(diaryProvider);
      if (!mounted) return;
      context.go('/');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to ${meal.label}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not add: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    final n = s.committableCount;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (s.excludedCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${s.excludedCount} not added (no match)',
                    style: TextStyle(color: tokens.muted, fontSize: 12)),
              ),
            FilledButton(
              onPressed: (n == 0 || _busy) ? null : _commit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(n == 0
                      ? 'Nothing to add yet'
                      : 'Add $n to ${s.meal.label} · ${s.committableKcal.round()} kcal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 64,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.hairline),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Container(
            width: 24,
            height: 24,
            decoration:
                BoxDecoration(color: tokens.hairline, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 140, height: 12, color: tokens.hairline),
                const SizedBox(height: 8),
                Container(width: 60, height: 10, color: tokens.hairline),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
