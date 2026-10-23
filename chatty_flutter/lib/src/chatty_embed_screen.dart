import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'chatty_api.dart';
import 'chatty_design_tokens.dart';

/// Defaults to the production widget site's own host (not the `api.` API host).
const String chattyDefaultEmbedBaseUrl = 'https://chatty.personaliai.com';

/// The exact bridge protocol EmbedClient.tsx speaks to `window.parent` (read
/// from that file, not guessed). Outbound (page -> us): chatty:ready,
/// chatty:message, chatty:close, chatty-request-notification,
/// chatty-trigger-notification. Inbound (us -> page): chatty-notification-status,
/// chatty-fullscreen.
const String _bridgeShimJs = '''
(function() {
  if (window.__chattyBridgeInstalled) { return; }
  window.__chattyBridgeInstalled = true;
  // MessageEvent's constructor only accepts a Window or MessagePort for
  // `source` (not a generic EventTarget, and definitely not a plain object
  // literal) — a MessagePort from a throwaway MessageChannel is the only
  // one of those we can actually construct standalone. Its native
  // postMessage is shadowed with our own override (own-property lookup
  // beats the prototype's), so the port itself is never really used to
  // send anything, only to satisfy the type check and as a stable
  // identity for the page's own `e.source !== window.parent` filter.
  var fakeParent = new MessageChannel().port1;
  fakeParent.postMessage = function(data) {
    try { ChattyFlutterBridge.postMessage(JSON.stringify(data)); } catch (e) {}
  };
  try {
    Object.defineProperty(window, 'parent', { get: function() { return fakeParent; }, configurable: true });
  } catch (e) {}
  window.__chattyDeliver = function(json) {
    try {
      var data = JSON.parse(json);
      window.dispatchEvent(new MessageEvent('message', { data: data, source: fakeParent }));
    } catch (e) {}
  };
  // Suppress raw browser window.alert() calls (e.g. "Browser push notifications
  // are not supported on this browser" from EmbedClient.tsx)
  try {
    window.alert = function(msg) {
      try { console.log('[ChattyBridge] alert suppressed: ' + msg); } catch (e) {}
    };
  } catch (e) {}
  // Intercept getUserMedia so native host knows mic access was requested
  try {
    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
      var _origGUM = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
      navigator.mediaDevices.getUserMedia = function(constraints) {
        try { fakeParent.postMessage({ type: 'chatty:mic-requested' }); } catch (e) {}
        return _origGUM(constraints);
      };
    }
  } catch (e) {}
  // Intercept geolocation so native host knows location access was requested
  try {
    if (navigator.geolocation && navigator.geolocation.getCurrentPosition) {
      var _origGCP = navigator.geolocation.getCurrentPosition.bind(navigator.geolocation);
      navigator.geolocation.getCurrentPosition = function(success, error, options) {
        try { fakeParent.postMessage({ type: 'chatty:location-requested' }); } catch (e) {}
        return _origGCP(success, error, options);
      };
    }
  } catch (e) {}
})();
''';

/// Exposed for test assertions and verification.
const String chattyBridgeShimJs = _bridgeShimJs;

/// Loads the bot's own web widget page (the exact code chatty.personaliai.com
/// serves at /embed/[botId]) in a WebView — guaranteed pixel-for-pixel and
/// feature-for-feature parity with the web widget, since it IS the web
/// widget, not a native reimplementation of it. See ChattyChatScreen for the
/// native-components alternative (more native feel, manually kept in parity).
class ChattyEmbedScreen extends StatefulWidget {
  final String botId;
  final String baseUrl;
  final bool voiceOnly;
  final VoidCallback? onReady;
  final VoidCallback? onMessage;
  final VoidCallback? onClose;

  /// Called when the visitor taps the in-chat "enable notifications" control.
  /// This SDK never requests POST_NOTIFICATIONS itself — see
  /// ChattyChatScreen's own notification-bell doc comment for the same
  /// "reflect, never request" contract. Request the permission yourself
  /// here; the granted state is then reflected back into the page
  /// automatically.
  final void Function(String? botName)? onRequestNotificationPermission;

  /// Called when the page attempts to use the composer's mic (getUserMedia)
  /// and this app hasn't granted RECORD_AUDIO yet. The WebView itself is only
  /// ever told to deny that specific attempt — same "reflect, never request"
  /// contract as notifications above. Request the permission yourself here
  /// (e.g. `Permission.microphone.request()`); once granted, the visitor's
  /// next mic tap succeeds without any extra plumbing.
  final VoidCallback? onMicPermissionNeeded;

  /// Same contract as [onMicPermissionNeeded], for the attach menu's
  /// "Location" option (ACCESS_COARSE_LOCATION / ACCESS_FINE_LOCATION).
  final VoidCallback? onLocationPermissionNeeded;
  final double? topInset;
  final double? bottomInset;

  const ChattyEmbedScreen({
    super.key,
    required this.botId,
    this.baseUrl = chattyDefaultEmbedBaseUrl,
    this.voiceOnly = false,
    this.topInset,
    this.bottomInset,
    this.onReady,
    this.onMessage,
    this.onClose,
    this.onRequestNotificationPermission,
    this.onMicPermissionNeeded,
    this.onLocationPermissionNeeded,
  });

  @override
  State<ChattyEmbedScreen> createState() => _ChattyEmbedScreenState();
}

class _ChattyEmbedScreenState extends State<ChattyEmbedScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  String get _embedUrl {
    final base = widget.baseUrl.replaceAll(RegExp(r"/$"), "");
    final uri = Uri.parse('$base/embed/${widget.botId}');
    final query = Map<String, String>.from(uri.queryParameters);
    query['platform'] = 'flutter';
    query['safeArea'] = 'true';
    if (widget.voiceOnly) query['voice'] = 'only';
    if (widget.topInset != null) query['topInset'] = widget.topInset!.toInt().toString();
    if (widget.bottomInset != null) query['bottomInset'] = widget.bottomInset!.toInt().toString();
    return uri.replace(queryParameters: query).toString();
  }
  late final String _embedHost = Uri.parse(_embedUrl).host;

  bool _pageReady = false;
  bool _loadError = false;
  bool _isOnline = true;
  bool _notifGranted = false;
  ChattyTheme? _theme;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTheme();
    _checkNotifPermission();
    _initConnectivity();
    _initWebView();
  }

  Future<void> _loadTheme() async {
    try {
      final t = await ChattyClient(widget.botId).getTheme();
      if (mounted) setState(() => _theme = t);
    } catch (_) {
      // Loading/offline screens fall back to the "minimal" design — the
      // embedded page itself owns all real theming regardless.
    }
  }

  Future<void> _initConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    if (mounted) setState(() => _isOnline = _isConnected(result));
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) setState(() => _isOnline = _isConnected(result));
    });
  }

  bool _isConnected(List<ConnectivityResult> result) =>
      result.isNotEmpty && !result.contains(ConnectivityResult.none);

  Future<void> _checkNotifPermission() async {
    final status = await ph.Permission.notification.status;
    if (!mounted) return;
    setState(() => _notifGranted = status.isGranted);
    if (_pageReady) _deliverToPage({'type': 'chatty-notification-status', 'granted': _notifGranted});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkNotifPermission();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _deliverSafeArea();
  }

  void _deliverSafeArea() {
    if (!_pageReady || !mounted) return;
    final padding = MediaQuery.maybePaddingOf(context);
    final top = widget.topInset ?? padding?.top ?? 0.0;
    final bottom = widget.bottomInset ?? padding?.bottom ?? 0.0;
    _deliverToPage({
      'type': 'chatty-safe-area',
      'top': top,
      'bottom': bottom,
    });
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'ChattyFlutterBridge',
        onMessageReceived: (JavaScriptMessage message) {
          Map<String, dynamic> msg;
          try {
            msg = jsonDecode(message.message) as Map<String, dynamic>;
          } catch (_) {
            return;
          }
          switch (msg['type']) {
            case 'chatty:ready':
              if (mounted) setState(() => _pageReady = true);
              _deliverToPage({'type': 'chatty-notification-status', 'granted': _notifGranted});
              _deliverSafeArea();
              widget.onReady?.call();
            case 'chatty:message':
              widget.onMessage?.call();
            case 'chatty:close':
              widget.onClose?.call();
            case 'chatty-request-notification':
              widget.onRequestNotificationPermission?.call(msg['botName'] as String?);
            case 'chatty:mic-requested':
              ph.Permission.microphone.status.then((status) {
                if (!status.isGranted) widget.onMicPermissionNeeded?.call();
              });
            case 'chatty:location-requested':
              ph.Permission.locationWhenInUse.status.then((status) {
                if (!status.isGranted) widget.onLocationPermissionNeeded?.call();
              });
            // chatty-trigger-notification: this SDK doesn't bundle a
            // local-notification dependency (matches ChattyChatScreen's own
            // scope) — watch onMessage and post your own instead.
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          // webview_flutter has no "inject before content loads" hook — unlike
          // Android's addDocumentStartJavaScript or RN-webview's
          // injectedJavaScriptBeforeContentLoaded — so the shim races the
          // page's own scripts here. In practice this wins comfortably: the
          // page's postMessage code only runs after its JS bundle finishes
          // downloading and React hydrates, both far slower than this
          // synchronous injection right as navigation starts.
          onPageStarted: (_) => _controller.runJavaScript(_bridgeShimJs),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              if (mounted) setState(() => _loadError = true);
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;
            if (uri.host == _embedHost) return NavigationDecision.navigate;
            if (uri.scheme == 'mailto' || uri.scheme == 'tel' || uri.scheme == 'sms') {
              launchUrl(uri);
              return NavigationDecision.prevent;
            }
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(_embedUrl));

    // Mic/location for the embedded page's getUserMedia()/geolocation calls —
    // Android-only hooks (webview_flutter has no cross-platform API for
    // these yet). Same reflect-only contract as the notification bell: never
    // call Permission.request() ourselves, only check already-granted status
    // and tell the WebView request to proceed or deny accordingly, firing
    // the on*PermissionNeeded callback so the host app can prompt in
    // context (right as the visitor reaches for that feature).
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setTextZoom(100);
      platform.setOnPlatformPermissionRequest((request) async {
        final wantsMic = request.types.contains(WebViewPermissionResourceType.microphone);
        final micGranted = wantsMic && await ph.Permission.microphone.status.isGranted;
        if (wantsMic && !micGranted) widget.onMicPermissionNeeded?.call();
        if (micGranted) {
          await request.grant();
        } else {
          await request.deny();
        }
      });
      platform.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (params) async {
          final granted = await ph.Permission.locationWhenInUse.status.isGranted;
          if (!granted) widget.onLocationPermissionNeeded?.call();
          return GeolocationPermissionsResponse(allow: granted, retain: false);
        },
      );
    }
  }

  void _deliverToPage(Map<String, dynamic> payload) {
    final json = jsonEncode(jsonEncode(payload));
    _controller.runJavaScript('window.__chattyDeliver && window.__chattyDeliver($json);');
  }

  void _retry() {
    setState(() {
      _loadError = false;
      _pageReady = false;
    });
    _controller.reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final designId = chattyNormalizeWidgetStyle(_theme?.widgetStyle);
    final t = chattyDesignTokens[designId] ?? chattyDesignTokens['minimal']!;

    if (!_isOnline) {
      return _OfflineOrErrorView(
        title: "You're offline",
        body: 'Check your connection and try again.',
        bg: t.containerBg,
        fg: t.headerText,
        onRetry: _retry,
      );
    }
    if (_loadError) {
      return _OfflineOrErrorView(title: "Couldn't load chat", body: null, bg: t.containerBg, fg: t.headerText, onRetry: _retry);
    }

    return Container(
      color: t.containerBg,
      child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (!_pageReady)
            Positioned.fill(
              child: Container(
                color: t.containerBg,
                child: Center(child: CircularProgressIndicator(color: t.userBubbleBg)),
              ),
            ),
        ],
      ),
    );
  }
}

class _OfflineOrErrorView extends StatelessWidget {
  final String title;
  final String? body;
  final Color bg;
  final Color fg;
  final VoidCallback onRetry;

  const _OfflineOrErrorView({required this.title, required this.body, required this.bg, required this.fg, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w700)),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 14), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Standalone LiveKit voice-agent surface using the official Chatty web UI.
class ChattyVoiceScreen extends StatelessWidget {
  final String botId;
  final String baseUrl;
  final VoidCallback? onReady;
  final VoidCallback? onMessage;
  final VoidCallback? onClose;

  const ChattyVoiceScreen({
    super.key,
    required this.botId,
    this.baseUrl = chattyDefaultEmbedBaseUrl,
    this.onReady,
    this.onMessage,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) => ChattyEmbedScreen(
        botId: botId,
        baseUrl: baseUrl,
        voiceOnly: true,
        onReady: onReady,
        onMessage: onMessage,
        onClose: onClose,
      );
}
