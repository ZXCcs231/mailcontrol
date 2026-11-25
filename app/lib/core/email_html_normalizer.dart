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
  'font-family',
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

final _pixelWidthPattern = RegExp(r'^(\d+(?:\.\d+)?)\s*(?:px)?$', caseSensitive: false);
final _zeroWidthAndSpacePattern = RegExp(r'[\s\u00A0\u200B\u200C\u200D\uFEFF]+');

/// 规范化邮件 HTML 正文，消除嵌套布局表格与固定 min-width 导致的极窄竖列排版问题。
String normalizeEmailHtml(String rawHtml) {
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

  for (final img in body.querySelectorAll('img')) {
    final styles = _parseStyleMap(img.attributes['style']);
    styles['max-width'] = '100%';
    styles.putIfAbsent('height', () => 'auto');
    _writeStyleMap(img, styles);
  }

  return body.innerHtml;
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
