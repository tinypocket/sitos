import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../theme.dart';

/// E1 · Add entry point. A modal bottom sheet of input methods; Scan is the
/// one-tap hero. Opened from the diary's center + (and pre-targeted from a meal
/// row, which passes [meal]).
Future<void> showAddEntrySheet(BuildContext context, {Meal? meal}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: const Color(0x52151F1A), // rgba(31,42,36,.32)
    builder: (sheetContext) => _AddEntrySheet(pageContext: context, meal: meal),
  );
}

class _AddEntrySheet extends StatelessWidget {
  const _AddEntrySheet({required this.pageContext, this.meal});

  /// The route context (not the sheet's) — used to navigate after dismissing.
  final BuildContext pageContext;
  final Meal? meal;

  void _go(BuildContext sheetContext, String location, {Object? extra}) {
    Navigator.of(sheetContext).pop();
    pageContext.push(location, extra: extra);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 10,
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Add to your diary',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          // Hero — Scan, always first, one tap.
          _HeroCard(
            onTap: () => _go(context, '/scan'),
            scheme: scheme,
          ),
          const SizedBox(height: 12),
          // Secondary grid, ordered by priority.
          Row(
            children: [
              _Tile(
                icon: Icons.auto_awesome_outlined,
                label: 'Smart add',
                highlight: true,
                onTap: () => _go(context, '/add/smart', extra: meal),
              ),
              const SizedBox(width: 10),
              _Tile(
                icon: Icons.photo_camera_outlined,
                label: 'Photo',
                // Take a photo of a Nutrition Facts label → add a new food (B1–B5).
                onTap: () => _go(context, '/food/new'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Tile(
                icon: Icons.search,
                label: 'Search',
                onTap: () => _go(context, '/search'),
              ),
              const SizedBox(width: 10),
              _Tile(
                icon: Icons.bookmark_outline,
                label: 'My meals',
                onTap: () => _go(context, '/recipes'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 4),
            child: Text(
              meal == null ? '' : 'Adding to ${meal!.label}',
              style: TextStyle(color: tokens.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onTap, required this.scheme});
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x572F8F5B), // grove glow .34
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Scan a barcode',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('under 5 seconds',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    return Expanded(
      child: Material(
        color: highlight ? scheme.primaryContainer : tokens.card,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: highlight ? scheme.primary.withValues(alpha: 0.5) : tokens.hairline,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    size: 22,
                    color: highlight ? scheme.onPrimaryContainer : tokens.subtle),
                const SizedBox(width: 10),
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: highlight ? scheme.onPrimaryContainer : tokens.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
