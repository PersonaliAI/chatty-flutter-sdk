import 'dart:async';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as ep;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:record/record.dart';

import 'chatty_api.dart';
import 'chatty_controller.dart';
import 'chatty_design_tokens.dart';
import 'chatty_markdown.dart';

/// Full Chatty chat screen: header (with notification/clear-chat
/// actions), message list, conversation starters, typing indicator, and
/// composer (emoji picker, attach menu, mic recording). Equivalent to the
/// web widget's embed iframe content and to chatty-android-sdk's
/// ChattyChatScreen — sizing/spacing/structure below is ported 1:1 from the
/// same source (EmbedClient.tsx + globals.css + widget.js).
class ChattyChatScreen extends StatefulWidget {
  final String botId;
  final String baseUrl;
  final String? host;
  final String hostKey;
  final void Function(ChattyMessage message)? onMessage;

  /// Called when the header's notification-bell button is tapped (only shown
  /// once POST_NOTIFICATIONS/notification permission is already granted —
  /// see [enableNotificationBell]).
  final VoidCallback? onNotificationBellPress;

  /// Renders a close (X) button in the header when provided — pass this
  /// instead of drawing your own close bar above [ChattyChatScreen] (e.g. in
  /// a dialog/sheet wrapper), so there's one header, not two stacked ones.
  /// [ChattyLauncher] already does this for you.
  final VoidCallback? onClose;

  /// Dangerous-permission policy: this SDK never triggers a system
  /// permission dialog itself — it only reflects whatever the host app has
  /// already granted (or not). Each gated button/option below simply doesn't
  /// render when its permission is missing, rather than showing something
  /// that would either silently no-op or have to request it internally. The
  /// host app owns if/when/how to actually ask (its own
  /// permission_handler `.request()` call elsewhere, however/whenever you
  /// choose); the button appears automatically once granted (re-checked on
  /// app resume) and stays hidden otherwise — matches chatty-android-sdk's
  /// contract exactly. See the SDK README's Permissions section.
  final bool enableVoiceNotes;
  final bool enableNotificationBell;
  final bool enableLocationSharing;

  const ChattyChatScreen({
    super.key,
    required this.botId,
    this.baseUrl = chattyDefaultBaseUrl,
    this.host,
    this.hostKey = 'app',
    this.onMessage,
    this.onNotificationBellPress,
    this.onClose,
    this.enableVoiceNotes = true,
    this.enableNotificationBell = true,
    this.enableLocationSharing = true,
  });

  @override
  State<ChattyChatScreen> createState() => _ChattyChatScreenState();
}

class _ChattyChatScreenState extends State<ChattyChatScreen> with WidgetsBindingObserver {
  late final ChattyController _controller;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();

  bool _showEmojiPicker = false;
  bool _showAttachMenu = false;
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  bool _micGranted = false;
  bool _notificationsGranted = false;
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    _controller = ChattyController(
      botId: widget.botId,
      baseUrl: widget.baseUrl,
      host: widget.host,
      hostKey: widget.hostKey,
      onMessage: widget.onMessage,
    )..addListener(_onControllerChanged);
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-checked on resume, since granting via the host app's own permission
    // dialog or the OS Settings page both resume this screen.
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final mic = await ph.Permission.microphone.status;
    final notif = await ph.Permission.notification.status;
    final loc = await ph.Permission.locationWhenInUse.status;
    if (!mounted) return;
    setState(() {
      _micGranted = mic.isGranted;
      _notificationsGranted = notif.isGranted;
      _locationGranted = loc.isGranted;
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _startRecording() async {
    final dir = Directory.systemTemp;
    final path = '${dir.path}/chatty_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() {
        _recordingSeconds = 0;
        _isRecording = true;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordingSeconds++);
      });
    } catch (_) {
      // mic busy/unavailable — silently no-op rather than crash the composer
    }
  }

  Future<void> _stopRecordingAndTranscribe() async {
    _recordingTimer?.cancel();
    final seconds = _recordingSeconds;
    setState(() => _isRecording = false);
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      // too-short recording etc — just skip transcription
    }
    if (path == null || seconds < 1) return;
    final text = await _controller.transcribeVoiceNote(File(path), 'audio/mp4');
    if (text != null && text.isNotEmpty && mounted) {
      setState(() {
        _inputController.text = _inputController.text.isEmpty ? text : '${_inputController.text} $text';
      });
    }
  }

  void _send() {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    _controller.sendText(text);
    _inputController.clear();
    setState(() {
      _showEmojiPicker = false;
      _showAttachMenu = false;
    });
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    setState(() => _showAttachMenu = false);
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked == null) return;
    final mime = picked.mimeType ?? 'image/jpeg';
    await _controller.sendImage(File(picked.path), mime);
  }

  Future<void> _pickAndSendDocument() async {
    setState(() => _showAttachMenu = false);
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'txt'],
    );
    final file = files.isNotEmpty ? files.first : null;
    if (file?.path == null) return;
    final mime = switch (file!.extension) {
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      _ => 'text/plain',
    };
    await _controller.sendImage(File(file.path!), mime);
  }

  // Matches the web widget exactly: drops a Google Maps link into the
  // composer text rather than sending a special "location message" type —
  // the user still has to tap send.
  Future<void> _shareLocation() async {
    setState(() => _showAttachMenu = false);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final link = 'https://www.google.com/maps?q=${pos.latitude},${pos.longitude}';
      setState(() {
        _inputController.text =
            _inputController.text.isEmpty ? '📍 My location: $link' : '${_inputController.text} 📍 $link';
      });
    } catch (_) {
      // location unavailable — no-op
    }
  }

  @override
  Widget build(BuildContext context) {
    final designId = chattyNormalizeWidgetStyle(_controller.theme?.widgetStyle);
    final cs = _controller.theme?.colorScheme;
    final base = chattyDesignTokens[designId] ?? chattyDesignTokens['minimal']!;
    // The dashboard's per-section color overrides (color_scheme) win over the
    // design preset's own colors wherever a section's bg is set — mirrors
    // buildColorSchemeCss's !important rules on web exactly.
    final t = base.copyWith(
      headerBg: chattyParseColor(cs?.header?.bg) ?? base.headerBg,
      headerText: chattyParseColor(cs?.header?.text) ?? base.headerText,
      botBubbleBg: chattyParseColor(cs?.botBubble?.bg) ?? base.botBubbleBg,
      botBubbleText: chattyParseColor(cs?.botBubble?.text) ?? base.botBubbleText,
      userBubbleBg: chattyParseColor(cs?.userBubble?.bg) ?? base.userBubbleBg,
      userBubbleText: chattyParseColor(cs?.userBubble?.text) ?? base.userBubbleText,
    );
    // Every design's send-btn background matches its user-bubble background
    // on web — reuse that as the "accent" for the send button, unless
    // color_scheme.sendBtn overrides it independently.
    final accent = t.userBubbleBg;
    final sendBtnBg = chattyParseColor(cs?.sendBtn?.bg) ?? accent;
    final sendBtnText = chattyParseColor(cs?.sendBtn?.text) ?? t.userBubbleText;
    final inputBarBg = chattyParseColor(cs?.inputBar?.bg) ?? t.containerBg;
    final inputBarText = chattyParseColor(cs?.inputBar?.text) ?? t.botBubbleText;
    final inputBarIconTint = chattyParseColor(cs?.inputBar?.icon);

    if (!_controller.ready) {
      return Container(
        color: t.containerBg,
        alignment: Alignment.center,
        child: CircularProgressIndicator(color: accent),
      );
    }

    return Container(
      color: t.containerBg,
      // SafeArea keeps the header clear of the status bar on edge-to-edge
      // hosts (a no-op otherwise) — applied here rather than by each caller
      // so a direct full-screen embed and ChattyLauncher's dialog panel both
      // get it right automatically instead of depending on the caller to
      // remember it.
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, t, designId),
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _controller.messages.length + (_controller.sending ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  if (index >= _controller.messages.length) {
                    return _TypingBubble(t: t, avatarIcon: _controller.theme?.avatarIcon, avatarUrl: _controller.theme?.avatarUrl);
                  }
                  final msg = _controller.messages[index];
                  return _Bubble(
                    message: msg,
                    t: t,
                    avatarIcon: _controller.theme?.avatarIcon,
                    avatarUrl: _controller.theme?.avatarUrl,
                    showSenderTag: _controller.theme?.showSenderTag == true,
                  );
                },
              ),
            ),
            if ((_controller.theme?.conversationStarters.isNotEmpty ?? false) && _controller.messages.length <= 1)
              _buildStarters(t),
            if (_controller.aiPaused) _Banner('A human agent has taken over this conversation.', const Color(0xFFFEF3C7)),
            if (_controller.error != null) _Banner(_controller.error!, const Color(0xFFFEE2E2)),
            _buildComposer(context, t, inputBarBg, inputBarText, inputBarIconTint, sendBtnBg, sendBtnText),
            if (_controller.theme?.hideBranding != true)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Powered by Chatty',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.headerText.withValues(alpha: 0.45), fontSize: 9),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ChattyDesignTokens t, String designId) {
    final cs = _controller.theme?.colorScheme;
    final gradientOverride = cs?.header?.bg == null && designId == 'gradient-glow';
    final logoBg = chattyLogoBgColor(_controller.theme?.widgetStyle) ?? t.headerText.withValues(alpha: 0.08);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: gradientOverride ? null : t.headerBg,
        gradient: gradientOverride
            ? const LinearGradient(colors: chattyGradientGlowHeaderColors, begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipOval(
            child: Container(
              width: 44,
              height: 44,
              color: logoBg,
              alignment: Alignment.center,
              child: (_controller.theme?.logoUrl?.isNotEmpty ?? false)
                  ? ClipOval(
                      child: Image.network(_controller.theme!.logoUrl!, width: 34, height: 34, fit: BoxFit.cover),
                    )
                  : Icon(chattyAvatarIcon(_controller.theme?.avatarIcon), color: t.headerText, size: 24),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _controller.theme?.name ?? 'Chatty Assistant',
                  style: TextStyle(color: t.headerText, fontWeight: FontWeight.w600, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _PulsingDot(color: Color(0xFF22C55E)),
                    const SizedBox(width: 4),
                    Text('Online · replies instantly', style: TextStyle(color: t.headerText.withValues(alpha: 0.7), fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              // Only rendered once notification permission is already granted
              // — the SDK never requests it itself.
              if (widget.enableNotificationBell && _notificationsGranted)
                _headerIconButton(Icons.notifications, t.headerText, widget.onNotificationBellPress),
              _headerIconButton(Icons.restart_alt, t.headerText, _controller.clearChat),
              if (widget.onClose != null) _headerIconButton(Icons.close, t.headerText, widget.onClose),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerIconButton(IconData icon, Color tint, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 19, color: tint),
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      splashRadius: 18,
    );
  }

  Widget _buildStarters(ChattyDesignTokens t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final starter in _controller.theme!.conversationStarters)
            OutlinedButton(
              onPressed: () => _controller.sendText(starter),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.userBubbleBg,
                side: BorderSide(color: t.userBubbleBg.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: Text(starter, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer(
    BuildContext context,
    ChattyDesignTokens t,
    Color inputBarBg,
    Color inputBarText,
    Color? inputBarIconTint,
    Color sendBtnBg,
    Color sendBtnText,
  ) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: inputBarBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.headerText.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showEmojiPicker)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: 280,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: t.headerText.withValues(alpha: 0.12)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ep.EmojiPicker(
                        onEmojiSelected: (category, emoji) {
                          _inputController.text += emoji.emoji;
                        },
                        config: const ep.Config(height: 280),
                      ),
                    ),
                  ),
                ),
              ),
            if (_showAttachMenu)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AttachMenu(
                  onCamera: () => _pickAndSendImage(ImageSource.camera),
                  onPhotoLibrary: () => _pickAndSendImage(ImageSource.gallery),
                  onDocuments: _pickAndSendDocument,
                  // Only offered once location permission is already granted
                  // — the SDK never requests it itself.
                  onLocation: (widget.enableLocationSharing && _locationGranted) ? _shareLocation : null,
                ),
              ),
            if (_isRecording)
              _RecordingIndicator(seconds: _recordingSeconds, onStop: _stopRecordingAndTranscribe)
            else
              TextField(
                controller: _inputController,
                style: TextStyle(fontSize: 13, color: inputBarText),
                decoration: const InputDecoration(
                  hintText: 'Type a message…',
                  hintStyle: TextStyle(fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.emoji_emotions_outlined, size: 20, color: inputBarIconTint ?? const Color(0xFF9CA3AF)),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() {
                      _showEmojiPicker = !_showEmojiPicker;
                      _showAttachMenu = false;
                    }),
                  ),
                  IconButton(
                    icon: Icon(Icons.attach_file, size: 20, color: inputBarIconTint ?? const Color(0xFF9CA3AF)),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() {
                      _showAttachMenu = !_showAttachMenu;
                      _showEmojiPicker = false;
                    }),
                  ),
                  // Only rendered once mic permission is already granted —
                  // the SDK never requests it itself.
                  if (widget.enableVoiceNotes && _micGranted)
                    IconButton(
                      icon: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        size: 20,
                        color: _isRecording ? const Color(0xFFEF4444) : (inputBarIconTint ?? const Color(0xFF9CA3AF)),
                      ),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: _isRecording ? _stopRecordingAndTranscribe : _startRecording,
                    ),
                  const Spacer(),
                  _SendButton(
                    style: _controller.theme?.sendButtonStyle,
                    accent: sendBtnBg,
                    textColor: sendBtnText,
                    enabled: _inputController.text.trim().isNotEmpty,
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Mirrors standalone.tsx's LAUNCHER_ICONS map + its MessageCircle fallback
// exactly (bot/headset/headphones/sparkles/message/chat/user, else a round
// chat bubble) — web does NOT default unmatched or "logo" icons to a robot.
IconData chattyAvatarIcon(String? avatarIcon) => switch (avatarIcon) {
      'bot' => Icons.smart_toy,
      'headset' || 'headphones' => Icons.support_agent,
      'sparkles' => Icons.auto_awesome,
      'message' => Icons.chat,
      'chat' => Icons.chat_bubble,
      'user' => Icons.person,
      _ => Icons.chat_bubble, // "logo" (no logoUrl), "custom" (no avatarUrl), or null
    };

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(_controller),
      child: Container(width: 6, height: 6, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Color background;
  const _Banner(this.text, this.background);
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF374151))),
    );
  }
}

class _RecordingIndicator extends StatelessWidget {
  final int seconds;
  final VoidCallback onStop;
  const _RecordingIndicator({required this.seconds, required this.onStop});
  @override
  Widget build(BuildContext context) {
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return Row(
      children: [
        const Icon(Icons.fiber_manual_record, color: Color(0xFFEF4444), size: 12),
        const SizedBox(width: 8),
        Text('Recording $mm:$ss', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        const Spacer(),
        TextButton(onPressed: onStop, child: const Text('Stop')),
      ],
    );
  }
}

class _AttachMenu extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onPhotoLibrary;
  final VoidCallback onDocuments;
  final VoidCallback? onLocation;
  const _AttachMenu({required this.onCamera, required this.onPhotoLibrary, required this.onDocuments, this.onLocation});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _tile(Icons.photo_camera, 'Camera', onCamera),
        _tile(Icons.photo_library, 'Photo Library', onPhotoLibrary),
        _tile(Icons.description, 'Documents', onDocuments),
        if (onLocation != null) _tile(Icons.location_on, 'Location', onLocation!),
      ],
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF4B5563)),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Color(0xFF4B5563))),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final String? style;
  final Color accent;
  final Color textColor;
  final bool enabled;
  final VoidCallback onPressed;
  const _SendButton({required this.style, required this.accent, required this.textColor, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final onTap = enabled ? onPressed : null;
    switch (style) {
      case 'square':
        return _iconButton(Icons.send, RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), onTap);
      case 'label':
        return ElevatedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.send, size: 14),
          label: const Text('Send', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: textColor,
            shape: const StadiumBorder(),
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
        );
      case 'arrowUp':
        return _iconButton(Icons.arrow_upward, const CircleBorder(), onTap);
      case 'arrowRight':
        return _iconButton(Icons.arrow_forward, const CircleBorder(), onTap);
      default:
        return _iconButton(Icons.send, const CircleBorder(), onTap); // "plane" default
    }
  }

  Widget _iconButton(IconData icon, ShapeBorder shape, VoidCallback? onTap) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: enabled ? accent : accent.withValues(alpha: 0.4),
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Icon(icon, size: 16, color: textColor),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChattyMessage message;
  final ChattyDesignTokens t;
  final String? avatarIcon;
  final String? avatarUrl;
  final bool showSenderTag;
  const _Bubble({required this.message, required this.t, this.avatarIcon, this.avatarUrl, required this.showSenderTag});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChattyRole.user;
    final radius = isUser ? t.userBubbleRadius : t.botBubbleRadius;
    return LayoutBuilder(builder: (context, constraints) {
      final maxRowWidth = constraints.maxWidth * 0.88;
      return Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxRowWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isUser) ...[_BotAvatar(avatarIcon: avatarIcon, avatarUrl: avatarUrl, t: t), const SizedBox(width: 8)],
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Matches EmbedClient.tsx's own tiny uppercase sender
                      // label: 9sp, semibold, tracked-out, assistant/agent only.
                      if (!isUser && showSenderTag)
                        Padding(
                          padding: const EdgeInsets.only(left: 2, bottom: 2),
                          child: Text(
                            message.role == ChattyRole.agent ? 'HUMAN AGENT' : 'AI',
                            style: TextStyle(
                              color: t.botBubbleText.withValues(alpha: 0.5),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      Container(
                        decoration: BoxDecoration(
                          color: isUser ? t.userBubbleBg : t.botBubbleBg,
                          borderRadius: chattyBubbleShape(radius, isUser: isUser),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.fileUrl != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(message.fileUrl!, width: 160, height: 120, fit: BoxFit.cover),
                              ),
                            if (message.text.isNotEmpty)
                              isUser
                                  ? Text(message.text, style: TextStyle(color: t.userBubbleText, fontSize: 13))
                                  : ChattyMarkdown(message.text, color: t.botBubbleText, fontSize: 13),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _TypingBubble extends StatelessWidget {
  final ChattyDesignTokens t;
  final String? avatarIcon;
  final String? avatarUrl;
  const _TypingBubble({required this.t, this.avatarIcon, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _BotAvatar(avatarIcon: avatarIcon, avatarUrl: avatarUrl, t: t),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(color: t.botBubbleBg, borderRadius: chattyBubbleShape(t.botBubbleRadius, isUser: false)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: const _TypingDots(),
        ),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = ((_controller.value - i * 0.2) % 1.0).clamp(0.0, 1.0);
            final opacity = 0.3 + 0.7 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF9CA3AF), shape: BoxShape.circle)),
              ),
            );
          }),
        );
      },
    );
  }
}

class _BotAvatar extends StatelessWidget {
  final String? avatarIcon;
  final String? avatarUrl;
  final ChattyDesignTokens t;
  const _BotAvatar({this.avatarIcon, this.avatarUrl, required this.t});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: 28,
        height: 28,
        color: t.headerText.withValues(alpha: 0.08),
        alignment: Alignment.center,
        child: (avatarUrl?.isNotEmpty ?? false)
            ? Image.network(avatarUrl!, width: 28, height: 28, fit: BoxFit.cover)
            : Icon(chattyAvatarIcon(avatarIcon), size: 16, color: t.botBubbleText),
      ),
    );
  }
}
