import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/confidence_chip.dart';
import 'portion_editor_sheet.dart';
import 'search_screen.dart';

/// E2 · Review & confirm ★ — the keystone. An input-agnostic surface where
/// AI-proposed rows are confirmed before logging. Reused by smart-add, photo, URL.
/// Below the rows: an "Add ingredient" affordance and a greyed Suggestions list
/// (lower-confidence AI items + anything the user just deleted), tap to add.
class ReviewConfirmScreen extends ConsumerStatefulWidget {
  const ReviewConfirmScreen({super.key});

  @override
  ConsumerState<ReviewConfirmScreen> createState() =>
      _ReviewConfirmScreenState();
}

class _ReviewConfirmScreenState extends ConsumerState<ReviewConfirmScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _maybeHint();
  }

  /// The first three times the user lands here, nudge the first row to reveal
  /// the swipe-to-delete action so the gesture is discoverable.
  Future<void> _maybeHint() async {
    final prefs = await SharedPreferences.getInstance();
    final n = prefs.getInt('review.swipeHint') ?? 0;
    if (n >= 3) return;
    await prefs.setInt('review.swipeHint', n + 1);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted && ref.read(addSessionProvider).rows.isNotEmpty) {
        _hint.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

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

  /// "+ Add ingredient" — choose how to add a food the AI missed. Photo is
  /// deliberately omitted so you can't recurse into another meal-photo.
  void _showAddChooser() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search foods'),
              onTap: () {
                Navigator.of(ctx).pop();
                _addViaSearch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Type it'),
              subtitle: const Text('Describe foods in words'),
              onTap: () {
                Navigator.of(ctx).pop();
                _addViaText();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Pick a food from search and append it as a row.
  Future<void> _addViaSearch() async {
    final food = await Navigator.of(context).push<Food>(
      MaterialPageRoute(builder: (_) => const SearchScreen(pickMode: true)),
    );
    if (food == null || !mounted) return;
    final row = ref.read(apiProvider).reviewRowFromFood(
          food,
          id: 'add_${DateTime.now().microsecondsSinceEpoch}',
        );
    ref.read(addSessionProvider.notifier).appendRow(row);
  }

  /// Describe foods in natural language; parse and append the resulting rows.
  Future<void> _addViaText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add foods'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. 2 eggs, a slice of toast'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Find')),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    try {
      final parsed = await ref.read(apiProvider).parseText(text);
      if (!mounted) return;
      final notifier = ref.read(addSessionProvider.notifier);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      var i = 0;
      for (final r in parsed) {
        // Re-id so parseText's 'row_N' ids never collide with existing rows.
        notifier.appendRow(ReviewRow(
          id: 'add_${stamp}_${i++}',
          rawText: r.rawText,
          match: r.match,
          candidates: r.candidates,
          quantity: r.quantity,
          unit: r.unit,
          sizeLabel: r.sizeLabel,
          grams: r.grams,
          calories: r.calories,
          tier: r.tier,
        ));
      }
    } catch (_) {
      if (mounted) _snack("Couldn't add that");
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(addSessionProvider);
    final tokens = Theme.of(context).extension<SitosTokens>()!;

    final subline = switch (s.status) {
      AddStatus.parsing => 'Finding foods…',
      AddStatus.error => 'Something went wrong',
      _ when s.flaggedCount > 0 => '${s.flaggedCount} need a check',
      _ when s.rows.isEmpty => 'Nothing to review',
      _ => '${s.committableCount} ready',
    };

    return PopScope(
      // Reached via context.go from the photo flow → no back stack, so system-back
      // would exit the app. Intercept it and run our in-app cancel instead.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: _cancel,
        ),
        title: const Text('Review & confirm'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(subline,
                  style: TextStyle(color: tokens.subtle, fontSize: 13)),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _MealSelector(meal: s.meal, ref: ref),
          Expanded(child: _body(context, s, tokens)),
        ],
      ),
      bottomNavigationBar: (s.status == AddStatus.ready ||
                  s.status == AddStatus.committing) &&
              s.rows.isNotEmpty
          ? _CommitBar(state: s, ref: ref)
          : null,
      ),
    );
  }

  /// Cancel the in-progress add. Confirms first only if the user edited anything,
  /// then discards the session and returns to the diary.
  Future<void> _cancel() async {
    if (ref.read(addSessionProvider).edited) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your edits to this list will be lost.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Keep editing')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Discard')),
          ],
        ),
      );
      if (discard != true) return;
    }
    ref.read(addSessionProvider.notifier).discard();
    if (mounted) context.go('/');
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget _body(BuildContext context, AddSessionState s, SitosTokens tokens) {
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
    if (s.rows.isEmpty && s.suggestions.isEmpty) {
      return Center(
        child:
            Text('No foods to review.', style: TextStyle(color: tokens.muted)),
      );
    }

    final children = <Widget>[];
    for (var i = 0; i < s.rows.length; i++) {
      final row = s.rows[i];
      Widget tile = _dismissibleRow(context, row, tokens);
      if (i == 0) tile = _withSwipeHint(tile, tokens);
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: tile,
      ));
    }

    children.add(_AddIngredientTile(onTap: _showAddChooser));

    if (s.suggestions.isNotEmpty) {
      children.add(const SizedBox(height: 22));
      children.add(Row(
        children: [
          Text('Suggestions',
              style: TextStyle(
                  color: tokens.subtle,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
          const SizedBox(width: 8),
          Text('tap to add',
              style: TextStyle(color: tokens.muted, fontSize: 12)),
        ],
      ));
      children.add(const SizedBox(height: 10));
      for (final sug in s.suggestions) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SuggestionTile(
            row: sug,
            qtyLabel: _qtyLabel(sug),
            onAdd: () =>
                ref.read(addSessionProvider.notifier).promoteSuggestion(sug.id),
          ),
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: children,
    );
  }

  /// First row gets a one-time peek of the delete action — the red background
  /// behind it, revealed by nudging the card left and back.
  Widget _withSwipeHint(Widget child, SitosTokens tokens) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: tokens.checkBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.delete_outline, color: tokens.checkFg),
          ),
        ),
        AnimatedBuilder(
          animation: _hint,
          builder: (_, c) => Transform.translate(
            offset: Offset(-54 * math.sin(_hint.value * math.pi), 0),
            child: c,
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _dismissibleRow(
      BuildContext context, ReviewRow row, SitosTokens tokens) {
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
        final notifier = ref.read(addSessionProvider.notifier);
        final removed = notifier.removeRow(row.id);
        if (removed == null) return;
        // Park it in Suggestions so it stays recoverable after the snackbar fades.
        notifier.addSuggestion(removed.$1);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 3),
            dismissDirection: DismissDirection.horizontal, // swipe to dismiss
            content:
                Text('Removed ${removed.$1.match?.name ?? removed.$1.rawText}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                notifier.removeSuggestion(removed.$1.id);
                notifier.insertRow(removed.$1, removed.$2);
              },
            ),
          ));
      },
      child: _RowTile(row: row, qtyLabel: _qtyLabel(row)),
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
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () {
                        ref
                            .read(addSessionProvider.notifier)
                            .replaceRow(_withMatch(row, f));
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

/// Outlined "+ Add ingredient" affordance below the rows.
class _AddIngredientTile extends StatelessWidget {
  const _AddIngredientTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final grove = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: grove.withValues(alpha: 0.5), width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: grove, size: 20),
              const SizedBox(width: 8),
              Text('Add ingredient',
                  style: TextStyle(
                      color: grove,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A greyed lower-confidence item (AI suggestion or one the user deleted). Tap
/// to promote it into the active rows.
class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile(
      {required this.row, required this.qtyLabel, required this.onAdd});
  final ReviewRow row;
  final String qtyLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    final grove = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onAdd,
        child: Container(
          decoration: BoxDecoration(
            color: tokens.paper,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.hairline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.match?.name ?? row.rawText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tokens.muted),
                    ),
                    const SizedBox(height: 1),
                    Text('$qtyLabel · ${row.calories.round()} kcal',
                        style: TextStyle(fontSize: 11, color: tokens.muted)),
                  ],
                ),
              ),
              Icon(Icons.add_circle_outline, color: grove, size: 24),
            ],
          ),
        ),
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
    // Capture before awaiting: a successful commit resets the session and navigates,
    // tearing down this bar, so `context`/`mounted` are unreliable afterwards.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(addSessionProvider.notifier).commit(date);
      ref.invalidate(diaryProvider);
      router.go('/');
      messenger
          .showSnackBar(SnackBar(content: Text('Added to ${meal.label}')));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not add: $e')));
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
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
