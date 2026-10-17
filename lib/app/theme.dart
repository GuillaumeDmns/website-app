import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors of states, beside the color scheme: real time, delays, warnings (the last metro), cancellations
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.live,
    required this.delayed,
    required this.warning,
    required this.cancelled,
    required this.card,
    required this.muted,
    required this.subtle,
  });

  /// Real-time departures, the time to leave
  final Color live;

  /// Late departures
  final Color delayed;

  /// What needs attention without being an error: last metro, elevators, schedule only
  final Color warning;

  /// Cancelled departures, interrupted traffic
  final Color cancelled;

  /// Cards on the page background
  final Color card;

  /// Secondary text
  final Color muted;

  /// Fills of tags, chips and fields
  final Color subtle;

  static const light = AppColors(
    live: Color(0xFF0A8F4E),
    delayed: Color(0xFFB45309),
    warning: Color(0xFFC2410C),
    cancelled: Color(0xFFD92D20),
    card: Colors.white,
    muted: Color(0xFF5F6673),
    subtle: Color(0xFFEDEFF2),
  );

  static const dark = AppColors(
    live: Color(0xFF3DD68C),
    delayed: Color(0xFFF5A524),
    warning: Color(0xFFFB923C),
    cancelled: Color(0xFFFF6B60),
    card: Color(0xFF1B1E23),
    muted: Color(0xFF9AA1AC),
    subtle: Color(0xFF262A30),
  );

  @override
  AppColors copyWith({Color? live, Color? delayed, Color? warning, Color? cancelled, Color? card, Color? muted, Color? subtle}) =>
      AppColors(
        live: live ?? this.live,
        delayed: delayed ?? this.delayed,
        warning: warning ?? this.warning,
        cancelled: cancelled ?? this.cancelled,
        card: card ?? this.card,
        muted: muted ?? this.muted,
        subtle: subtle ?? this.subtle,
      );

  @override
  AppColors lerp(AppColors? other, double t) => other == null
      ? this
      : AppColors(
          live: Color.lerp(live, other.live, t)!,
          delayed: Color.lerp(delayed, other.delayed, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          cancelled: Color.lerp(cancelled, other.cancelled, t)!,
          card: Color.lerp(card, other.card, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          subtle: Color.lerp(subtle, other.subtle, t)!,
        );
}

extension AppColorsOf on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
}

/// Citymapper-like: a light grey page with white cards, near-black text, one green for what moves (real time,
/// GO, actions), line colors as the only other colors. Inter is bundled in 400, 500 and 600 only: nothing bolder.
abstract final class AppTheme {
  /// The app's green: actions, GO, the user's choices
  static const Color brand = Color(0xFF0A8F4E);
  static const Color brandDark = Color(0xFF3DD68C);

  // Light surfaces: the page (behind the cards), the cards, lines between rows
  static const Color lightPage = Color(0xFFF3F4F6);
  static const Color lightText = Color(0xFF14171C);
  static const Color lightOutline = Color(0xFFE1E4E8);

  static const Color darkPage = Color(0xFF101215);
  static const Color darkText = Color(0xFFECEEF1);
  static const Color darkOutline = Color(0xFF2C3036);

  static const radius = 16.0;

  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final light = brightness == Brightness.light;
    final colors = light ? AppColors.light : AppColors.dark;
    final primary = light ? brand : brandDark;
    final text = light ? lightText : darkText;
    final page = light ? lightPage : darkPage;
    final outline = light ? lightOutline : darkOutline;
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
      primary: primary,
      onPrimary: light ? Colors.white : const Color(0xFF00210F),
      secondary: light ? const Color(0xFF1D4ED8) : const Color(0xFF7AA7FF),
      surface: page,
      onSurface: text,
      onSurfaceVariant: colors.muted,
      surfaceContainerHighest: colors.subtle,
      surfaceContainerHigh: colors.card,
      outline: outline,
      outlineVariant: outline,
      error: colors.cancelled,
    );

    final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: text, displayColor: text).copyWith(
          headlineSmall: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.4),
          titleLarge: GoogleFonts.inter(fontSize: 21, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.3),
          titleMedium: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.2),
          titleSmall: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: text),
          bodyLarge: GoogleFonts.inter(fontSize: 16, color: text),
          bodyMedium: GoogleFonts.inter(fontSize: 15, color: text),
          bodySmall: GoogleFonts.inter(fontSize: 13, color: colors.muted),
          labelLarge: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: text),
          labelMedium: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: colors.muted),
        );
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));

    return base.copyWith(
      extensions: [colors],
      textTheme: textTheme,
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
      scaffoldBackgroundColor: page,
      canvasColor: page,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: page,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          // Dark cards need no edge; light ones a hairline, like Citymapper's
          side: light ? BorderSide(color: outline.withValues(alpha: 0.7), width: 0.5) : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.muted,
        titleTextStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle: textTheme.bodySmall,
      ),
      iconTheme: IconThemeData(color: text),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: primary, width: 1.5)),
        hintStyle: GoogleFonts.inter(color: colors.muted, fontSize: 16),
        labelStyle: GoogleFonts.inter(color: colors.muted),
        prefixIconColor: colors.muted,
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 0.5, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: colors.card,
        selectedColor: primary.withValues(alpha: light ? 0.14 : 0.24),
        side: BorderSide(color: outline),
        shape: pill,
        labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: text),
        iconTheme: IconThemeData(color: text, size: 18),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(pill),
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? text : colors.card,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? page : text,
          ),
          textStyle: WidgetStatePropertyAll(GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: light ? const Color(0xFF1F242B) : const Color(0xFF2C323A),
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 15),
        actionTextColor: brandDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: scheme.onPrimary,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
          shape: pill,
          minimumSize: const Size(double.infinity, 52),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          backgroundColor: colors.card,
          side: BorderSide(color: outline),
          shape: pill,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: pill,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.card,
        foregroundColor: text,
        elevation: 2,
        shape: const CircleBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: page,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary, linearTrackColor: colors.subtle),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
