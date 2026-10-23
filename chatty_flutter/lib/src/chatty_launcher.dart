import 'package:flutter/material.dart';

import 'chatty_api.dart';
import 'chatty_chat_screen.dart' show chattyAvatarIcon;
import 'chatty_embed_screen.dart';
import 'chatty_design_tokens.dart';

enum ChattyPosition { bottomStart, bottomEnd }

/// Floating launcher button + full-screen dialog chat panel — the native-SDK
/// equivalent of widget.js's launcher button + iframe panel. 60dp (widget.js:
/// 60x60px), button color/shadow follow the selected design's own
/// LAUNCHER_STYLES entry unless [color] is explicitly passed, which always
/// wins. Mirrors chatty-android-sdk's ChattyLauncher.
///
/// Positions itself with [Positioned], so drop it directly as a child of
/// your own `Stack` alongside your page content:
/// ```dart
/// Stack(children: [MyPageContent(), ChattyLauncher(botId: '...')])
/// ```
class ChattyLauncher extends StatefulWidget {
  final String botId;
  final String baseUrl;
  final String? host;
  final ChattyPosition position;
  final Color? color;

  /// Called when the visitor taps the in-chat "enable notifications" control.
  /// See ChattyEmbedScreen's own doc comment for the "reflect, never
  /// request" contract this SDK follows.
  final void Function(String? botName)? onRequestNotificationPermission;

  /// Forwarded to [ChattyEmbedScreen]'s onMicPermissionNeeded — see its doc for details.
  final VoidCallback? onMicPermissionNeeded;

  /// Forwarded to [ChattyEmbedScreen]'s onLocationPermissionNeeded — see its doc for details.
  final VoidCallback? onLocationPermissionNeeded;

  const ChattyLauncher({
    super.key,
    required this.botId,
    this.baseUrl = chattyDefaultBaseUrl,
    this.host,
    this.position = ChattyPosition.bottomEnd,
    this.color,
    this.onRequestNotificationPermission,
    this.onMicPermissionNeeded,
    this.onLocationPermissionNeeded,
  });

  @override
  State<ChattyLauncher> createState() => _ChattyLauncherState();
}

class _ChattyLauncherState extends State<ChattyLauncher> {
  bool _open = false;
  int _unread = 0;
  String _designId = 'minimal';
  String? _rawWidgetStyle;
  ChattyColorScheme? _colorScheme;
  // Same avatar_icon the header avatar (in ChattyChatScreen) renders — so the
  // launcher shows the bot's actual configured icon instead of an unrelated
  // fixed glyph, matching web's own launcher (which reads avatarIconType too).
  String? _avatarIcon;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final theme = await ChattyClient(widget.botId, baseUrl: widget.baseUrl, host: widget.host).getTheme();
      if (!mounted) return;
      setState(() {
        _designId = chattyNormalizeWidgetStyle(theme.widgetStyle);
        _rawWidgetStyle = theme.widgetStyle;
        _colorScheme = theme.colorScheme;
        _avatarIcon = theme.avatarIcon;
      });
    } catch (_) {
      // keep the fallback design — a failed theme fetch shouldn't block the button from rendering
    }
  }

  void _openChat() {
    setState(() {
      _open = true;
      _unread = 0;
    });
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      pageBuilder: (context, _, __) {
        final tokens = chattyDesignTokens[_designId] ?? chattyDesignTokens['minimal']!;
        return Scaffold(
          backgroundColor: tokens.containerBg,
          body: ChattyEmbedScreen(
            botId: widget.botId,
            onMessage: () {
              if (!_open) setState(() => _unread++);
            },
            onClose: () => Navigator.of(context).pop(),
            onRequestNotificationPermission: widget.onRequestNotificationPermission,
            onMicPermissionNeeded: widget.onMicPermissionNeeded,
            onLocationPermissionNeeded: widget.onLocationPermissionNeeded,
          ),
        );
      },
    ).then((_) {
      if (mounted) setState(() => _open = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = chattyDesignTokens[_designId] ?? chattyDesignTokens['minimal']!;
    final launcherOverride = _colorScheme?.launcher;
    final resolvedColor = widget.color ?? chattyParseColor(launcherOverride?.bg) ?? tokens.launcherBg;
    // A color_scheme override always wins with a solid color — same as web,
    // where buildColorSchemeCss's launcher rule would also beat the gradient.
    final isGradient = widget.color == null && launcherOverride?.bg == null && _designId == 'gradient-glow';
    final shape = chattyLauncherShape(_rawWidgetStyle);
    final radius = shape.toBorderRadius(isBottomEnd: widget.position == ChattyPosition.bottomEnd);
    // web's launcher icon is a crisp vector line icon (Lucide's
    // MessageCircle by default, or whatever avatarIconType the bot owner
    // picked), not a raw platform emoji glyph.
    final iconTint = chattyParseColor(launcherOverride?.text) ?? Colors.white;
    final launcherIcon = chattyAvatarIcon(_avatarIcon);

    return Positioned(
      bottom: 20,
      left: widget.position == ChattyPosition.bottomStart ? 20 : null,
      right: widget.position == ChattyPosition.bottomEnd ? 20 : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [BoxShadow(color: tokens.launcherShadow, blurRadius: 20, offset: const Offset(0, 6))],
                gradient: isGradient
                    ? const LinearGradient(colors: chattyGradientGlowHeaderColors, begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: isGradient ? null : resolvedColor,
              ),
              child: InkWell(
                borderRadius: radius,
                onTap: _openChat,
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: Icon(launcherIcon, color: iconTint, size: 26),
                ),
              ),
            ),
          ),
          if (_unread > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  _unread > 9 ? '9+' : '$_unread',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
