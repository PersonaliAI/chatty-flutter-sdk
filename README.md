<div align="center">

# Chatty Flutter SDK

**Official Flutter SDK for [Chatty](https://github.com/PersonaliAI/chatty) AI chatbots — Web Widget Parity via Script Method & 100% Native Flutter UI.**

Drop a fully functional, on-brand support chat into any Flutter app in minutes. Supports both the **Script Method** (`ChattyEmbedScreen` for guaranteed 1:1 web widget parity) and **Native Components** (`ChattyChatScreen` and `ChattyLauncher` with CommonMark, GFM tables, and LaTeX equations).

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?logo=flutter&logoColor=white)](#requirements)

[Install](#install) · [Quick start](#quick-start) · [Permissions](#permissions-architecture) · [API reference](#api-reference)

</div>

---

## Why this SDK

| | |
|---|---|
| **Script Method (100% Web Widget Parity)** | `ChattyEmbedScreen` hosts the exact production web widget (`/embed/{botId}`) in a hardened WebView with voice recording, file upload, AI search, CSAT, OEM font isolation (`textZoom: 100`), and raw alert suppression. |
| **Native Components Alternative** | `ChattyChatScreen` and `ChattyLauncher` render every bubble, avatar, and input with real Flutter widgets. |
| **Real CommonMark & LaTeX Math** | Supports GitHub-flavored Markdown (tables, strikethrough, blockquotes, code blocks with copy) and LaTeX equations (`$inline$` and `$$block$$`). |
| **"Reflect, Never Request" Permissions** | The SDK never prompts unsolicited OS dialogs. It reflects existing permissions and fires contextual callbacks (`onMicPermissionNeeded`, `onLocationPermissionNeeded`, `onRequestNotificationPermission`). |
| **Automatic Dashboard Theming** | Resolves the bot's theme tokens, colors, corner radii, and conversation starters automatically from the Chatty API. |

---

## Install

Add `chatty_flutter` to your `pubspec.yaml`:

```yaml
dependencies:
  chatty_flutter:
    path: ../chatty_flutter # or pub.dev dependency
```

---

## Quick start

Find your bot ID in the Chatty dashboard under **Embed & Integrate → Flutter SDK**.

### Option A: Script Method (`ChattyEmbedScreen` — Recommended for 100% Web Parity)

Loads the bot's own web widget page inside a hardened WebView. Guaranteed pixel-for-pixel parity with the web widget:

```dart
import 'package:chatty_flutter/chatty_flutter.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ChattyEmbedScreen(
          botId: 'YOUR_BOT_ID',
          onReady: () => debugPrint('Chat loaded and ready'),
          onMessage: () => debugPrint('New message received'),
          onClose: () => Navigator.of(context).pop(),
          onRequestNotificationPermission: (botName) async {
            // Request notification permission contextually
            await Permission.notification.request();
          },
          onMicPermissionNeeded: () async {
            // Request microphone permission contextually when user taps mic
            await Permission.microphone.request();
          },
          onLocationPermissionNeeded: () async {
            // Request location permission contextually when user taps "Location"
            await Permission.locationWhenInUse.request();
          },
        ),
      ),
    );
  }
}
```

### Option B: Floating Launcher (`ChattyLauncher`)

A floating action button that opens a chat dialog:

```dart
import 'package:chatty_flutter/chatty_flutter.dart';
import 'package:flutter/material.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Your main app screen
        const ChattyLauncher(
          botId: 'YOUR_BOT_ID',
          position: ChattyPosition.bottomRight,
        ),
      ],
    );
  }
}
```

### Option C: Native Full-Screen Chat (`ChattyChatScreen`)

```dart
import 'package:chatty_flutter/chatty_flutter.dart';
import 'package:flutter/material.dart';

class NativeChatScreen extends StatelessWidget {
  const NativeChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: ChattyChatScreen(botId: 'YOUR_BOT_ID'),
      ),
    );
  }
}
```

---

## Permissions Architecture

This SDK strictly adheres to the **"Reflect, Never Request"** contract. It never displays native OS permission dialogs unsolicited.

### Permission Mapping

| Feature | Android Permission | iOS Info.plist Key | SDK Callback |
|---|---|---|---|
| **Voice Notes (`getUserMedia`)** | `android.permission.RECORD_AUDIO`<br>`android.permission.MODIFY_AUDIO_SETTINGS` | `NSMicrophoneUsageDescription` | `onMicPermissionNeeded` |
| **Location Share (`geolocation`)** | `android.permission.ACCESS_COARSE_LOCATION`<br>`android.permission.ACCESS_FINE_LOCATION` | `NSLocationWhenInUseUsageDescription` | `onLocationPermissionNeeded` |
| **Notifications** | `android.permission.POST_NOTIFICATIONS` | N/A (UserNotifications API) | `onRequestNotificationPermission` |

### Android Setup (`android/app/src/main/AndroidManifest.xml`)

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
</manifest>
```

### iOS Setup (`ios/Runner/Info.plist`)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need access to your microphone to record voice messages for support.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to share with support.</string>
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to attach photos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library to attach photos.</string>
```

---

## Markdown & LaTeX Math

`ChattyMarkdown` renders CommonMark + GFM (tables, strikethrough, blockquotes, code blocks with copy) and LaTeX equations (`$inline$` and `$$block$$`):

```dart
import 'package:chatty_flutter/chatty_flutter.dart';
import 'package:flutter/material.dart';

const markdown = '''
# Quadratic Equation
Solve \$\$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\$\$ for \$x\$.

| Step | Operation |
| --- | --- |
| 1 | Compute discriminant |
| 2 | Evaluate roots |
''';

Widget buildEquation() {
  return const ChattyMarkdown(
    markdown,
    color: Color(0xFF111827),
    fontSize: 13,
  );
}
```

---

## API Reference

### `ChattyEmbedScreen` (Script Method)

| Parameter | Type | Description |
|---|---|---|
| `botId` | `String` | **Required.** Your Chatty bot ID. |
| `baseUrl` | `String` | Base widget URL (defaults to `https://chatty.personaliai.com`). |
| `onReady` | `VoidCallback?` | Called when the web widget finishes loading and React hydrates. |
| `onMessage` | `VoidCallback?` | Called whenever the assistant or agent sends a reply. |
| `onClose` | `VoidCallback?` | Called when the visitor taps close or completes CSAT. |
| `onRequestNotificationPermission` | `void Function(String?)?` | Called when visitor taps the in-chat notification bell. |
| `onMicPermissionNeeded` | `VoidCallback?` | Called when visitor taps the mic and `RECORD_AUDIO` is not yet granted. |
| `onLocationPermissionNeeded` | `VoidCallback?` | Called when visitor selects Location and location permission is not yet granted. |

---

## License

MIT License. Copyright (c) PersonaliAI.

## LiveKit voice

Call `ChattyClient(botId).createVoiceToken(sessionId)` and connect the result
with the official `livekit_client` package. `ChattyEmbedScreen` already
includes the complete widget voice UI and real-time transcript for hosts that
prefer zero native LiveKit setup.

For a standalone screen, use `ChattyVoiceScreen(botId: "…")`; it loads the
same official LiveKit UI in voice-only mode.
