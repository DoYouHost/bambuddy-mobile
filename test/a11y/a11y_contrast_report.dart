import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Where [reportContrastFindings] appends, one JSON object per finding. Unset,
/// nothing is written. `flutter test --dart-define=A11Y_CONTRAST_REPORT=/tmp/x.jsonl …`
const _path = String.fromEnvironment('A11Y_CONTRAST_REPORT');

/// What the widget's own colors say about one finding of
/// `MinimumTextContrastGuideline`.
///
/// The guideline never reads the color of the text: it takes the commonest
/// light and the commonest dark pixel color in the node's box (flutter_test
/// accessibility.dart, "a very naive partitioning"), at one pixel per dp. On
/// 11-14 dp semi-transparent text most glyph pixels are blends, so it fails
/// text that reads fine. This reads the color from the paragraph instead.
enum ContrastVerdict {
  /// Every paragraph in the node passes with its own colors: the guideline's
  /// failure is its measurement, not the text.
  artefact,

  /// A paragraph fails with its own colors too.
  genuine,

  /// No paragraph or no ground could be found: the guideline's finding stands.
  inconclusive,
}

class ContrastJudgment {
  const ContrastJudgment(this.verdict, this.detail);
  final ContrastVerdict verdict;
  final Map<String, Object?> detail;
}

final _nodeId = RegExp(r'SemanticsNode#(\d+)\(');
final _measured = RegExp(
  r'but found (\d+(?:\.\d+)?) for a font size of (\d+(?:\.\d+)?)',
);

/// A verdict per finding, keyed like [findings]. A paragraph counts for a node
/// when its text is part of the node's label, value or hint and it lies inside
/// the node's bounds (the framework's own transforms).
Future<Map<String, ContrastJudgment>> judgeContrastFindings(
  WidgetTester tester,
  Map<String, String> findings,
) async {
  const none = ContrastJudgment(ContrastVerdict.inconclusive, {});
  if (findings.isEmpty) return {};
  final renderView = tester.binding.renderViews.first;
  // The image below is one pixel per dp, like the guideline's own; coordinates
  // are only the same at a device pixel ratio of 1, which the a11y window has.
  if (renderView.flutterView.devicePixelRatio != 1) {
    return {for (final k in findings.keys) k: none};
  }

  // A Text paints through a RenderParagraph, a text field through a
  // RenderEditable; both hold the span they draw.
  final paragraphs = <RenderBox>[];
  void collect(RenderObject o) {
    if (o is RenderParagraph || o is RenderEditable) {
      paragraphs.add(o as RenderBox);
    }
    o.visitChildren(collect);
  }

  collect(renderView);

  final nodes = <int, SemanticsNode>{};
  void walk(SemanticsNode n) {
    nodes[n.id] = n;
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  if (renderView.owner?.semanticsOwner?.rootSemanticsNode case final r?) {
    walk(r);
  }

  final rootTransform = Matrix4.identity();
  renderView.applyPaintTransform(renderView.child!, rootTransform);

  final root = tester.element(find.byType(MaterialApp).first);
  final image = await tester.runAsync(() => captureImage(root));
  final bytes = image == null
      ? null
      : await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
        );

  final out = <String, ContrastJudgment>{};
  for (final MapEntry(:key, value: finding) in findings.entries) {
    final measured = _measured.firstMatch(finding);
    final id = int.tryParse(_nodeId.firstMatch(finding)?.group(1) ?? '');
    final node = id == null ? null : nodes[id];
    if (measured == null || node == null || image == null || bytes == null) {
      out[key] = none;
      continue;
    }
    final reportedSize = double.parse(measured.group(2)!);
    final data = node.getSemanticsData();
    final text = '${data.label}\n${data.value}\n${data.hint}';

    var nodeBounds = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      final t = n.transform;
      if (t != null) nodeBounds = MatrixUtils.transformRect(t, nodeBounds);
    }

    var failing = 0, passing = 0, unknown = 0;
    Map<String, Object?>? worstDetail;
    double? worstReal;
    for (final p in paragraphs) {
      final span = p is RenderParagraph ? p.text : (p as RenderEditable).text;
      if (span == null) continue;
      final plain = span.toPlainText().replaceAll('\uFFFC', '');
      if (plain.isEmpty || !text.contains(plain)) continue;
      final rootStyle = span is TextSpan ? span.style : null;
      // The size the guideline reports is the Text's own effective size.
      if (((rootStyle?.fontSize ?? 12) - reportedSize).abs() > 0.6) continue;
      final box = MatrixUtils.transformRect(
        rootTransform.clone()..multiply(p.getTransformTo(null)),
        p.paintBounds,
      );
      final inside = nodeBounds.intersect(box);
      if (inside.width <= 0 || inside.height <= 0) continue;

      final opacity = _ancestorOpacity(p);
      final spans = _leafStyles(span);
      final colors = [
        for (final s in spans)
          if (_color(s) case final c?) c.withValues(alpha: c.a * opacity),
      ];
      final grounds = _grounds(bytes, image.width, image.height, box, colors);
      if (colors.isEmpty || grounds.isEmpty) {
        unknown++;
        continue;
      }
      var real = double.infinity;
      String? worstFg;
      for (final fg in colors) {
        for (final g in grounds) {
          final c = _contrast(Color.alphaBlend(fg, g), g);
          if (c < real) {
            real = c;
            worstFg = _hex(fg);
          }
        }
      }
      final need = _need(rootStyle);
      if (real < need) {
        failing++;
      } else {
        passing++;
      }
      if (worstReal == null || real < worstReal) {
        worstReal = real;
        final context = (p.debugCreator as DebugCreator?)?.element;
        final tokens = context == null
            ? null
            : Theme.of(context).extension<DashTokens>();
        final token = tokens == null
            ? null
            : _tokenName(tokens, spans.first.color ?? const Color(0x00000000));
        worstDetail = {
          'text': plain.length > 40 ? plain.substring(0, 40) : plain,
          'size': reportedSize,
          'fg': worstFg,
          'grounds': [for (final g in grounds) _hex(g)],
          'real': double.parse(real.toStringAsFixed(2)),
          'need': need,
          'token': token,
          'opacity': opacity == 1 ? null : opacity,
          'width': box.width.round(),
          'chain': context
              ?.debugGetCreatorChain(8)
              .replaceAll(RegExp(r'\s+'), ' '),
        };
      }
    }
    final verdict = failing > 0
        ? ContrastVerdict.genuine
        : (passing > 0 && unknown == 0
              ? ContrastVerdict.artefact
              : ContrastVerdict.inconclusive);
    out[key] = ContrastJudgment(verdict, {
      'paragraphs': failing + passing + unknown,
      'guideline': double.parse(measured.group(1)!),
      ...?worstDetail,
    });
  }
  return out;
}

/// Writes the judgments as JSON lines when `A11Y_CONTRAST_REPORT` is set.
void reportContrastFindings(Map<String, ContrastJudgment> judgments) {
  if (_path.isEmpty || judgments.isEmpty) return;
  final out = StringBuffer();
  for (final MapEntry(:key, :value) in judgments.entries) {
    out.writeln(
      jsonEncode({'verdict': value.verdict.name, ...value.detail, 'key': key}),
    );
  }
  File(_path).writeAsStringSync(out.toString(), mode: FileMode.append);
}

/// 3:1 for large text (18, or 14 bold), 4.5:1 otherwise: the framework's own
/// constants (`MinimumTextContrastGuideline.targetContrastRatio`), so a verdict
/// here is about the same bar as the finding.
double _need(TextStyle? style) {
  final size = style?.fontSize ?? 12;
  final bold = style?.fontWeight == FontWeight.bold;
  return (bold && size >= 14) || size >= 18 ? 3.0 : 4.5;
}

Color? _color(TextStyle s) => s.color ?? s.foreground?.color;

/// The product of the opacities between [p] and the root.
double _ancestorOpacity(RenderObject p) {
  var opacity = 1.0;
  for (RenderObject? o = p.parent; o != null; o = o.parent) {
    if (o is RenderOpacity) opacity *= o.opacity;
    if (o is RenderAnimatedOpacity) opacity *= o.opacity.value;
  }
  return opacity;
}

/// The effective style of every span that carries text, parents merged in.
List<TextStyle> _leafStyles(InlineSpan root) {
  final out = <TextStyle>[];
  void visit(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final style = inherited == null ? span.style : inherited.merge(span.style);
    if ((span.text ?? '').isNotEmpty && style != null) out.add(style);
    for (final c in span.children ?? const <InlineSpan>[]) {
      visit(c, style);
    }
  }

  visit(root, null);
  return out;
}

String _hex(Color c) {
  String two(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}'
      '${c.a < 1 ? '@${(c.a * 100).round()}' : ''}';
}

String? _tokenName(DashTokens t, Color c) {
  final named = <String, Color>{
    'textPrimary': t.textPrimary,
    'textSecondary': t.textSecondary,
    'textTertiary': t.textTertiary,
    'accentGreen': t.accentGreen,
    'accentGreenInk': t.accentGreenInk,
    'accentOrange': t.accentOrange,
    'accentOrangeInk': t.accentOrangeInk,
    'accentBlue': t.accentBlue,
    'danger': t.danger,
    'dangerInk': t.dangerInk,
    'warning': t.warning,
    'warningInk': t.warningInk,
    'onDanger': t.onDanger,
  };
  for (final e in named.entries) {
    if (e.value == c) return e.key;
  }
  return null;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The ground behind a paragraph: the commonest colors inside its box that are
/// not the text itself (a span's color, or that color blended over the first
/// ground, within a small distance), and a second one when it is a large share
/// (30%) and visibly different (a half painted bar): the text has to read on
/// both. The interior, not a ring around it: a badge or a pill is padded by less
/// than the ring is wide, and the ring would be the page outside it. A box that
/// is all text colors falls back to the ring.
List<Color> _grounds(ByteData data, int w, int h, Rect box, List<Color> text) {
  bool near(Color a, Color b) =>
      ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255 < 36;

  List<Color> pickGrounds(Map<int, int> counts, List<Color> glyphs) {
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final glyph = [...glyphs];
    final out = <Color>[];
    for (final e in ranked) {
      final c = Color(0xFF000000 | e.key);
      if (glyph.any((g) => near(g, c))) continue;
      if (out.isEmpty) {
        out.add(c);
        // Semi-transparent text paints its blend over the ground.
        glyph.addAll([for (final g in glyphs) Color.alphaBlend(g, c)]);
      } else if (e.value >= total * 0.3 && _contrast(c, out.first) >= 1.15) {
        out.add(c);
        break;
      }
      if (out.length == 2) break;
    }
    return out;
  }

  Map<int, int> histogram(Rect area, Rect? hole) {
    final counts = <int, int>{};
    final l = area.left.floor().clamp(0, w);
    final r = area.right.ceil().clamp(0, w);
    final t = area.top.floor().clamp(0, h);
    final b = area.bottom.ceil().clamp(0, h);
    for (var y = t; y < b; y++) {
      for (var x = l; x < r; x++) {
        if (hole != null && hole.contains(Offset(x + 0.5, y + 0.5))) continue;
        final o = (y * w + x) * 4;
        final v =
            (data.getUint8(o) << 16) |
            (data.getUint8(o + 1) << 8) |
            data.getUint8(o + 2);
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    return counts;
  }

  final inner = histogram(box, null);
  if (inner.isNotEmpty) {
    final grounds = pickGrounds(inner, text);
    if (grounds.isNotEmpty) return grounds;
  }
  final ring = histogram(box.inflate(4), box);
  return ring.isEmpty ? const [] : pickGrounds(ring, const []);
}
