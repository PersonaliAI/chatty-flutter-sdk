import 'dart:convert';

import 'package:chatty_flutter/chatty_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chatty Theming & Design Tokens', () {
    test('chattyNormalizeWidgetStyle resolves legacy style ids to a current design key', () {
      expect(chattyNormalizeWidgetStyle('minimal:#fff:bubble'), 'minimal');
      expect(chattyNormalizeWidgetStyle('liquid'), 'glassmorphism'); // LEGACY_STYLE_MAP
      expect(chattyNormalizeWidgetStyle(null), 'minimal');
      expect(chattyNormalizeWidgetStyle('unknown-style-id'), 'minimal');
    });

    test('every design key has a matching ChattyDesignTokens entry', () {
      for (final key in chattyDesignTokens.keys) {
        expect(chattyDesignTokens[key], isNotNull);
        final t = chattyDesignTokens[key]!;
        expect(t.userBubbleBg, isNotNull);
        expect(t.botBubbleBg, isNotNull);
      }
    });
  });

  group('ChattyMarkdown - LaTeX Math Extraction', () {
    test('extracts inline math equations into placeholders', () {
      const raw = 'The speed of light is related by \$E = mc^2\$ in physics.';
      final (text, spans) = chattyExtractMath(raw);

      expect(spans.length, 1);
      expect(spans[0].latex, 'E = mc^2');
      expect(spans[0].isBlock, false);
      expect(text, contains('ChattyMathSpanZ0Z'));
    });

    test('extracts block math equations into placeholders', () {
      const raw = 'The formula is:\n\$\$\nx = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\n\$\$';
      final (text, spans) = chattyExtractMath(raw);

      expect(spans.length, 1);
      expect(spans[0].latex, 'x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}');
      expect(spans[0].isBlock, true);
      expect(text, contains('ChattyMathSpanZ0Z'));
    });

    test('extracts multiple mixed inline and block equations preserving order', () {
      const raw = 'Inline \$a^2 + b^2 = c^2\$ and block:\n\$\$\\sum_{i=1}^n i = \\frac{n(n+1)}{2}\$\$\nand \$x_i \\ge 0\$.';
      final (text, spans) = chattyExtractMath(raw);

      expect(spans.length, 3);
      expect(spans[0].isBlock, true);
      expect(spans[0].latex, contains('\\sum_{i=1}^n'));
      expect(spans[1].isBlock, false);
      expect(spans[1].latex, 'a^2 + b^2 = c^2');
      expect(spans[2].isBlock, false);
      expect(spans[2].latex, 'x_i \\ge 0');

      expect(text, contains('ChattyMathSpanZ0Z'));
      expect(text, contains('ChattyMathSpanZ1Z'));
      expect(text, contains('ChattyMathSpanZ2Z'));
    });

    test('preserves LaTeX formatting characters without markdown syntax collisions', () {
      const raw = 'Subscripts \$a_1, a_2\$ and asterisks \$A * B\$ and carets \$x^2\$.';
      final (text, spans) = chattyExtractMath(raw);

      expect(spans.length, 3);
      expect(text, isNot(contains('a_1')));
      expect(text, isNot(contains('A * B')));
      expect(text, isNot(contains('x^2')));
    });
  });

  group('ChattyMarkdown - Widget Rendering', () {
    testWidgets('renders markdown text formatting correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChattyMarkdown(
              '# Heading 1\n\nThis is **bold**, *italic*, and `inline code`.\n\n- Item 1\n- Item 2\n\n> A quote',
              color: Colors.black,
            ),
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsWidgets);

      bool hasRichTextContaining(String pattern) {
        return find.byWidgetPredicate((widget) {
          if (widget is RichText) {
            return widget.text.toPlainText().contains(pattern);
          }
          return false;
        }).evaluate().isNotEmpty;
      }

      expect(hasRichTextContaining('Heading 1'), isTrue);
      expect(hasRichTextContaining('bold'), isTrue);
      expect(hasRichTextContaining('Item 1'), isTrue);
      expect(hasRichTextContaining('Item 2'), isTrue);
    });

    testWidgets('renders tables and block math equations', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChattyMarkdown(
              '| Header A | Header B |\n| --- | --- |\n| Cell 1 | Cell 2 |\n\n\$\$E = mc^2\$\$',
              color: Colors.black,
            ),
          ),
        ),
      );

      expect(find.byType(Table), findsOneWidget);

      bool hasRichTextContaining(String pattern) {
        return find.byWidgetPredicate((widget) {
          if (widget is RichText) {
            return widget.text.toPlainText().contains(pattern);
          }
          return false;
        }).evaluate().isNotEmpty;
      }

      expect(hasRichTextContaining('Header A'), isTrue);
      expect(hasRichTextContaining('Cell 1'), isTrue);
    });
  });

  group('ChattyEmbedScreen - Bridge Protocol & Permissions', () {
    test('bridge shim JS contains fakeParent window.parent override', () {
      expect(chattyBridgeShimJs, contains('window.__chattyBridgeInstalled'));
      expect(chattyBridgeShimJs, contains('var fakeParent = new MessageChannel().port1;'));
      expect(chattyBridgeShimJs, contains('ChattyFlutterBridge.postMessage(JSON.stringify(data))'));
      expect(chattyBridgeShimJs, contains("Object.defineProperty(window, 'parent'"));
      expect(chattyBridgeShimJs, contains('window.__chattyDeliver'));
    });

    test('bridge shim JS suppresses raw browser alert dialogs', () {
      expect(chattyBridgeShimJs, contains('window.alert = function(msg)'));
      expect(chattyBridgeShimJs, contains('[ChattyBridge] alert suppressed'));
    });

    test('bridge shim JS intercepts getUserMedia for microphone permission reflection', () {
      expect(chattyBridgeShimJs, contains('navigator.mediaDevices.getUserMedia'));
      expect(chattyBridgeShimJs, contains("type: 'chatty:mic-requested'"));
    });

    test('bridge shim JS intercepts geolocation for location permission reflection', () {
      expect(chattyBridgeShimJs, contains('navigator.geolocation.getCurrentPosition'));
      expect(chattyBridgeShimJs, contains("type: 'chatty:location-requested'"));
    });

    test('notification status delivery JSON payload is correctly serialized for evaluateJavascript', () {
      final payload = {'type': 'chatty-notification-status', 'granted': true};
      final json = jsonEncode(jsonEncode(payload));
      final script = 'window.__chattyDeliver && window.__chattyDeliver($json);';

      expect(script, contains('chatty-notification-status'));
      expect(script, contains('granted'));
      expect(script, contains('true'));
    });

    test('handles valid outbound bridge messages correctly', () {
      final validMessages = [
        {'type': 'chatty:ready'},
        {'type': 'chatty:message', 'role': 'assistant'},
        {'type': 'chatty:close'},
        {'type': 'chatty-request-notification', 'botName': 'ChattyBot'},
        {'type': 'chatty:mic-requested'},
        {'type': 'chatty:location-requested'},
      ];

      for (final msg in validMessages) {
        final encoded = jsonEncode(msg);
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;
        expect(decoded['type'], msg['type']);
      }
    });
  });
}
