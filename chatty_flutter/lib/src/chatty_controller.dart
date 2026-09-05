import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chatty_api.dart';
import 'chatty_session.dart';

enum ChattyRole { user, assistant, agent }

class ChattyMessage {
  final String id;
  final ChattyRole role;
  final String text;
  final String createdAt;
  final String? fileUrl;

  ChattyMessage({
    String? id,
    required this.role,
    required this.text,
    String? createdAt,
    this.fileUrl,
  })  : id = id ?? _randomId(),
        createdAt = createdAt ?? DateTime.now().toUtc().toIso8601String();

  ChattyMessage copyWith({String? text}) => ChattyMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        createdAt: createdAt,
        fileUrl: fileUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'createdAt': createdAt,
        if (fileUrl != null) 'fileUrl': fileUrl,
      };

  factory ChattyMessage.fromJson(Map<String, dynamic> json) {
    return ChattyMessage(
      id: json['id'] as String? ?? _randomId(),
      role: ChattyRole.values.firstWhere(
        (r) => r.name == (json['role'] as String? ?? 'user'),
        orElse: () => ChattyRole.user,
      ),
      text: json['text'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
      fileUrl: (json['fileUrl'] as String?)?.isNotEmpty == true ? json['fileUrl'] as String : null,
    );
  }

  static String _randomId() {
    final r = Random.secure();
    const chars = '0123456789abcdef';
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

/// Drives a full Chatty conversation: loads bot theme/config, manages the
/// persistent session id, sends messages, and polls for human-agent replies
/// every 4s — the native-SDK equivalent of widget.js's embed iframe
/// lifecycle. Mirrors chatty-android-sdk's ChattyViewModel (ChangeNotifier
/// here takes the place of Android's ViewModel + StateFlow).
class ChattyController extends ChangeNotifier {
  final String botId;
  final String baseUrl;
  final String? host;
  final String hostKey;
  final Duration pollInterval;
  final String visitorTimezone;
  final void Function(ChattyMessage message)? onMessage;

  late final ChattyClient _client;
  String? _sessionId;
  String _lastPollAt = DateTime.now().toUtc().toIso8601String();
  Timer? _pollTimer;

  ChattyTheme? theme;
  bool ready = false;
  List<ChattyMessage> messages = [];
  bool sending = false;
  bool aiPaused = false;
  String? error;

  ChattyController({
    required this.botId,
    this.baseUrl = chattyDefaultBaseUrl,
    this.host,
    this.hostKey = 'app',
    this.pollInterval = const Duration(seconds: 4),
    String? visitorTimezone,
    this.onMessage,
  }) : visitorTimezone = visitorTimezone ?? DateTime.now().timeZoneName {
    _client = ChattyClient(botId, baseUrl: baseUrl, host: host);
    _init();
  }

  String get _msgPrefsKey => 'chatty_msgs_${botId}_$hostKey';

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(_msgPrefsKey);
    if (cachedJson != null) {
      try {
        final arr = jsonDecode(cachedJson) as List<dynamic>;
        messages = arr.map((e) => ChattyMessage.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        messages = [];
      }
    }
    notifyListeners();

    try {
      final fetchedTheme = await _client.getTheme();
      _sessionId = await ChattySession.getOrCreateSessionId(botId, hostKey: hostKey);
      final welcome = fetchedTheme.welcomeMessage != null && fetchedTheme.welcomeMessage!.isNotEmpty
          ? [ChattyMessage(id: 'welcome', role: ChattyRole.assistant, text: fetchedTheme.welcomeMessage!)]
          : <ChattyMessage>[];
      final wasEmpty = messages.isEmpty;
      if (wasEmpty) messages = welcome;
      theme = fetchedTheme;
      ready = true;
      notifyListeners();
      if (wasEmpty && welcome.isNotEmpty) await _persistMessages(messages);
      _startPolling();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> _persistMessages(List<ChattyMessage> msgs) async {
    final toStore = msgs.length > 100 ? msgs.sublist(msgs.length - 100) : msgs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_msgPrefsKey, jsonEncode(toStore.map((m) => m.toJson()).toList()));
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) async {
      final sid = _sessionId;
      if (sid == null) return;
      try {
        final res = await _client.poll(sid, _lastPollAt);
        if (res.messages.isNotEmpty) {
          _lastPollAt = res.messages.last.createdAt;
          final newMsgs = res.messages
              .map((m) => ChattyMessage(
                    // Backend's /api/widget/poll is server-side filtered to
                    // sender="human" rows only (see widget.py's widget_poll) —
                    // every message that arrives here is a human-agent reply.
                    role: ChattyRole.agent,
                    text: m.content,
                    createdAt: m.createdAt,
                  ))
              .toList();
          messages = [...messages, ...newMsgs];
          await _persistMessages(messages);
          aiPaused = res.aiPaused;
          notifyListeners();
          for (final m in newMsgs) {
            onMessage?.call(m);
          }
        } else {
          aiPaused = res.aiPaused;
          notifyListeners();
        }
      } catch (_) {
        // silent — polling failures shouldn't surface as user-facing errors
      }
    });
  }

  Future<void> sendTextStream(String text) async {
    final trimmed = text.trim();
    final sid = _sessionId;
    if (sid == null || trimmed.isEmpty) return;

    final userMsg = ChattyMessage(role: ChattyRole.user, text: trimmed);
    final assistantId = ChattyMessage._randomId();
    var placeholder = ChattyMessage(id: assistantId, role: ChattyRole.assistant, text: '');

    messages = [...messages, userMsg, placeholder];
    sending = true;
    error = null;
    notifyListeners();
    await _persistMessages(messages);

    try {
      await _client.sendMessageStream(
        sid,
        trimmed,
        visitorTimezone: visitorTimezone,
        onToken: (token) {
          messages = messages
              .map((m) => m.id == assistantId ? m.copyWith(text: m.text + token) : m)
              .toList();
          notifyListeners();
          unawaited(_persistMessages(messages));
        },
      );
      final finished = messages.where((m) => m.id == assistantId).firstOrNull;
      if (finished != null) onMessage?.call(finished);
    } catch (_) {
      messages = messages.where((m) => m.id != userMsg.id && m.id != assistantId).toList();
      await _persistMessages(messages);
      notifyListeners();
      await sendText(trimmed);
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    final sid = _sessionId;
    if (sid == null || trimmed.isEmpty) return;

    messages = [...messages, ChattyMessage(role: ChattyRole.user, text: trimmed)];
    sending = true;
    error = null;
    notifyListeners();
    await _persistMessages(messages);

    try {
      final res = await _client.sendMessage(sid, trimmed, visitorTimezone: visitorTimezone);
      aiPaused = res.aiPaused;
      if (!res.aiPaused && res.reply.isNotEmpty) {
        final reply = ChattyMessage(role: ChattyRole.assistant, text: res.reply);
        messages = [...messages, reply];
        await _persistMessages(messages);
        onMessage?.call(reply);
      }
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  /// Clears the local conversation and starts a fresh session — the native
  /// equivalent of web's header "clear chat" button.
  Future<void> clearChat() async {
    _sessionId = await ChattySession.newSession(botId, hostKey: hostKey);
    final welcome = theme?.welcomeMessage != null && theme!.welcomeMessage!.isNotEmpty
        ? [ChattyMessage(id: 'welcome', role: ChattyRole.assistant, text: theme!.welcomeMessage!)]
        : <ChattyMessage>[];
    messages = welcome;
    aiPaused = false;
    error = null;
    notifyListeners();
    await _persistMessages(welcome);
    _lastPollAt = DateTime.now().toUtc().toIso8601String();
  }

  /// Uploads a recorded voice note for server-side transcription (mic
  /// button). Errors are swallowed to null since a failed transcription
  /// shouldn't surface as a chat error banner.
  Future<String?> transcribeVoiceNote(File file, String mimeType) async {
    try {
      final text = await _client.transcribe(file, mimeType);
      return text.trim().isNotEmpty ? text : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> sendImage(File file, String mimeType, {String caption = ''}) async {
    final sid = _sessionId;
    if (sid == null) return;
    messages = [...messages, ChattyMessage(role: ChattyRole.user, text: caption, fileUrl: file.path)];
    sending = true;
    error = null;
    notifyListeners();
    await _persistMessages(messages);

    try {
      final res = await _client.sendMedia(sid, file, mimeType, text: caption, visitorTimezone: visitorTimezone);
      aiPaused = res.aiPaused;
      if (!res.aiPaused && res.reply.isNotEmpty) {
        final reply = ChattyMessage(role: ChattyRole.assistant, text: res.reply);
        messages = [...messages, reply];
        await _persistMessages(messages);
        onMessage?.call(reply);
      }
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
