import 'dart:math' as math;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

const _safeBlockStyleProps = <String>{
  'background',
  'background-color',
  'border',
  'border-top',
  'border-right',
  'border-bottom',
  'border-left',
  'border-style',
  'border-width',
  'border-color',
  'border-radius',
  'padding',
  'padding-top',
  'padding-right',
  'padding-bottom',
  'padding-left',
  'margin',
  'margin-top',
  'margin-right',
  'margin-bottom',
  'margin-left',
  'text-align',
  'color',
  'font-size',
  'font-weight',
  'line-height',
  'max-width',
};

const _dropTableLayoutProps = <String>{
  'min-width',
  'height',
  'border-collapse',
  'border-spacing',
};

const _monospaceTags = <String>{'pre', 'code', 'kbd', 'samp', 'tt'};
const _borderShorthandProps = <String>{
  'border',
  'border-top',
  'border-right',
  'border-bottom',
  'border-left',
};

final _pixelWidthPattern = RegExp(r'^(\d+(?:\.\d+)?)\s*(?:px)?$', caseSensitive: false);
final _zeroWidthAndSpacePattern = RegExp(r'[\s\u00A0\u200B\u200C\u200D\uFEFF]+');
final _colorTokenPattern = RegExp(
  r'rgba?\([^)]+\)|#[0-9a-fA-F]{3,8}\b|\b[a-zA-Z]+\b',
);

typedef _CssRgba = ({int r, int g, int b, double a, bool isTransparent});

const _namedColors = <String, ({int r, int g, int b, double a, bool isTransparent})>{
  'transparent': (r: 0, g: 0, b: 0, a: 0, isTransparent: true),
  'black': (r: 0, g: 0, b: 0, a: 1, isTransparent: false),
  'white': (r: 255, g: 255, b: 255, a: 1, isTransparent: false),
  'gray': (r: 128, g: 128, b: 128, a: 1, isTransparent: false),
  'grey': (r: 128, g: 128, b: 128, a: 1, isTransparent: false),
  'whitesmoke': (r: 245, g: 245, b: 245, a: 1, isTransparent: false),
  'lightgray': (r: 211, g: 211, b: 211, a: 1, isTransparent: false),
  'lightgrey': (r: 211, g: 211, b: 211, a: 1, isTransparent: false),
  'silver': (r: 192, g: 192, b: 192, a: 1, isTransparent: false),
  'darkgray': (r: 169, g: 169, b: 169, a: 1, isTransparent: false),
  'darkgrey': (r: 169, g: 169, b: 169, a: 1, isTransparent: false),
  'dimgray': (r: 105, g: 105, b: 105, a: 1, isTransparent: false),
  'dimgrey': (r: 105, g: 105, b: 105, a: 1, isTransparent: false),
  'gainsboro': (r: 220, g: 220, b: 220, a: 1, isTransparent: false),
  'snow': (r: 255, g: 250, b: 250, a: 1, isTransparent: false),
  'ghostwhite': (r: 248, g: 248, b: 255, a: 1, isTransparent: false),
  'aliceblue': (r: 240, g: 248, b: 255, a: 1, isTransparent: false),
  'ivory': (r: 255, g: 255, b: 240, a: 1, isTransparent: false),
  'linen': (r: 250, g: 240, b: 230, a: 1, isTransparent: false),
  'beige': (r: 245, g: 245, b: 220, a: 1, isTransparent: false),
  'navy': (r: 0, g: 0, b: 128, a: 1, isTransparent: false),
  'blue': (r: 0, g: 0, b: 255, a: 1, isTransparent: false),
  'red': (r: 255, g: 0, b: 0, a: 1, isTransparent: false),
  'green': (r: 0, g: 128, b: 0, a: 1, isTransparent: false),
  'yellow': (r: 255, g: 255, b: 0, a: 1, isTransparent: false),
  'orange': (r: 255, g: 165, b: 0, a: 1, isTransparent: false),
};

/// 规范化邮件 HTML 正文：消除嵌套布局表格窄列挤压、剥离点阵中文字体回退，并按需适配深色模式色彩。
String normalizeEmailHtml(String rawHtml, {bool darkMode = false}) {
  if (rawHtml.trim().isEmpty) return rawHtml;

  final doc = html_parser.parse(rawHtml);
  final body = doc.body;
  if (body == null) return rawHtml;

  for (final el in body.querySelectorAll('script, noscript, style')) {
    el.remove();
  }

  // 自底向上遍历所有 table，先解包内层再处理外层
  final tables = body.querySelectorAll('table').reversed.toList();
  for (final table in tables) {
    if (table.parent == null) continue;

    final rows = _directTableRows(table);
    final isData = _isDataTable(table, rows);

    if (!isData) {
      for (final row in rows) {
        final cells = _directRowCells(row);
        if (cells.length >= 2) {
          final hasContent = cells.any((c) => !_isEmptySpacerCell(c));
          final hasSpacer = cells.any(_isEmptySpacerCell);
          if (hasContent && hasSpacer) {
            for (final cell in cells) {
              if (_isEmptySpacerCell(cell)) {
                cell.remove();
              }
            }
          }
        }

        final remainingCells = _directRowCells(row);
        if (remainingCells.isEmpty ||
            (remainingCells.every(_isEmptySpacerCell) && !_hasRowOrCellBackground(row, remainingCells))) {
          row.remove();
        }
      }

      final remainingRows = _directTableRows(table);
      final isSingleColumn = remainingRows.every((r) => _directRowCells(r).length <= 1);
      if (isSingleColumn) {
        final outerDiv = dom.Element.tag('div');
        final outerStyle = _sanitizeBlockStyles(
          table,
          onlySafeProps: true,
          includeAlign: false,
        );
        if (outerStyle.isNotEmpty) {
          outerDiv.attributes['style'] = outerStyle;
        }

        for (final row in remainingRows) {
          final cells = _directRowCells(row);
          if (cells.isEmpty) continue;
          final cell = cells.first;
          final cellDiv = dom.Element.tag('div');
          final cellStyle = _sanitizeMergedRowCellStyles(row, cell);
          if (cellStyle.isNotEmpty) {
            cellDiv.attributes['style'] = cellStyle;
          }
          for (final node in cell.nodes.toList()) {
            cellDiv.append(node);
          }
          outerDiv.append(cellDiv);
        }

        table.parent?.insertBefore(outerDiv, table);
        table.remove();
        continue;
      }
    }

    // 多列布局表格或数据表格：清理触发均分列宽 Bug 的 min-width 与超大固定像素 width
    _sanitizeResponsiveSizes(table, removeMinWidth: true);
  }

  for (final el in body.querySelectorAll('div, p, section, article, td, th')) {
    _sanitizeResponsiveSizes(el, removeMinWidth: true);
  }

  // 剥离非等宽代码元素上的内联 font-family 与 <font face>，防止 Windows 上回退到点阵 SimSun 产生毛刺
  for (final el in body.querySelectorAll('*')) {
    final tag = el.localName?.toLowerCase() ?? '';
    if (_monospaceTags.contains(tag)) continue;

    if (tag == 'font' && el.attributes.containsKey('face')) {
      el.attributes.remove('face');
    }
    final styles = _parseStyleMap(el.attributes['style']);
    if (styles.remove('font-family') != null) {
      _writeStyleMap(el, styles);
    }
  }

  for (final img in body.querySelectorAll('img')) {
    final styles = _parseStyleMap(img.attributes['style']);
    styles['max-width'] = '100%';
    styles.putIfAbsent('height', () => 'auto');
    _writeStyleMap(img, styles);
  }

  if (darkMode) {
    _adaptElementColorsForDarkMode(body, insideBrightColoredBg: false);
  }

  return body.innerHtml;
}

void _adaptElementColorsForDarkMode(dom.Element el, {required bool insideBrightColoredBg}) {
  final styles = _parseStyleMap(el.attributes['style']);
  var changed = false;
  var childInsideBrightBg = insideBrightColoredBg;

  final bgRaw = styles['background-color'] ?? styles['background'] ?? el.attributes['bgcolor'];
  final bgColor = bgRaw != null ? _parseCssColor(bgRaw) : null;
  if (bgColor != null && !bgColor.isTransparent && bgColor.a > 0.05) {
    final lum = _luminance(bgColor);
    final chroma = _chroma(bgColor);
    if (lum > 0.985 && chroma < 40) {
      // 纯白/近白背景改为透明，融入深色卡片
      if (styles.containsKey('background-color')) {
        styles['background-color'] = 'transparent';
        changed = true;
      }
      if (styles.containsKey('background') && _parseCssColor(styles['background']!) != null) {
        styles.remove('background');
        styles['background-color'] = 'transparent';
        changed = true;
      }
      if (el.attributes.remove('bgcolor') != null) {
        styles.putIfAbsent('background-color', () => 'transparent');
        changed = true;
      }
      childInsideBrightBg = false;
    } else if (lum > 0.72 && chroma < 40) {
      // 浅灰底提示框（如 #f5f5f5 / #f8f9fa）转为柔和深色表面
      styles.remove('background');
      styles['background-color'] = '#222E42';
      el.attributes.remove('bgcolor');
      changed = true;
      childInsideBrightBg = false;
    } else if (lum > 0.72 && chroma >= 40) {
      // 保持高饱和亮色底块原样，内部深色文字不再反白
      childInsideBrightBg = true;
    } else if (lum < 0.55) {
      childInsideBrightBg = false;
    }
  }

  if (!childInsideBrightBg) {
    final inlineTextColor = styles['color'];
    if (inlineTextColor != null) {
      final adapted = _adaptTextColor(inlineTextColor);
      if (adapted != null) {
        styles['color'] = adapted;
        changed = true;
      }
    }

    final attrColor = el.attributes['color'];
    if (attrColor != null) {
      final adapted = _adaptTextColor(attrColor);
      if (adapted != null) {
        el.attributes['color'] = adapted;
      }
    }
  }

  final borderColorRaw = styles['border-color'];
  if (borderColorRaw != null) {
    final bc = _parseCssColor(borderColorRaw);
    if (bc != null && !bc.isTransparent && _luminance(bc) > 0.70 && _chroma(bc) < 30) {
      styles['border-color'] = '#334155';
      changed = true;
    }
  }

  for (final prop in _borderShorthandProps) {
    final raw = styles[prop];
    if (raw == null) continue;
    final replaced = raw.replaceAllMapped(_colorTokenPattern, (match) {
      final token = match.group(0)!;
      final c = _parseCssColor(token);
      if (c != null && !c.isTransparent && _luminance(c) > 0.70 && _chroma(c) < 30) {
        return '#334155';
      }
      return token;
    });
    if (replaced != raw) {
      styles[prop] = replaced;
      changed = true;
    }
  }

  if (changed) {
    _writeStyleMap(el, styles);
  }

  for (final child in el.children) {
    _adaptElementColorsForDarkMode(child, insideBrightColoredBg: childInsideBrightBg);
  }
}

String? _adaptTextColor(String rawColor) {
  final c = _parseCssColor(rawColor);
  if (c == null || c.isTransparent) return null;

  final lum = _luminance(c);
  final chroma = _chroma(c);

  if (c.b > c.r + 40 && lum < 0.55) {
    return '#60A5FA';
  }
  if (lum < 0.45 && chroma < 50) {
    if (c.a < 0.65 || lum >= 0.28) {
      return '#94A3B8';
    }
    return '#F1F5F9';
  }
  return null;
}

_CssRgba? _parseCssColor(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;

  final named = _namedColors[s];
  if (named != null) return named;

  if (s.startsWith('#')) {
    final hex = s.substring(1);
    if (hex.length == 3) {
      final r = int.tryParse('${hex[0]}${hex[0]}', radix: 16);
      final g = int.tryParse('${hex[1]}${hex[1]}', radix: 16);
      final b = int.tryParse('${hex[2]}${hex[2]}', radix: 16);
      if (r != null && g != null && b != null) {
        return (r: r, g: g, b: b, a: 1.0, isTransparent: false);
      }
    } else if (hex.length == 6) {
      final r = int.tryParse(hex.substring(0, 2), radix: 16);
      final g = int.tryParse(hex.substring(2, 4), radix: 16);
      final b = int.tryParse(hex.substring(4, 6), radix: 16);
      if (r != null && g != null && b != null) {
        return (r: r, g: g, b: b, a: 1.0, isTransparent: false);
      }
    } else if (hex.length == 8) {
      final r = int.tryParse(hex.substring(0, 2), radix: 16);
      final g = int.tryParse(hex.substring(2, 4), radix: 16);
      final b = int.tryParse(hex.substring(4, 6), radix: 16);
      final aByte = int.tryParse(hex.substring(6, 8), radix: 16);
      if (r != null && g != null && b != null && aByte != null) {
        final a = aByte / 255.0;
        return (r: r, g: g, b: b, a: a, isTransparent: a <= 0.01);
      }
    }
    return null;
  }

  final rgbMatch = RegExp(r'^rgba?\(\s*([^)]+)\s*\)$').firstMatch(s);
  if (rgbMatch != null) {
    final parts = rgbMatch
        .group(1)!
        .replaceAll('/', ' ')
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 3) {
      final r = _parseColorChannel(parts[0]);
      final g = _parseColorChannel(parts[1]);
      final b = _parseColorChannel(parts[2]);
      final a = parts.length >= 4 ? _parseAlphaChannel(parts[3]) : 1.0;
      if (r != null && g != null && b != null && a != null) {
        return (r: r, g: g, b: b, a: a, isTransparent: a <= 0.01);
      }
    }
  }
  return null;
}

int? _parseColorChannel(String raw) {
  final t = raw.trim();
  if (t.endsWith('%')) {
    final pct = double.tryParse(t.substring(0, t.length - 1));
    if (pct == null) return null;
    return (pct.clamp(0, 100) * 2.55).round();
  }
  final v = double.tryParse(t);
  return v?.clamp(0, 255).round();
}

double? _parseAlphaChannel(String raw) {
  final t = raw.trim();
  if (t.endsWith('%')) {
    final pct = double.tryParse(t.substring(0, t.length - 1));
    if (pct == null) return null;
    return (pct.clamp(0, 100) / 100.0);
  }
  final v = double.tryParse(t);
  return v?.clamp(0.0, 1.0);
}

double _luminance(_CssRgba c) {
  return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) / 255.0;
}

int _chroma(_CssRgba c) {
  return math.max(c.r, math.max(c.g, c.b)) - math.min(c.r, math.min(c.g, c.b));
}

List<dom.Element> _directTableRows(dom.Element table) {
  final rows = <dom.Element>[];
  for (final child in table.children) {
    final tag = child.localName?.toLowerCase();
    if (tag == 'tr') {
      rows.add(child);
    } else if (tag == 'tbody' || tag == 'thead' || tag == 'tfoot') {
      for (final grandChild in child.children) {
        if (grandChild.localName?.toLowerCase() == 'tr') {
          rows.add(grandChild);
        }
      }
    }
  }
  return rows;
}

List<dom.Element> _directRowCells(dom.Element row) {
  return row.children.where((c) {
    final tag = c.localName?.toLowerCase();
    return tag == 'td' || tag == 'th';
  }).toList();
}

bool _isDataTable(dom.Element table, List<dom.Element> rows) {
  for (final child in table.children) {
    final tag = child.localName?.toLowerCase();
    if (tag == 'thead' || tag == 'tfoot' || tag == 'caption') {
      return true;
    }
  }
  final borderAttr = table.attributes['border']?.trim();
  if (borderAttr != null) {
    final borderVal = int.tryParse(borderAttr);
    if (borderVal != null && borderVal > 0) {
      return true;
    }
  }
  for (final row in rows) {
    for (final cell in _directRowCells(row)) {
      if (cell.localName?.toLowerCase() == 'th') {
        return true;
      }
    }
  }
  return false;
}

bool _isEmptySpacerCell(dom.Element cell) {
  final colspan = int.tryParse(cell.attributes['colspan']?.trim() ?? '') ?? 1;
  final rowspan = int.tryParse(cell.attributes['rowspan']?.trim() ?? '') ?? 1;
  if (colspan > 1 || rowspan > 1) return false;

  if (cell.querySelector('img, a, button, input, svg, hr, table, iframe') != null) {
    return false;
  }

  final cleanedText = cell.text.replaceAll(_zeroWidthAndSpacePattern, '');
  return cleanedText.isEmpty;
}

bool _hasRowOrCellBackground(dom.Element row, List<dom.Element> cells) {
  bool hasBg(dom.Element el) {
    if ((el.attributes['bgcolor'] ?? '').trim().isNotEmpty) return true;
    final styles = _parseStyleMap(el.attributes['style']);
    return styles.containsKey('background') || styles.containsKey('background-color');
  }

  return hasBg(row) || cells.any(hasBg);
}

String _sanitizeMergedRowCellStyles(dom.Element row, dom.Element cell) {
  final rowStyles = _sanitizeBlockStyleMap(row, onlySafeProps: true, includeAlign: true);
  final cellStyles = _sanitizeBlockStyleMap(cell, onlySafeProps: true, includeAlign: true);
  rowStyles.addAll(cellStyles);
  return _formatStyleMap(rowStyles);
}

String _sanitizeBlockStyles(
  dom.Element el, {
  required bool onlySafeProps,
  required bool includeAlign,
}) {
  final map = _sanitizeBlockStyleMap(
    el,
    onlySafeProps: onlySafeProps,
    includeAlign: includeAlign,
  );
  return _formatStyleMap(map);
}

Map<String, String> _sanitizeBlockStyleMap(
  dom.Element el, {
  required bool onlySafeProps,
  required bool includeAlign,
}) {
  final raw = _parseStyleMap(el.attributes['style']);
  final out = <String, String>{};

  for (final entry in raw.entries) {
    final key = entry.key;
    final val = entry.value;
    if (_dropTableLayoutProps.contains(key)) continue;

    if (key == 'width') {
      final px = _parsePixelValue(val);
      if (px != null && px > 320) {
        out.putIfAbsent('max-width', () => '${_formatNum(px)}px');
        out['width'] = '100%';
      } else if (val.trim().endsWith('%')) {
        out['width'] = val;
      }
      continue;
    }

    if (!onlySafeProps || _safeBlockStyleProps.contains(key)) {
      out[key] = val;
    }
  }

  final widthAttr = _parsePixelValue(el.attributes['width']);
  if (widthAttr != null && widthAttr > 320) {
    out.putIfAbsent('max-width', () => '${_formatNum(widthAttr)}px');
    out.putIfAbsent('width', () => '100%');
  }

  final bgcolor = (el.attributes['bgcolor'] ?? '').trim();
  if (bgcolor.isNotEmpty && !out.containsKey('background') && !out.containsKey('background-color')) {
    out['background-color'] = bgcolor;
  }

  if (includeAlign && !out.containsKey('text-align')) {
    final align = (el.attributes['align'] ?? '').trim().toLowerCase();
    if (align == 'left' || align == 'center' || align == 'right') {
      out['text-align'] = align;
    }
  }

  return out;
}

void _sanitizeResponsiveSizes(dom.Element el, {required bool removeMinWidth}) {
  final styles = _parseStyleMap(el.attributes['style']);
  var changed = false;

  if (removeMinWidth && styles.remove('min-width') != null) {
    changed = true;
  }

  final widthVal = styles['width'];
  if (widthVal != null) {
    final px = _parsePixelValue(widthVal);
    if (px != null && px > 320) {
      styles.putIfAbsent('max-width', () => '${_formatNum(px)}px');
      styles['width'] = '100%';
      changed = true;
    }
  }

  final widthAttr = _parsePixelValue(el.attributes['width']);
  if (widthAttr != null && widthAttr > 320) {
    el.attributes.remove('width');
    styles.putIfAbsent('max-width', () => '${_formatNum(widthAttr)}px');
    styles.putIfAbsent('width', () => '100%');
    changed = true;
  }

  if (changed) {
    _writeStyleMap(el, styles);
  }
}

Map<String, String> _parseStyleMap(String? style) {
  final map = <String, String>{};
  if (style == null || style.trim().isEmpty) return map;
  for (final decl in style.split(';')) {
    final idx = decl.indexOf(':');
    if (idx <= 0) continue;
    final key = decl.substring(0, idx).trim().toLowerCase();
    final val = decl.substring(idx + 1).trim();
    if (key.isNotEmpty && val.isNotEmpty) {
      map[key] = val;
    }
  }
  return map;
}

String _formatStyleMap(Map<String, String> styles) {
  return styles.entries.map((e) => '${e.key}: ${e.value}').join('; ');
}

void _writeStyleMap(dom.Element el, Map<String, String> styles) {
  if (styles.isEmpty) {
    el.attributes.remove('style');
  } else {
    el.attributes['style'] = _formatStyleMap(styles);
  }
}

double? _parsePixelValue(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.endsWith('%')) return null;
  final m = _pixelWidthPattern.firstMatch(trimmed);
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

String _formatNum(double value) {
  return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
}
