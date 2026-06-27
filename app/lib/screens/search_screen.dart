import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../providers.dart';

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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
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
                    ..._results.map((f) => ListTile(
                          title: Text(f.name),
                          subtitle: Text(
                              '${f.brand != null ? '${f.brand} · ' : ''}${f.caloriesPer100g.round()} kcal/100g'),
                          onTap: () => widget.pickMode
                              ? Navigator.of(context).pop(f)
                              : context.pushReplacement('/food', extra: f),
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
}
