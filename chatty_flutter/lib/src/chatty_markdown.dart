import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fm;
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Real CommonMark + GFM (tables, strikethrough) rendering for chat replies,
/// plus LaTeX equation support ($inline$ / $$block$$) — matches web's
/// react-markdown + remark-gfm + remark-math/rehype-katex feature set (minus
/// syntax highlighting, which web's own CodeBlock doesn't do either — see
/// chatty/packages/chatty-react/src/ChatWidgetCore.tsx). Mirrors
/// chatty-android-sdk's ChattyMarkdown.kt (commonmark-java + jlatexmath ->
/// package:markdown + flutter_math_fork here).

class ChattyMathSpan {
  final String latex;
  final bool isBlock;
  const ChattyMathSpan(this.latex, this.isBlock);
}

typedef _MathSpan = ChattyMathSpan;

// Alnum-only placeholders (no markdown-special characters) so LaTeX's own
// backslashes/underscores/asterisks/dollar signs never get misread as
// markdown syntax by the parser below — the same reason remark-math is its
// own pre-parse pass on web rather than a generic inline token.
const String _mathPrefix = 'ChattyMathSpanZ';
final RegExp _blockMathRe = RegExp(r'\$\$([\s\S]+?)\$\$');
final RegExp _inlineMathRe = RegExp(r'(?<!\$)\$(?!\$)([^$\n]+?)(?<!\$)\$(?!\$)');
final RegExp _mathPlaceholderRe = RegExp('$_mathPrefix(\\d+)Z');

(String, List<ChattyMathSpan>) chattyExtractMath(String raw) {
  final spans = <ChattyMathSpan>[];
  var text = raw.replaceAllMapped(_blockMathRe, (m) {
    final idx = spans.length;
    spans.add(ChattyMathSpan(m.group(1)!.trim(), true));
    return '$_mathPrefix${idx}Z';
  });
  text = text.replaceAllMapped(_inlineMathRe, (m) {
    final idx = spans.length;
    spans.add(ChattyMathSpan(m.group(1)!.trim(), false));
    return '$_mathPrefix${idx}Z';
  });
  return (text, spans);
}

(String, List<_MathSpan>) _extractMath(String raw) => chattyExtractMath(raw);

final md.Document _parser = md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  encodeHtml: false,
);

class ChattyMarkdown extends StatelessWidget {
  final String text;
  final Color color;
  final double fontSize;

  const ChattyMarkdown(this.text, {super.key, required this.color, this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    final (withPlaceholders, mathSpans) = _extractMath(text);
    final nodes = _parser.parse(withPlaceholders);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final node in nodes) _block(node, mathSpans, color, fontSize),
      ],
    );
  }
}

Widget _block(md.Node node, List<_MathSpan> mathSpans, Color color, double fontSize) {
  if (node is! md.Element) {
    return _inlineText(node, mathSpans, color, fontSize);
  }
  final children = node.children ?? const <md.Node>[];
  switch (node.tag) {
    case 'p':
      // A paragraph that's ONLY a block-math placeholder (the common case for
      // a lone $$...$$ on its own line) renders as the actual equation, not
      // inline text.
      if (children.length == 1 && children.first is md.Text) {
        final literal = (children.first as md.Text).text.trim();
        final m = _mathPlaceholderRe.matchAsPrefix(literal);
        if (m != null && m.end == literal.length) {
          final idx = int.tryParse(m.group(1)!);
          final span = idx != null && idx < mathSpans.length ? mathSpans[idx] : null;
          if (span != null && span.isBlock) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: fm.Math.tex(
                span.latex,
                mathStyle: fm.MathStyle.display,
                textStyle: TextStyle(fontSize: fontSize, color: color),
                onErrorFallback: (e) => Text('\$\$${span.latex}\$\$',
                    style: TextStyle(fontSize: fontSize, color: color, fontFamily: 'monospace')),
              ),
            );
          }
        }
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _InlineRich(children, mathSpans, color, fontSize),
      );
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      final scale = switch (node.tag) { 'h1' => 1.4, 'h2' => 1.3, 'h3' => 1.15, _ => 1.05 };
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _InlineRich(children, mathSpans, color, fontSize * scale, bold: true),
      );
    case 'ul':
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final li in children.whereType<md.Element>())
            _listItemRow('•', li, mathSpans, color, fontSize),
        ],
      );
    case 'ol':
      var n = int.tryParse(node.attributes['start'] ?? '1') ?? 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final li in children.whereType<md.Element>())
            _listItemRow('${n++}.', li, mathSpans, color, fontSize),
        ],
      );
    case 'blockquote':
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: color.withValues(alpha: 0.25)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in children) _block(c, mathSpans, color.withValues(alpha: 0.75), fontSize),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    case 'pre':
      final codeEl = children.whereType<md.Element>().firstOrNull;
      final lang = (codeEl?.attributes['class'] ?? '').replaceFirst('language-', '');
      final code = (codeEl?.textContent ?? node.textContent).replaceAll(RegExp(r'\n$'), '');
      return _CodeBlock(lang: lang, code: code, fontSize: fontSize);
    case 'table':
      return _MarkdownTable(node, mathSpans, color, fontSize);
    case 'hr':
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        height: 1,
        color: color.withValues(alpha: 0.15),
      );
    default:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [for (final c in children) _block(c, mathSpans, color, fontSize)],
      );
  }
}

Widget _listItemRow(String marker, md.Element item, List<_MathSpan> mathSpans, Color color, double fontSize) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(marker, style: TextStyle(color: color, fontSize: fontSize)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [for (final c in item.children ?? const []) _block(c, mathSpans, color, fontSize)],
          ),
        ),
      ],
    ),
  );
}

Widget _inlineText(md.Node node, List<_MathSpan> mathSpans, Color color, double fontSize) {
  return _InlineRich([node], mathSpans, color, fontSize);
}

class _MarkdownTable extends StatelessWidget {
  final md.Element table;
  final List<_MathSpan> mathSpans;
  final Color color;
  final double fontSize;
  const _MarkdownTable(this.table, this.mathSpans, this.color, this.fontSize);

  @override
  Widget build(BuildContext context) {
    final borderColor = color.withValues(alpha: 0.2);
    final rows = <TableRow>[];
    for (final section in table.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      final isHead = section.tag == 'thead';
      for (final tr in (section.children ?? const <md.Node>[]).whereType<md.Element>()) {
        rows.add(TableRow(
          children: [
            for (final cell in (tr.children ?? const <md.Node>[]).whereType<md.Element>())
              TableCell(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: _InlineRich(cell.children ?? const [], mathSpans, color, fontSize, bold: isHead),
                ),
              ),
          ],
        ));
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Table(
        border: TableBorder.all(color: borderColor, width: 0.5, borderRadius: BorderRadius.circular(6)),
        children: rows,
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String lang;
  final String code;
  final double fontSize;
  const _CodeBlock({required this.lang, required this.code, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: const Color(0x33000000))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                color: const Color(0x14000000),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        lang.isEmpty ? 'code' : lang,
                        style: const TextStyle(color: Color(0xFF6B7280), fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                    InkWell(
                      onTap: () => Clipboard.setData(ClipboardData(text: code)),
                      child: const Icon(Icons.copy, size: 14, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                child: Text(
                  code,
                  style: TextStyle(color: const Color(0xFF111827), fontFamily: 'monospace', fontSize: fontSize * 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline-level rendering for a list of markdown inline nodes — bold/italic/
/// code/strikethrough/links/math, flowing as real text via [WidgetSpan] for
/// math (auto-sized by RichText's own layout, no manual measuring needed —
/// simpler than the Compose InlineTextContent approach this mirrors).
class _InlineRich extends StatelessWidget {
  final List<md.Node> nodes;
  final List<_MathSpan> mathSpans;
  final Color color;
  final double fontSize;
  final bool bold;

  const _InlineRich(this.nodes, this.mathSpans, this.color, this.fontSize, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return RichText(
      text: TextSpan(style: baseStyle, children: _spans(nodes, baseStyle, context)),
    );
  }

  List<InlineSpan> _spans(List<md.Node> nodes, TextStyle style, BuildContext context) {
    final result = <InlineSpan>[];
    for (final n in nodes) {
      if (n is md.Text) {
        result.addAll(_textWithMath(n.text, style));
      } else if (n is md.Element) {
        switch (n.tag) {
          case 'em':
            result.add(TextSpan(
              style: style.copyWith(fontStyle: FontStyle.italic),
              children: _spans(n.children ?? const [], style.copyWith(fontStyle: FontStyle.italic), context),
            ));
          case 'strong':
            result.add(TextSpan(
              style: style.copyWith(fontWeight: FontWeight.bold),
              children: _spans(n.children ?? const [], style.copyWith(fontWeight: FontWeight.bold), context),
            ));
          case 'del':
            result.add(TextSpan(
              style: style.copyWith(decoration: TextDecoration.lineThrough),
              children: _spans(n.children ?? const [], style.copyWith(decoration: TextDecoration.lineThrough), context),
            ));
          case 'code':
            result.add(TextSpan(
              text: n.textContent,
              style: style.copyWith(
                fontFamily: 'monospace',
                backgroundColor: color.withValues(alpha: 0.1),
              ),
            ));
          case 'a':
            final href = n.attributes['href'] ?? '';
            final linkStyle = style.copyWith(color: const Color(0xFF2563EB), decoration: TextDecoration.underline);
            result.add(TextSpan(
              style: linkStyle,
              children: _spans(n.children ?? const [], linkStyle, context),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  final uri = Uri.tryParse(href);
                  if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
            ));
          case 'br':
            result.add(const TextSpan(text: '\n'));
          default:
            result.addAll(_spans(n.children ?? const [], style, context));
        }
      }
    }
    return result;
  }

  List<InlineSpan> _textWithMath(String literal, TextStyle style) {
    final result = <InlineSpan>[];
    var last = 0;
    for (final m in _mathPlaceholderRe.allMatches(literal)) {
      if (m.start > last) result.add(TextSpan(text: literal.substring(last, m.start), style: style));
      final idx = int.tryParse(m.group(1)!);
      final span = idx != null && idx < mathSpans.length ? mathSpans[idx] : null;
      if (span != null) {
        result.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: fm.Math.tex(
            span.latex,
            mathStyle: fm.MathStyle.text,
            textStyle: style,
            onErrorFallback: (e) =>
                Text('\$${span.latex}\$', style: style.copyWith(fontFamily: 'monospace')),
          ),
        ));
      } else {
        result.add(TextSpan(text: m.group(0), style: style)); // shouldn't happen, but never silently drop text
      }
      last = m.end;
    }
    if (last < literal.length) result.add(TextSpan(text: literal.substring(last), style: style));
    return result;
  }
}

extension _FirstOrNullElement<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
