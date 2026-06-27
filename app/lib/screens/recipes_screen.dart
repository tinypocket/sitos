import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../providers.dart';

class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      body: recipes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load recipes.\n$e', textAlign: TextAlign.center)),
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No recipes yet.\nCreate one from ingredients, set how many servings\n'
                    'it makes, then log your portion.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                children: [
                  for (final r in list)
                    Dismissible(
                      key: ValueKey(r.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Theme.of(context).colorScheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete_outline),
                      ),
                      onDismissed: (_) async {
                        await ref.read(apiProvider).deleteRecipe(r.id);
                        ref.invalidate(recipesProvider);
                      },
                      child: ListTile(
                        title: Text(r.name),
                        subtitle: Text(
                            '${r.perServingCalories.round()} kcal/serving · '
                            '${r.servings} servings · ${r.ingredients.length} ingredients'),
                        trailing: FilledButton.tonal(
                          onPressed: () => _logDialog(context, ref, r),
                          child: const Text('Log'),
                        ),
                        onTap: () => context.push('/recipe/edit', extra: r),
                      ),
                    ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/recipe/edit'),
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
      ),
    );
  }

  Future<void> _logDialog(BuildContext context, WidgetRef ref, Recipe recipe) async {
    final servings = TextEditingController(text: '1');
    var meal = Meal.forTimeOfDay(DateTime.now());
    final date = ref.read(selectedDateProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Log "${recipe.name}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: servings,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Servings eaten'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in Meal.values)
                    ChoiceChip(
                      label: Text(m.label),
                      selected: meal == m,
                      onSelected: (_) => setLocal(() => meal = m),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final qty = double.tryParse(servings.text.trim()) ?? 1;
    try {
      await ref.read(apiProvider).logRecipe(id: recipe.id, date: date, meal: meal, servings: qty);
      ref.invalidate(diaryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Added ${recipe.name} to ${meal.label}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not log: $e')));
      }
    }
  }
}
