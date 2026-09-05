import 'package:chatty_flutter/chatty_flutter.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'local_config.dart';

void main() {
  runApp(const ChattyExampleApp());
}

class ChattyExampleApp extends StatelessWidget {
  const ChattyExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chatty Flutter SDK',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  bool _showFullScreen = false;

  // The SDK itself never calls the OS permission dialog — it only reflects
  // whatever this app has already been granted, hiding the mic/notification-
  // bell/location UI when not granted. Each permission is requested
  // contextually below, right when the visitor actually reaches for that
  // feature (tapping the bell / mic / location option) — not all upfront at
  // launch, which is poor UX and also means a user who denies once during a
  // meaningless cold-start prompt can never be re-asked in context.
  void _onRequestNotificationPermission(String? botName) {
    Permission.notification.request();
  }

  void _onMicPermissionNeeded() {
    Permission.microphone.request();
  }

  void _onLocationPermissionNeeded() {
    Permission.locationWhenInUse.request();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (_showFullScreen)
              Column(
                children: [
                  AppBar(
                    title: const Text('Full-screen chat'),
                    leading: TextButton(
                      onPressed: () => setState(() => _showFullScreen = false),
                      child: const Text('← Back'),
                    ),
                  ),
                  Expanded(
                    child: ChattyEmbedScreen(
                      botId: chattyDemoBotId,
                      onRequestNotificationPermission: _onRequestNotificationPermission,
                      onMicPermissionNeeded: _onMicPermissionNeeded,
                      onLocationPermissionNeeded: _onLocationPermissionNeeded,
                    ),
                  ),
                ],
              )
            else ...[
              Container(
                color: const Color(0xFFFAFAFA),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Chatty Flutter SDK', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    const Text(
                      'This example shows both integration styles: a floating launcher '
                      '(bottom-right, tap it) and a full-screen embedded chat.',
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => setState(() => _showFullScreen = true),
                      child: const Text('Open full-screen chat'),
                    ),
                  ],
                ),
              ),
              // Floating launcher — its default color follows whatever design
              // is selected for this bot in the dashboard; no primaryColor
              // config needed here.
              ChattyLauncher(
                botId: chattyDemoBotId,
                onRequestNotificationPermission: _onRequestNotificationPermission,
                onMicPermissionNeeded: _onMicPermissionNeeded,
                onLocationPermissionNeeded: _onLocationPermissionNeeded,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
