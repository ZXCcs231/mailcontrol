import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

const _skipTags = <String>{
  'script',
  'style',
  'noscript',
  'title',
  'textarea',
  'code',
  'pre',
  'svg',
  'math',
};

final _urlOnlyRe = RegExp(r'^https?://\S+$', caseSensitive: false);
final _emailOnlyRe = RegExp(r'^[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}$');
final _letterRe = RegExp(r'[A-Za-z\u00C0-\u024F\u0400-\u04FF\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]');
final _leadSpaceRe = RegExp(r'^\s+');
final _trailSpaceRe = RegExp(r'\s+$');
final _lineBreakRe = RegExp(r'[\r\n\t]+');
final _multiSpaceRe = RegExp(r' {2,}');

class _TextSlot {
  final dom.Text node;
  final String lead;
  final String core;
  final String trail;

  _TextSlot(this.node, this.lead, this.core, this.trail);
}

/// 保留原始 HTML DOM 排版结构，原地将文本节点替换为译文（用作旧版后端兜底）。
Future<String> translateHtmlInPlace({
  required String rawHtml,
  required Future<String> Function(String text) translateBatch,
}) async {
  if (rawHtml.trim().isEmpty) return rawHtml;

  final doc = html_parser.parse(rawHtml);
  final body = doc.body;
  if (body == null) return rawHtml;

  final slots = <_TextSlot>[];
  final uniqueTexts = <String>[];
  final uniqueSet = <String>{};

  void walk(dom.Node node, bool skip) {
    var nextSkip = skip;
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase() ?? '';
      if (_skipTags.contains(tag)) {
        nextSkip = true;
      }
    }
    if (!nextSkip && node is dom.Text) {
      final raw = node.text;
      if (raw.trim().isEmpty) return;
      final lead = _leadSpaceRe.stringMatch(raw) ?? '';
      final rest = raw.substring(lead.length);
      final trail = _trailSpaceRe.stringMatch(rest) ?? '';
      final middle = rest.substring(0, rest.length - trail.length);
      final core = _collapseInline(middle);
      if (_shouldTranslate(core)) {
        slots.add(_TextSlot(node, lead, core, trail));
        if (uniqueSet.add(core)) {
          uniqueTexts.add(core);
        }
      }
    }
    for (final child in node.nodes) {
      walk(child, nextSkip);
    }
  }

  walk(body, false);
  if (uniqueTexts.isEmpty) return rawHtml;

  final translations = <String, String>{};
  const maxBatchChars = 1100;
  var batch = <String>[];
  var batchLen = 0;

  Future<void> flush() async {
    if (batch.isEmpty) return;
    await _translateAligned(batch, translateBatch, translations);
    batch = <String>[];
    batchLen = 0;
  }

  for (final item in uniqueTexts) {
    if (batch.isNotEmpty && batchLen + 1 + item.length > maxBatchChars) {
      await flush();
    }
    batch.add(item);
    batchLen += item.length + 1;
  }
  await flush();

  for (final s in slots) {
    final tr = translations[s.core];
    if (tr != null && tr.trim().isNotEmpty) {
      s.node.text = '${s.lead}$tr${s.trail}';
    }
  }

  return body.innerHtml;
}

Future<void> _translateAligned(
  List<String> items,
  Future<String> Function(String text) translateBatch,
  Map<String, String> outMap,
) async {
  if (items.isEmpty) return;
  if (items.length == 1) {
    final res = await translateBatch(items.first);
    outMap[items.first] = _collapseInline(res);
    return;
  }

  final out = await translateBatch(items.join('\n'));
  final lines = out.replaceAll('\r\n', '\n').split('\n');
  if (lines.length == items.length) {
    for (var i = 0; i < items.length; i++) {
      outMap[items[i]] = lines[i].trim();
    }
    return;
  }

  final mid = items.length ~/ 2;
  await _translateAligned(items.sublist(0, mid), translateBatch, outMap);
  await _translateAligned(items.sublist(mid), translateBatch, outMap);
}

String _collapseInline(String s) {
  return s.replaceAll(_lineBreakRe, ' ').replaceAll(_multiSpaceRe, ' ').trim();
}

bool _shouldTranslate(String core) {
  if (core.isEmpty) return false;
  if (_urlOnlyRe.hasMatch(core) || _emailOnlyRe.hasMatch(core)) return false;
  return _letterRe.hasMatch(core);
}
