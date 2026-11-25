import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mailcontrol_app/core/email_html_normalizer.dart';

const _googleSecurityAlertHtml = '''
<table width="100%" height="100%" style="min-width: 348px;" border="0" cellspacing="0" cellpadding="0" lang="zh-CN">
  <tr height="32" style="height: 32px;"><td></td></tr>
  <tr align="center">
    <td>
      <table border="0" cellspacing="0" cellpadding="0" style="padding-bottom: 20px; max-width: 516px; min-width: 220px;">
        <tr>
          <td width="8" style="width: 8px;"></td>
          <td>
            <div style="background-color: #f5f5f5; padding: 12px 16px; font-size: 13px; color: #5f6368;">
              <p>user@example.com 的安全提醒转发邮件。如果不需要转发，请<a href="https://accounts.google.com">移除</a>您的邮箱。</p>
            </div>
            <div style="border-style: solid; border-width: thin; border-color: #dadce0; border-radius: 8px; padding: 40px 20px;" align="center">
              <img src="https://www.gstatic.com/images/branding/googlelogo/2x/googlelogo_color_74x24dp.png" width="74" height="24" alt="Google">
              <div style="font-size: 24px; color: rgba(0,0,0,0.87); line-height: 32px; padding-top: 16px;">
                已创建用于登录 Google 账号的通行密钥
              </div>
              <div style="font-size: 14px; color: rgba(0,0,0,0.87); line-height: 20px; padding-top: 20px; text-align: left;">
                您的 Google 账号已添加一个新的通行密钥，以后可以使用该通行密钥安全登录。
              </div>
            </div>
          </td>
          <td width="8" style="width: 8px;"></td>
        </tr>
      </table>
    </td>
  </tr>
  <tr height="32" style="height: 32px;"><td></td></tr>
</table>
''';

void main() {
  test('unwraps nested single-column Google alert tables and strips min-width', () {
    final normalized = normalizeEmailHtml(_googleSecurityAlertHtml);

    expect(normalized.toLowerCase(), isNot(contains('<table')));
    expect(normalized.toLowerCase(), isNot(contains('min-width')));
    expect(normalized, contains('已创建用于登录 Google 账号的通行密钥'));
    expect(normalized, contains('https://accounts.google.com'));
    expect(normalized, contains('移除'));
  });

  test('preserves multi-column data table while removing min-width', () {
    const dataTableHtml = '''
      <table border="1" style="min-width: 480px; width: 100%; border-collapse: collapse;">
        <thead>
          <tr><th>项目</th><th>状态</th></tr>
        </thead>
        <tbody>
          <tr><td>服务器检查</td><td>正常</td></tr>
        </tbody>
      </table>
    ''';

    final normalized = normalizeEmailHtml(dataTableHtml);

    expect(normalized.toLowerCase(), contains('<table'));
    expect(normalized.toLowerCase(), contains('<th>项目</th>'));
    expect(normalized.toLowerCase(), contains('<td>服务器检查</td>'));
    expect(normalized.toLowerCase(), isNot(contains('min-width')));
  });

  test('strips non-monospace font-family and font face while keeping code font', () {
    const fontHtml = '''
      <div style="font-family: 'Google Sans', Roboto, Helvetica, Arial, sans-serif; font-size: 15px;">
        <font face="SimSun" color="#202124">中文正文内容</font>
        <code style="font-family: Consolas, monospace;">flutter test</code>
      </div>
    ''';

    final normalized = normalizeEmailHtml(fontHtml);

    expect(normalized.toLowerCase(), isNot(contains('google sans')));
    expect(normalized.toLowerCase(), isNot(contains('simsun')));
    expect(normalized.toLowerCase(), isNot(contains('face=')));
    expect(normalized, contains('Consolas'));
    expect(normalized, contains('中文正文内容'));
  });

  test('adapts dark text, light backgrounds and borders for dark mode while preserving buttons', () {
    const darkAlertHtml = '''
      <div style="background-color: #f5f5f5; color: #5f6368; border: 1px solid #dadce0;">
        提示正文
      </div>
      <div style="background-color: #ffffff; color: rgba(0,0,0,0.87); border-color: #dadce0;">
        主标题
        <a href="https://example.com" style="background-color: #1a73e8; color: #ffffff;">查看活动</a>
      </div>
    ''';

    final normalized = normalizeEmailHtml(darkAlertHtml, darkMode: true);
    final lower = normalized.toLowerCase();

    expect(lower, contains('#222e42'));
    expect(lower, contains('#94a3b8'));
    expect(lower, contains('#f1f5f9'));
    expect(lower, contains('#334155'));
    expect(lower, contains('background-color: transparent'));
    expect(lower, contains('#1a73e8'));
    expect(lower, contains('#ffffff'));
  });

  testWidgets('renders normalized Google security alert without squeezing text into narrow column', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final normalized = normalizeEmailHtml(_googleSecurityAlertHtml);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: 780,
                child: HtmlWidget(
                  normalized,
                  textStyle: const TextStyle(fontSize: 14.5, height: 1.68),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.textContaining('已创建用于登录 Google 账号的通行密钥', findRichText: true);
    expect(titleFinder, findsOneWidget);

    final titleSize = tester.getSize(titleFinder);
    expect(titleSize.width, greaterThan(200));
  });
}
