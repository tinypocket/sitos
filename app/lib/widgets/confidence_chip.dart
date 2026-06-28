import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// The one confidence treatment used everywhere AI proposes something: a 24×24
/// round chip (glyph in tier foreground on a tier background) with a screen-reader
/// label. Never relies on color alone — always glyph + the SR string.
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip(this.tier, {super.key, this.size = 24});

  final ConfidenceTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SitosTokens>()!;
    final (bg, fg, glyph) = tokens.confidence(tier);
    return Semantics(
      label: tier.srLabel,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(
          glyph,
          style: TextStyle(
            fontSize: size * 0.54,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
      ),
    );
  }
}
