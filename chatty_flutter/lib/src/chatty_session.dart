import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors the web widget's session id scheme (`chatty_sid_{botId}_{hostKey}`
/// in localStorage) so the same visitor is recognized whether they arrive via
/// web or the native app, when `hostKey` is shared deliberately. Same shape
/// as chatty-android-sdk's ChattySession (SharedPreferences there,
/// shared_preferences here — same underlying platform storage on Android).
class ChattySession {
  ChattySession._();

  static Future<String> getOrCreateSessionId(String botId, {String hostKey = 'app'}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chatty_sid_${botId}_$hostKey';
    final existing = prefs.getString(key);
    if (existing != null) return existing;
    return newSession(botId, hostKey: hostKey);
  }

  /// Overwrites the stored session id with a fresh one — used by the
  /// "clear chat" action.
  static Future<String> newSession(String botId, {String hostKey = 'app'}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chatty_sid_${botId}_$hostKey';
    final sid = 'v-${_randomHex(32)}';
    await prefs.setString(key, sid);
    return sid;
  }

  static String _randomHex(int length) {
    final random = Random.secure();
    const chars = '0123456789abcdef';
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
