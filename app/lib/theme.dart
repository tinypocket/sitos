import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models.dart';

/// Design tokens from the entry-experience handoff that don't fit `ColorScheme`
/// (paper/card/ink, muted text, hairlines, honey accent, and the four confidence
/// tiers). Access via `Theme.of(context).extension<SitosTokens>()!`.
@immutable
class SitosTokens extends ThemeExtension<SitosTokens> {
  final Color paper; // app background
  final Color card; // cards, sheets, rows
  final Color ink; // primary text
  final Color subtle; // secondary text
  final Color muted; // captions, meta, placeholder
  final Color hairline; // row borders, dividers
  final Color honey; // streaks / accent only

  // Confidence tiers — (background, foreground).
  final Color verifiedBg, verifiedFg;
  final Color estimatedBg, estimatedFg;
  final Color checkBg, checkFg;
  final Color noMatchBg, noMatchFg;

  const SitosTokens({
    required this.paper,
    required this.card,
    required this.ink,
    required this.subtle,
    required this.muted,
    required this.hairline,
    required this.honey,
    required this.verifiedBg,
    required this.verifiedFg,
    required this.estimatedBg,
    required this.estimatedFg,
    required this.checkBg,
    required this.checkFg,
    required this.noMatchBg,
    required this.noMatchFg,
  });

  static const light = SitosTokens(
    paper: Color(0xFFF7F8F4),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF1F2A24),
    subtle: Color(0xFF5D6B62),
    muted: Color(0xFF8A978D),
    hairline: Color(0xFFEDF0EA),
    honey: Color(0xFFE8A13C),
    verifiedBg: Color(0xFFE4F1E9),
    verifiedFg: Color(0xFF1F6B42),
    estimatedBg: Color(0xFFFBECCB),
    estimatedFg: Color(0xFFB6791F),
    checkBg: Color(0xFFF6DDCF),
    checkFg: Color(0xFFB8542C),
    noMatchBg: Color(0xFFEEF0EC),
    noMatchFg: Color(0xFF8A978D),
  );

  /// (background, foreground, glyph) for a confidence tier.
  (Color, Color, String) confidence(ConfidenceTier t) => switch (t) {
        ConfidenceTier.verified => (verifiedBg, verifiedFg, '✓'), // ✓
        ConfidenceTier.estimated => (estimatedBg, estimatedFg, '≈'), // ≈
        ConfidenceTier.checkThis => (checkBg, checkFg, '!'),
        ConfidenceTier.noMatch => (noMatchBg, noMatchFg, '?'),
      };

  @override
  SitosTokens copyWith() => this;

  @override
  SitosTokens lerp(ThemeExtension<SitosTokens>? other, double t) => this;
}

const _grove = Color(0xFF2F8F5B);

/// The Sitos light theme. Dark theme is a later pass — not built yet.
ThemeData sitosTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: _grove).copyWith(
    primary: _grove,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFE4F1E9),
    onPrimaryContainer: const Color(0xFF1F6B42),
    tertiary: const Color(0xFFE8A13C),
    surface: const Color(0xFFF7F8F4),
    onSurface: const Color(0xFF1F2A24),
    surfaceContainerHighest: const Color(0xFFEDF0EA),
    onSurfaceVariant: const Color(0xFF5D6B62),
    outlineVariant: const Color(0xFFEDF0EA),
    error: const Color(0xFFB8542C),
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = GoogleFonts.hankenGroteskTextTheme(base.textTheme).copyWith(
    titleLarge: GoogleFonts.hankenGrotesk(
        fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface),
    titleMedium: GoogleFonts.hankenGrotesk(
        fontSize: 18, fontWeight: FontWeight.w800, color: scheme.onSurface),
    bodyMedium: GoogleFonts.hankenGrotesk(
        fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
  );

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    extensions: const [SitosTokens.light],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.hankenGrotesk(
          fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFFFFFFFF),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Number style with tabular figures (calorie totals, steppers).
TextStyle displayNumber(BuildContext context, {double size = 30}) =>
    GoogleFonts.hankenGrotesk(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.03 * size,
      color: Theme.of(context).extension<SitosTokens>()!.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle tabular(BuildContext context,
        {double size = 15, FontWeight weight = FontWeight.w700, Color? color}) =>
    GoogleFonts.hankenGrotesk(
      fontSize: size,
      fontWeight: weight,
      color: color ?? Theme.of(context).extension<SitosTokens>()!.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
