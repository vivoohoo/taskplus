import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ornate Samanvay's colours (its styles.css), light and dark, in the Standard (green) or Google (blue) style.
@immutable
class Ornate extends ThemeExtension<Ornate> {
  const Ornate({
    required this.bg, required this.panel, required this.text, required this.muted, required this.line, required this.brand,
    required this.accent, required this.accentText, required this.accentInk, required this.inBubble, required this.outBubble,
    required this.wall, required this.wallDot, required this.chip, required this.chipOn, required this.chipOnText, required this.badge,
    required this.badgeText, required this.tick, required this.danger, required this.dangerBg, required this.glass,
    required this.greenBg, required this.green, required this.orangeBg, required this.orange, required this.redBg, required this.red,
    required this.neutralBg, required this.neutral,
  });
  final Color bg, panel, text, muted, line, brand, accent, accentText, accentInk, inBubble, outBubble, wall, wallDot, chip, chipOn, chipOnText,
      badge, badgeText, tick, danger, dangerBg, glass, greenBg, green, orangeBg, orange, redBg, red, neutralBg, neutral;

  static const light = Ornate(
    bg: Color(0xFFFFFFFF), panel: Color(0xFFF0F2F5), text: Color(0xFF111B21), muted: Color(0xFF54656F), line: Color(0xFFE9EDEF),
    brand: Color(0xFF008069), accent: Color(0xFF008069), accentText: Color(0xFFFFFFFF), accentInk: Color(0xFF00684D),
    inBubble: Color(0xFFFFFFFF), outBubble: Color(0xFFD9FDD3), wall: Color(0xFFEFEAE2), wallDot: Color(0xFFE2DBD0),
    chip: Color(0xFFF0F2F5), chipOn: Color(0xFFD9FDD3), chipOnText: Color(0xFF005C4B), badge: Color(0xFF25D366), badgeText: Color(0xFF0B141A),
    tick: Color(0xFF027EB5), danger: Color(0xFFC0262D), dangerBg: Color(0xFFFDE2E1), glass: Color(0xD1FFFFFF),
    greenBg: Color(0xFFD9FDD3), green: Color(0xFF00684D), orangeBg: Color(0xFFFFE6C7), orange: Color(0xFF8A4300),
    redBg: Color(0xFFFDE2E1), red: Color(0xFFB42318), neutralBg: Color(0xFFE9EDEF), neutral: Color(0xFF3B4A54),
  );
  static const dark = Ornate(
    bg: Color(0xFF111B21), panel: Color(0xFF202C33), text: Color(0xFFE9EDEF), muted: Color(0xFF9AABB4), line: Color(0xFF222D34),
    brand: Color(0xFF21C063), accent: Color(0xFF00A884), accentText: Color(0xFF0B141A), accentInk: Color(0xFF4CD6B0),
    inBubble: Color(0xFF202C33), outBubble: Color(0xFF005C4B), wall: Color(0xFF0B141A), wallDot: Color(0xFF16232B),
    chip: Color(0xFF202C33), chipOn: Color(0xFF103529), chipOnText: Color(0xFF6FDCB4), badge: Color(0xFF00A884), badgeText: Color(0xFF0B141A),
    tick: Color(0xFF53BDEB), danger: Color(0xFFF47A85), dangerBg: Color(0xFF3F1D22), glass: Color(0xD120262A),
    greenBg: Color(0xFF103529), green: Color(0xFF6FDCB4), orangeBg: Color(0xFF3D2A12), orange: Color(0xFFFDBA74),
    redBg: Color(0xFF3F1D22), red: Color(0xFFFCA5A5), neutralBg: Color(0xFF2A3942), neutral: Color(0xFFD1D7DB),
  );

  /// Google style (You > Style): blue accents instead of green.
  Ornate google(bool isDark) => copyWith(
        accent: isDark ? const Color(0xFF8AB4F8) : const Color(0xFF1A73E8),
        accentText: isDark ? const Color(0xFF062E6F) : const Color(0xFFFFFFFF),
        accentInk: isDark ? const Color(0xFFA8C7FA) : const Color(0xFF0B57D0),
        brand: isDark ? const Color(0xFFA8C7FA) : const Color(0xFF0B57D0),
        outBubble: isDark ? const Color(0xFF1F3760) : const Color(0xFFD3E3FD),
        chipOn: isDark ? const Color(0xFF1F3760) : const Color(0xFFD3E3FD),
        chipOnText: isDark ? const Color(0xFFD3E3FD) : const Color(0xFF0B57D0),
      );

  /// Chat wallpaper (You > Chat wallpaper).
  Ornate wallpaper(String id, bool isDark) => switch (id) {
        'plain' => copyWith(wallDot: wall),
        'mint' => copyWith(wall: isDark ? const Color(0xFF0E2620) : const Color(0xFFDCEFE4), wallDot: isDark ? const Color(0xFF16352D) : const Color(0xFFC8E2D2)),
        'sky' => copyWith(wall: isDark ? const Color(0xFF0D1D2B) : const Color(0xFFDDE9F4), wallDot: isDark ? const Color(0xFF15293B) : const Color(0xFFC9DBEB)),
        'blush' => copyWith(wall: isDark ? const Color(0xFF26171A) : const Color(0xFFF4E3E1), wallDot: isDark ? const Color(0xFF352225) : const Color(0xFFE8D0CD)),
        _ => this,
      };

  @override
  Ornate copyWith({Color? accent, Color? accentText, Color? accentInk, Color? brand, Color? outBubble, Color? chipOn, Color? chipOnText, Color? wall, Color? wallDot}) => Ornate(
        bg: bg, panel: panel, text: text, muted: muted, line: line, brand: brand ?? this.brand, accent: accent ?? this.accent,
        accentText: accentText ?? this.accentText, accentInk: accentInk ?? this.accentInk, inBubble: inBubble, outBubble: outBubble ?? this.outBubble,
        wall: wall ?? this.wall, wallDot: wallDot ?? this.wallDot, chip: chip, chipOn: chipOn ?? this.chipOn, chipOnText: chipOnText ?? this.chipOnText,
        badge: badge, badgeText: badgeText, tick: tick, danger: danger, dangerBg: dangerBg, glass: glass, greenBg: greenBg, green: green,
        orangeBg: orangeBg, orange: orange, redBg: redBg, red: red, neutralBg: neutralBg, neutral: neutral,
      );

  @override
  Ornate lerp(Ornate? other, double t) => t < 0.5 || other == null ? this : other;
}

extension OrnateOf on BuildContext {
  Ornate get o => Theme.of(this).extension<Ornate>() ?? Ornate.light;
}

class AppTheme {
  /// Set by the browser demo to its bundled fonts; the phone uses the system font.
  static String? font;
  static List<String>? fallback;

  static ThemeData light([Appearance a = const Appearance()]) => _build(Brightness.light, a);
  static ThemeData dark([Appearance a = const Appearance()]) => _build(Brightness.dark, a);

  static ThemeData _build(Brightness b, Appearance a) {
    final isDark = b == Brightness.dark;
    var o = isDark ? Ornate.dark : Ornate.light;
    if (a.style == 'google') o = o.google(isDark);
    o = o.wallpaper(a.wallpaper, isDark);
    final scheme = ColorScheme.fromSeed(seedColor: o.accent, brightness: b).copyWith(
      primary: o.accent, onPrimary: o.accentText, surface: o.bg, onSurface: o.text, onSurfaceVariant: o.muted,
      error: o.danger, outlineVariant: o.line, surfaceContainerHigh: o.panel, primaryContainer: o.outBubble,
    );
    return ThemeData(
      fontFamily: font, fontFamilyFallback: fallback,
      colorScheme: scheme,
      scaffoldBackgroundColor: o.bg,
      extensions: [o],
      appBarTheme: AppBarTheme(centerTitle: false, backgroundColor: o.bg, foregroundColor: o.text, elevation: 0, scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(fontFamily: font, fontSize: 19, fontWeight: FontWeight.w600, color: o.text)),
      dividerColor: o.line,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: o.accent, foregroundColor: o.accentText,
          minimumSize: const Size(44, 44), shape: const StadiumBorder(), textStyle: const TextStyle(fontWeight: FontWeight.w600))),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: o.accentInk, minimumSize: const Size(44, 44))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: o.accent, foregroundColor: o.accentText,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: isDark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21),
          contentTextStyle: TextStyle(color: isDark ? const Color(0xFF111B21) : Colors.white)),
    );
  }
}

/// Per-phone look (Ornate's You page): light or dark, colour style, chat wallpaper. Remembered on this phone.
class Appearance {
  const Appearance({this.mode = ThemeMode.system, this.style = 'standard', this.wallpaper = 'default'});
  final ThemeMode mode;
  final String style, wallpaper;
  Appearance copy({ThemeMode? mode, String? style, String? wallpaper}) =>
      Appearance(mode: mode ?? this.mode, style: style ?? this.style, wallpaper: wallpaper ?? this.wallpaper);
}

const themeLabels = {ThemeMode.system: 'System default', ThemeMode.light: 'Light', ThemeMode.dark: 'Dark'};
const styleLabels = {'standard': 'Standard', 'google': 'Google'};
const wallpaperLabels = {'default': 'Default', 'plain': 'Plain', 'mint': 'Mint', 'sky': 'Sky', 'blush': 'Blush'};

final appearanceProvider = NotifierProvider<AppearanceController, Appearance>(AppearanceController.new);

class AppearanceController extends Notifier<Appearance> {
  @override
  Appearance build() {
    SharedPreferences.getInstance().then((p) {
      state = Appearance(
        mode: ThemeMode.values.firstWhere((m) => m.name == p.getString('theme'), orElse: () => ThemeMode.system),
        style: p.getString('style') ?? 'standard',
        wallpaper: p.getString('wallpaper') ?? 'default',
      );
    }).catchError((_) {});
    return const Appearance();
  }

  Future<void> set(Appearance a) async {
    state = a;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('theme', a.mode.name);
      await p.setString('style', a.style);
      await p.setString('wallpaper', a.wallpaper);
    } catch (_) {/* tests, private mode */}
  }
}
