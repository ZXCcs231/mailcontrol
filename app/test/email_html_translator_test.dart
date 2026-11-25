import 'package:flutter_test/flutter_test.dart';
import 'package:mailcontrol_app/core/email_html_translator.dart';

void main() {
  test('translateHtmlInPlace keeps HTML layout, skips code/URLs and splits mismatched lines', () async {
    const html = '''
      <div style="color:#202124">
        <p>Hello <strong>Team</strong></p>
        <p><a href="https://example.com">Confirm Email</a></p>
        <code>flutter test</code>
        <p>https://verify.example.com/abc</p>
      </div>
    ''';

    final out = await translateHtmlInPlace(
      rawHtml: html,
      translateBatch: (text) async {
        if (text.contains('\n')) {
          return text.replaceAll('\n', ' | ');
        }
        return '[译]$text';
      },
    );

    expect(out, contains('<strong>[译]Team</strong>'));
    expect(out, contains('<a href="https://example.com">[译]Confirm Email</a>'));
    expect(out, contains('<code>flutter test</code>'));
    expect(out, contains('<p>https://verify.example.com/abc</p>'));
    expect(out, contains('style="color:#202124"'));
  });
}
