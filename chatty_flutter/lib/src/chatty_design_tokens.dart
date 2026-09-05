import 'package:flutter/material.dart';

/// The 10 widget designs' visual tokens, ported 1:1 from the web widget's
/// globals.css (`.style-*` rules) and widget.js's `LAUNCHER_STYLES` — same
/// source of truth chatty-android-sdk's ChattyDesignTokens.kt was ported
/// from, so this stays in sync with both. Font pairing (each design uses a
/// distinct Google Font on web) is intentionally out of scope here, same
/// reasoning as the Android SDK — colors, radii, and structural sizing carry
/// most of a design's visual identity.
class ChattyDesignTokens {
  final Color containerBg;
  final Color headerBg;
  final Color headerText;
  final Color botBubbleBg;
  final Color botBubbleText;
  final double botBubbleRadius;
  final Color userBubbleBg;
  final Color userBubbleText;
  final double userBubbleRadius;
  // widget.js's LAUNCHER_STYLES — NOT always the same as userBubbleBg (e.g.
  // dark-sleek's launcher is dark, not its teal accent; neubrutalism's
  // launcher is black, not its pink accent).
  final Color launcherBg;
  final Color launcherShadow;

  const ChattyDesignTokens({
    required this.containerBg,
    required this.headerBg,
    required this.headerText,
    required this.botBubbleBg,
    required this.botBubbleText,
    required this.botBubbleRadius,
    required this.userBubbleBg,
    required this.userBubbleText,
    required this.userBubbleRadius,
    required this.launcherBg,
    required this.launcherShadow,
  });

  ChattyDesignTokens copyWith({
    Color? containerBg,
    Color? headerBg,
    Color? headerText,
    Color? botBubbleBg,
    Color? botBubbleText,
    double? botBubbleRadius,
    Color? userBubbleBg,
    Color? userBubbleText,
    double? userBubbleRadius,
    Color? launcherBg,
    Color? launcherShadow,
  }) {
    return ChattyDesignTokens(
      containerBg: containerBg ?? this.containerBg,
      headerBg: headerBg ?? this.headerBg,
      headerText: headerText ?? this.headerText,
      botBubbleBg: botBubbleBg ?? this.botBubbleBg,
      botBubbleText: botBubbleText ?? this.botBubbleText,
      botBubbleRadius: botBubbleRadius ?? this.botBubbleRadius,
      userBubbleBg: userBubbleBg ?? this.userBubbleBg,
      userBubbleText: userBubbleText ?? this.userBubbleText,
      userBubbleRadius: userBubbleRadius ?? this.userBubbleRadius,
      launcherBg: launcherBg ?? this.launcherBg,
      launcherShadow: launcherShadow ?? this.launcherShadow,
    );
  }
}

Color _c(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

/// Safe hex parser for color_scheme overrides — a malformed/missing stored
/// value should silently fall back to the design preset's own color, never
/// throw.
Color? chattyParseColor(String? hex) {
  if (hex == null || hex.trim().isEmpty) return null;
  try {
    return _c(hex.trim());
  } catch (_) {
    return null;
  }
}

// gradient-glow's header/launcher is a linear-gradient(#a855f7, #ec4899) on
// web; a LinearGradient is used directly at call sites for that one design
// instead of trying to encode a gradient into a single Color.
const List<Color> chattyGradientGlowHeaderColors = [Color(0xFFA855F7), Color(0xFFEC4899)];

final Map<String, ChattyDesignTokens> chattyDesignTokens = {
  'minimal': ChattyDesignTokens(
    containerBg: _c('#f3f2ee'), headerBg: _c('#ffffff'), headerText: _c('#1c1a15'),
    botBubbleBg: _c('#f3f2ee'), botBubbleText: _c('#1c1a15'), botBubbleRadius: 14,
    userBubbleBg: _c('#1c1a15'), userBubbleText: _c('#ffffff'), userBubbleRadius: 14,
    launcherBg: _c('#1c1a15'), launcherShadow: const Color(0x2E000000),
  ),
  'playful': ChattyDesignTokens(
    containerBg: _c('#fffaf5'), headerBg: _c('#ff8a5c'), headerText: _c('#ffffff'),
    botBubbleBg: _c('#ffe6d9'), botBubbleText: _c('#7a3f24'), botBubbleRadius: 20,
    userBubbleBg: _c('#ff8a5c'), userBubbleText: _c('#ffffff'), userBubbleRadius: 20,
    launcherBg: _c('#ff8a5c'), launcherShadow: const Color(0x73FF8A5C),
  ),
  'corporate': ChattyDesignTokens(
    containerBg: _c('#eef1f6'), headerBg: _c('#1c2e4a'), headerText: _c('#ffffff'),
    botBubbleBg: _c('#eef1f6'), botBubbleText: _c('#1c2e4a'), botBubbleRadius: 8,
    userBubbleBg: _c('#1c2e4a'), userBubbleText: _c('#ffffff'), userBubbleRadius: 8,
    launcherBg: _c('#1c2e4a'), launcherShadow: const Color(0x4C1C2E4A),
  ),
  'dark-sleek': ChattyDesignTokens(
    containerBg: _c('#111114'), headerBg: _c('#14141a'), headerText: _c('#e4e4e8'),
    botBubbleBg: _c('#1c1c22'), botBubbleText: _c('#e4e4e8'), botBubbleRadius: 12,
    userBubbleBg: _c('#00e5c7'), userBubbleText: _c('#05201c'), userBubbleRadius: 12,
    // Launcher is dark (matches header), not the teal accent bubble color.
    launcherBg: _c('#14141a'), launcherShadow: const Color(0x5900E5C7),
  ),
  // headerBg/launcherBg here are placeholders — see chattyGradientGlowHeaderColors above.
  'gradient-glow': ChattyDesignTokens(
    containerBg: _c('#ffffff'), headerBg: _c('#a855f7'), headerText: _c('#ffffff'),
    botBubbleBg: _c('#f6effc'), botBubbleText: _c('#4a2467'), botBubbleRadius: 16,
    userBubbleBg: _c('#a855f7'), userBubbleText: _c('#ffffff'), userBubbleRadius: 16,
    launcherBg: _c('#a855f7'), launcherShadow: const Color(0x66A855F7),
  ),
  'glassmorphism': ChattyDesignTokens(
    containerBg: _c('#8f6ff0'), headerBg: const Color(0x14FFFFFF), headerText: _c('#ffffff'),
    botBubbleBg: const Color(0x2EFFFFFF), botBubbleText: _c('#ffffff'), botBubbleRadius: 14,
    userBubbleBg: const Color(0xE6FFFFFF), userBubbleText: _c('#39396b'), userBubbleRadius: 14,
    // Launcher is translucent white (rgba(255,255,255,.25)), lighter than the near-opaque user bubble.
    launcherBg: const Color(0x40FFFFFF), launcherShadow: const Color(0x33000000),
  ),
  'ecommerce': ChattyDesignTokens(
    containerBg: _c('#fdf9f2'), headerBg: _c('#0f9d8c'), headerText: _c('#ffffff'),
    botBubbleBg: _c('#f3efe6'), botBubbleText: _c('#3a3226'), botBubbleRadius: 14,
    userBubbleBg: _c('#0f9d8c'), userBubbleText: _c('#ffffff'), userBubbleRadius: 14,
    launcherBg: _c('#0f9d8c'), launcherShadow: const Color(0x590F9D8C),
  ),
  'healthcare-calm': ChattyDesignTokens(
    containerBg: _c('#fbfcf9'), headerBg: _c('#eaf1e9'), headerText: _c('#2f4235'),
    botBubbleBg: _c('#eaf1e9'), botBubbleText: _c('#2f4235'), botBubbleRadius: 14,
    userBubbleBg: _c('#6f9c7d'), userBubbleText: _c('#ffffff'), userBubbleRadius: 14,
    launcherBg: _c('#6f9c7d'), launcherShadow: const Color(0x596F9C7D),
  ),
  'neubrutalism': ChattyDesignTokens(
    containerBg: _c('#ffffff'), headerBg: _c('#ffde59'), headerText: _c('#111111'),
    botBubbleBg: _c('#f2f2f2'), botBubbleText: _c('#111111'), botBubbleRadius: 4,
    userBubbleBg: _c('#ff3d67'), userBubbleText: _c('#ffffff'), userBubbleRadius: 4,
    // Launcher is black with a hard offset shadow, not the pink accent bubble color.
    launcherBg: _c('#111111'), launcherShadow: _c('#111111'),
  ),
  'luxury-editorial': ChattyDesignTokens(
    containerBg: _c('#fbf9f5'), headerBg: _c('#161412'), headerText: _c('#f5efe3'),
    botBubbleBg: _c('#f1ebdf'), botBubbleText: _c('#2a251d'), botBubbleRadius: 2,
    userBubbleBg: _c('#161412'), userBubbleText: _c('#f5efe3'), userBubbleRadius: 2,
    launcherBg: _c('#161412'), launcherShadow: const Color(0x4D000000),
  ),
};

/// Mirrors widget-style.ts's LEGACY_STYLE_MAP — every historical widget_style
/// ID across all 3 preset generations this project has shipped, mapped onto
/// one of the 10 current design keys above.
const Map<String, String> _chattyLegacyStyleMap = {
  'liquid': 'glassmorphism', 'neumorphism': 'corporate', 'claymorphism': 'playful',
  'bento': 'minimal', 'brutalism': 'neubrutalism', 'retro': 'dark-sleek', 'aurora': 'gradient-glow',
  'minimalist': 'minimal', 'elevated': 'corporate', 'frosted': 'glassmorphism',
  'bold': 'gradient-glow', 'contrast': 'dark-sleek',
};

/// `widgetStyle` from the theme API is `"{styleId}:{logoBgColor}:{launcherShape}"`.
String chattyNormalizeWidgetStyle(String? raw) {
  if (raw == null || raw.isEmpty) return 'minimal';
  final id = raw.split(':').first;
  if (chattyDesignTokens.containsKey(id)) return id;
  return _chattyLegacyStyleMap[id] ?? 'minimal';
}

/// The 2nd colon-segment of `widgetStyle`, e.g. `"minimal:#fff:bubble"` ->
/// `"#fff"` — overrides the header/bubble avatar circle's background when a
/// real logo/avatar image isn't shown.
Color? chattyLogoBgColor(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final hex = parts[1].trim();
  if (hex.isEmpty) return null;
  return chattyParseColor(hex);
}

enum ChattyLauncherShapeKind { circle, square, rounded, bubble }

class ChattyLauncherShape {
  final ChattyLauncherShapeKind kind;
  const ChattyLauncherShape(this.kind);

  BorderRadius toBorderRadius({required bool isBottomEnd}) {
    switch (kind) {
      case ChattyLauncherShapeKind.square:
        return BorderRadius.zero;
      case ChattyLauncherShapeKind.rounded:
        return BorderRadius.circular(12);
      case ChattyLauncherShapeKind.bubble:
        return isBottomEnd
            ? const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
                bottomRight: Radius.circular(30),
                bottomLeft: Radius.circular(4),
              )
            : const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
                bottomRight: Radius.circular(4),
                bottomLeft: Radius.circular(30),
              );
      case ChattyLauncherShapeKind.circle:
        return BorderRadius.circular(999);
    }
  }
}

/// The 3rd colon-segment of `widgetStyle` controls the launcher button's
/// corner shape: `square` -> 0 corners, `rounded` -> 12dp corners, `bubble`
/// -> an asymmetric "speech tail" corner, anything else (including absent)
/// -> a full circle, matching widget.js.
ChattyLauncherShape chattyLauncherShape(String? raw) {
  final parts = raw?.split(':') ?? const <String>[];
  final shapeId = parts.length > 2 ? parts[2].trim() : null;
  switch (shapeId) {
    case 'square':
      return const ChattyLauncherShape(ChattyLauncherShapeKind.square);
    case 'rounded':
      return const ChattyLauncherShape(ChattyLauncherShapeKind.rounded);
    case 'bubble':
      return const ChattyLauncherShape(ChattyLauncherShapeKind.bubble);
    default:
      return const ChattyLauncherShape(ChattyLauncherShapeKind.circle);
  }
}

/// Message bubble shape with the corner nearest the avatar squared off,
/// matching web's `.rounded-tl-none` (bot) / `.rounded-tr-none` (user) — the
/// "speech tail" corner treatment used by every design.
BorderRadius chattyBubbleShape(double radius, {required bool isUser}) {
  final r = Radius.circular(radius);
  return isUser
      ? BorderRadius.only(topLeft: r, topRight: Radius.zero, bottomRight: r, bottomLeft: r)
      : BorderRadius.only(topLeft: Radius.zero, topRight: r, bottomRight: r, bottomLeft: r);
}
