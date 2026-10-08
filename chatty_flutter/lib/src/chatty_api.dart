import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

const String chattyDefaultBaseUrl = 'https://api.chatty.personaliai.com';

/// One section's optional bg/text/icon hex overrides — mirrors
/// SectionColorsInput in bots_api.py / WidgetColorScheme in
/// chatty/src/lib/color-contrast.ts.
class ChattySectionColors {
  final String? bg;
  final String? text;
  final String? icon;

  const ChattySectionColors({this.bg, this.text, this.icon});

  factory ChattySectionColors.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChattySectionColors();
    return ChattySectionColors(
      bg: json['bg'] as String?,
      text: json['text'] as String?,
      icon: json['icon'] as String?,
    );
  }
}

/// Per-element color overrides set via the dashboard's widget customizer (or
/// the MCP `customize_widget_styling` tool) — mirrors WidgetColorScheme in
/// chatty/src/lib/color-contrast.ts and buildColorSchemeCss's !important
/// rules exactly: when a section's bg+text are both set, it silently wins
/// over the design preset's own colors, same as on web.
class ChattyColorScheme {
  final ChattySectionColors? header;
  final ChattySectionColors? botBubble;
  final ChattySectionColors? userBubble;
  final ChattySectionColors? inputBar;
  final ChattySectionColors? sendBtn;
  final ChattySectionColors? launcher;

  const ChattyColorScheme({
    this.header,
    this.botBubble,
    this.userBubble,
    this.inputBar,
    this.sendBtn,
    this.launcher,
  });

  factory ChattyColorScheme.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChattyColorScheme();
    return ChattyColorScheme(
      header: ChattySectionColors.fromJson(json['header'] as Map<String, dynamic>?),
      botBubble: ChattySectionColors.fromJson(json['botBubble'] as Map<String, dynamic>?),
      userBubble: ChattySectionColors.fromJson(json['userBubble'] as Map<String, dynamic>?),
      inputBar: ChattySectionColors.fromJson(json['inputBar'] as Map<String, dynamic>?),
      sendBtn: ChattySectionColors.fromJson(json['sendBtn'] as Map<String, dynamic>?),
      launcher: ChattySectionColors.fromJson(json['launcher'] as Map<String, dynamic>?),
    );
  }
}

class ChattyTheme {
  final String? name;
  final String? primaryColor;
  final String? widgetStyle;
  final String? logoUrl;
  final String? welcomeMessage;
  final String? sendButtonStyle;
  final List<String> conversationStarters;
  final String? teaserMessage;
  final String? avatarIcon;
  final String? avatarUrl;
  final ChattyColorScheme? colorScheme;
  /// Shows a small "AI"/"Human agent" label above assistant/agent bubbles —
  /// mirrors web's showSenderTag in EmbedClient.tsx.
  final bool showSenderTag;
  /// Paid-plan white-label flag; hides the "Powered by Chatty" footer when true.
  final bool hideBranding;
  final bool voiceEnabled;

  const ChattyTheme({
    this.name,
    this.primaryColor,
    this.widgetStyle,
    this.logoUrl,
    this.welcomeMessage,
    this.sendButtonStyle,
    this.conversationStarters = const [],
    this.teaserMessage,
    this.avatarIcon,
    this.avatarUrl,
    this.colorScheme,
    this.showSenderTag = false,
    this.hideBranding = false,
    this.voiceEnabled = false,
  });

  factory ChattyTheme.fromJson(Map<String, dynamic> json) {
    return ChattyTheme(
      name: json['name'] as String?,
      primaryColor: json['primary_color'] as String?,
      widgetStyle: json['widget_style'] as String?,
      logoUrl: json['logo_url'] as String?,
      welcomeMessage: json['welcome_message'] as String?,
      sendButtonStyle: json['send_button_style'] as String?,
      conversationStarters: (json['conversation_starters'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      teaserMessage: json['teaser_message'] as String?,
      avatarIcon: json['avatar_icon'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      colorScheme: ChattyColorScheme.fromJson(json['color_scheme'] as Map<String, dynamic>?),
      showSenderTag: json['show_sender_tag'] == true,
      hideBranding: json['hide_branding'] == true,
      voiceEnabled: json['voice_enabled'] == true,
    );
  }
}

class ChattyVoiceToken {
  final String serverUrl;
  final String participantToken;
  final String roomName;
  final String participantName;

  const ChattyVoiceToken({
    required this.serverUrl,
    required this.participantToken,
    required this.roomName,
    required this.participantName,
  });

  factory ChattyVoiceToken.fromJson(Map<String, dynamic> json) => ChattyVoiceToken(
        serverUrl: json['serverUrl'] as String? ?? '',
        participantToken: json['participantToken'] as String? ?? '',
        roomName: json['roomName'] as String? ?? '',
        participantName: json['participantName'] as String? ?? '',
      );
}

class ChattyChatResponse {
  final String reply;
  final String sessionId;
  final bool aiPaused;
  final String? fileUrl;
  final String? fileType;

  const ChattyChatResponse({
    required this.reply,
    required this.sessionId,
    this.aiPaused = false,
    this.fileUrl,
    this.fileType,
  });

  factory ChattyChatResponse.fromJson(Map<String, dynamic> json) {
    return ChattyChatResponse(
      reply: json['reply'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      aiPaused: json['ai_paused'] == true,
      fileUrl: json['file_url'] as String?,
      fileType: json['file_type'] as String?,
    );
  }
}

class ChattyPollMessage {
  final String content;
  final String createdAt;
  final String sender;

  const ChattyPollMessage({required this.content, required this.createdAt, required this.sender});
}

class ChattyPollResponse {
  final List<ChattyPollMessage> messages;
  final bool aiPaused;

  const ChattyPollResponse({required this.messages, required this.aiPaused});

  factory ChattyPollResponse.fromJson(Map<String, dynamic> json) {
    final arr = json['messages'] as List<dynamic>? ?? const [];
    return ChattyPollResponse(
      messages: arr.map((e) {
        final m = e as Map<String, dynamic>;
        return ChattyPollMessage(
          content: m['content'] as String? ?? '',
          createdAt: m['created_at'] as String? ?? '',
          sender: m['sender'] as String? ?? '',
        );
      }).toList(),
      aiPaused: json['ai_paused'] == true,
    );
  }
}

/// The backend can't cryptographically verify a native app's identity the way
/// it verifies a browser's Referer for the web widget, so a bot with
/// allowed_domains configured always rate-limits mobile SDK traffic at the
/// stricter "unverified" tier (5 msgs/120s per bot+IP) rather than the normal
/// tier (30 msgs/60s) — it does NOT reject on a mismatched `host`. The `host`
/// field this client sends is advisory only; the backend doesn't trust it.
class ChattyRateLimitException implements Exception {
  @override
  String toString() =>
      'Chatty: rate limit exceeded — 30 msgs/60s normally, or 5 msgs/120s per bot+IP if allowed_domains is set (mobile traffic always gets this stricter tier)';
}

/// Kept for forward-compatibility — the current backend never returns 403 for
/// domain/origin reasons on these endpoints, but this stays wired up in case
/// that changes.
class ChattyDomainNotAllowedException implements Exception {
  @override
  String toString() => 'Chatty: request rejected (403)';
}

class ChattyRequestException implements Exception {
  final int statusCode;
  ChattyRequestException(this.statusCode);
  @override
  String toString() => 'Chatty request failed: $statusCode';
}

/// Thin HTTP client for the Chatty widget API (the `/api/widget/` routes). No
/// auth header — bot_id alone identifies the bot. bot_id is not a secret
/// (it's extractable from any client); allowed_domains is enforced via
/// rate-limit tier, not a hard reject — see [ChattyRateLimitException].
class ChattyClient {
  final String botId;
  final String baseUrl;
  final String? host;

  // Default http.Client has no built-in timeout — a chat reply can involve
  // RAG retrieval, a scheduling tool-calling round trip (availability check,
  // booking, notification side effects), and Gemini model-fallback retries
  // before the first byte comes back, easily exceeding a short default and
  // surfacing to users as a generic "timeout error" with no other symptom.
  static const _timeout = Duration(seconds: 120);

  ChattyClient(this.botId, {this.baseUrl = chattyDefaultBaseUrl, this.host});

  Future<ChattyTheme> getTheme() async {
    final uri = Uri.parse(
      '$baseUrl/api/widget/theme?bot_id=$botId&t=${DateTime.now().millisecondsSinceEpoch}',
    );
    final json = await _get(uri);
    return ChattyTheme.fromJson(json);
  }

  Future<ChattyChatResponse> sendMessage(
    String sessionId,
    String text, {
    String visitorTimezone = 'UTC',
  }) async {
    final body = <String, dynamic>{
      'bot_id': botId,
      'session_id': sessionId,
      'text': text,
      'visitor_timezone': visitorTimezone,
      if (host != null) 'host': host,
    };
    final json = await _post(Uri.parse('$baseUrl/api/widget/chat'), body);
    return ChattyChatResponse.fromJson(json);
  }

  Future<ChattyChatResponse> sendMedia(
    String sessionId,
    File file,
    String mimeType, {
    String text = '',
    String visitorTimezone = 'UTC',
  }) async {
    final uri = Uri.parse('$baseUrl/api/widget/chat/media');
    final request = http.MultipartRequest('POST', uri)
      ..fields['bot_id'] = botId
      ..fields['session_id'] = sessionId
      ..fields['text'] = text
      ..fields['visitor_timezone'] = visitorTimezone;
    if (host != null) request.fields['host'] = host!;
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      file.path,
      filename: file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'upload',
      contentType: _parseMediaType(mimeType),
    ));
    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    return ChattyChatResponse.fromJson(_decode(response));
  }

  /// Server-side speech-to-text for the mic button. Accepts wav/mp3/ogg/aac/
  /// aiff/flac (not webm) up to 10MB. Returns the transcribed text, or "" if
  /// speech wasn't detected.
  Future<String> transcribe(File file, String mimeType) async {
    final uri = Uri.parse('$baseUrl/api/widget/transcribe');
    final request = http.MultipartRequest('POST', uri)..fields['bot_id'] = botId;
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: _parseMediaType(mimeType),
    ));
    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    final json = _decode(response);
    return json['text'] as String? ?? '';
  }

  /// Creates a short-lived LiveKit participant token for the official
  /// `livekit_client` package. API keys and provider credentials stay server-side.
  Future<ChattyVoiceToken> createVoiceToken(
    String sessionId, {
    String participantName = 'Visitor',
    String visitorTimezone = 'UTC',
  }) async {
    final json = await _post(Uri.parse('$baseUrl/api/widget/voice/token'), {
      'bot_id': botId,
      'session_id': sessionId,
      'participant_name': participantName,
      'visitor_timezone': visitorTimezone,
    });
    return ChattyVoiceToken.fromJson(json);
  }

  Future<ChattyPollResponse> poll(String sessionId, String after) async {
    final uri = Uri.parse('$baseUrl/api/widget/poll?bot_id=$botId&session_id=$sessionId&after=$after');
    final json = await _get(uri);
    return ChattyPollResponse.fromJson(json);
  }

  /// Streams the assistant's reply token-by-token via SSE (`data: {...}` lines).
  Future<void> sendMessageStream(
    String sessionId,
    String text, {
    String visitorTimezone = 'UTC',
    required void Function(String token) onToken,
  }) async {
    final uri = Uri.parse('$baseUrl/api/widget/chat/stream');
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'bot_id': botId,
        'session_id': sessionId,
        'text': text,
        'visitor_timezone': visitorTimezone,
        if (host != null) 'host': host,
      });
    final streamed = await request.send().timeout(_timeout);
    if (streamed.statusCode == 429) throw ChattyRateLimitException();
    if (streamed.statusCode == 403) throw ChattyDomainNotAllowedException();
    if (streamed.statusCode >= 400) throw ChattyRequestException(streamed.statusCode);

    final lines = streamed.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data.isEmpty) continue;
      final json = jsonDecode(data) as Map<String, dynamic>;
      if (json['done'] == true) break;
      final token = json['token'] as String? ?? '';
      if (token.isNotEmpty) onToken(token);
    }
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await http.get(uri).timeout(_timeout);
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, dynamic> body) async {
    final response = await http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(_timeout);
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 429) throw ChattyRateLimitException();
    if (response.statusCode == 403) throw ChattyDomainNotAllowedException();
    if (response.statusCode >= 400) throw ChattyRequestException(response.statusCode);
    if (response.bodyBytes.isEmpty) return const {};
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}

MediaType? _parseMediaType(String mimeType) {
  final parts = mimeType.split('/');
  if (parts.length != 2) return null;
  return MediaType(parts[0], parts[1]);
}
