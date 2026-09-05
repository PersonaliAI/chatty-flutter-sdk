import 'package:chatty_flutter_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Intro screen renders with the full-screen chat button', (WidgetTester tester) async {
    await tester.pumpWidget(const ChattyExampleApp());
    // ChattyLauncher's theme fetch has no real network in a widget test — it
    // stays on its fallback state, which is fine for this smoke test.
    await tester.pump();

    expect(find.text('Chatty Flutter SDK'), findsOneWidget);
    expect(find.text('Open full-screen chat'), findsOneWidget);
  });
}
