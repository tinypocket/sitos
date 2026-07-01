import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../providers.dart';
import '../recent_foods.dart';
import '../theme.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.pickMode = false});

  /// When true, tapping a result pops with the selected [Food] (for picking a recipe
  /// ingredient) instead of navigating to log it.
  final bool pickMode;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  List<Food> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Rebuild as the query changes so the empty-state recents show/hide.
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (_controller.text.trim().isEmpty && _results.isNotEmpty) {
      setState(() => _results = []);
    } else {
      setState(() {});
    }
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).record(q);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref.read(apiProvider).searchFoods(q);
      setState(() => _results = results);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Re-runs a previously used query.
  void _runRecentSearch(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _search();
  }

  /// Records the picked food into recents, then does the existing pick/navigate.
  void _pickFood(Food f) {
    ref.read(pickedFoodsProvider.notifier).record(f);
    if (widget.pickMode) {
      Navigator.of(context).pop(f);
    } else {
      context.pushReplacement('/food', extra: f);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search foods…',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _search(),
        ),
        actions: [IconButton(onPressed: _search, icon: const Icon(Icons.search))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Search failed.\n$_error', textAlign: TextAlign.center))
              : ListView(
                  children: [
                    if (_showRecents) ..._buildRecents(context),
                    ..._results.map((f) => ListTile(
                          title: Text(f.name),
                          subtitle: Text(
                              '${f.brand != null ? '${f.brand} · ' : ''}${f.caloriesPer100g.round()} kcal/100g'),
                          onTap: () => _pickFood(f),
                        )),
                    if (!widget.pickMode) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('Add a new food'),
                        subtitle: const Text("Can't find it? Enter it manually."),
                        onTap: () => context.pushReplacement('/food/new'),
                      ),
                    ],
                  ],
                ),
    );
  }

  /// Recents only make sense on the blank slate: empty query and no results.
  bool get _showRecents => _controller.text.trim().isEmpty && _results.isEmpty;

  List<Widget> _buildRecents(BuildContext context) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    final searches = ref.watch(recentSearchesProvider);
    final foods = ref.watch(pickedFoodsProvider);
    return [
      if (searches.isNotEmpty) ...[
        _sectionHeader(context, 'Recent searches'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in searches)
                ActionChip(
                  label: Text(q),
                  onPressed: () => _runRecentSearch(q),
                ),
            ],
          ),
        ),
      ],
      if (foods.isNotEmpty) ...[
        _sectionHeader(context, 'Recently picked'),
        for (final f in foods) ...[
          ListTile(
            title: Text(f.name),
            subtitle: Text(
                '${f.brand != null ? '${f.brand} · ' : ''}${f.caloriesPer100g.round()} kcal/100g'),
            onTap: () => _pickFood(f),
          ),
          Divider(height: 1, color: tokens.hairline),
        ],
      ],
    ];
  }

  Widget _sectionHeader(BuildContext context, String label) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: tokens.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
