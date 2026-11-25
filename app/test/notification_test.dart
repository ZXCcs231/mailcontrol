import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mailcontrol_app/core/api_client.dart';
import 'package:mailcontrol_app/core/notification_service.dart';
import 'package:mailcontrol_app/core/sse_client.dart';
import 'package:mailcontrol_app/models/models.dart';
import 'package:mailcontrol_app/providers/mail_provider.dart';

MailMessage _makeMsg({
  required int id,
  int accountId = 1,
  String accountLabel = 'QQ 邮箱',
  String fromName = 'Google',
  String fromAddr = 'no-reply@accounts.google.com',
  String subject = '安全提醒',
  String snippet = '摘要内容',
  bool isRead = false,
}) {
  final now = DateTime(2026, 11, 25, 22, 0);
  return MailMessage(
    id: id,
    accountId: accountId,
    accountLabel: accountLabel,
    accountEmail: 'user@qq.com',
    accountColor: '#2563eb',
    folderId: 1,
    folderRole: 'inbox',
    folderName: '收件箱',
    messageIdHeader: '<$id@example.com>',
    inReplyTo: '',
    subject: subject,
    fromName: fromName,
    fromAddr: fromAddr,
    toAddrs: 'user@qq.com',
    ccAddrs: '',
    bccAddrs: '',
    snippet: snippet,
    bodyText: snippet,
    bodyHtml: '',
    isRead: isRead,
    isStarred: false,
    isDraft: false,
    hasAttachments: false,
    sentAt: now,
    receivedAt: now,
    tags: const [],
    attachments: const [],
  );
}

class _RecordedNotification {
  final int id;
  final String title;
  final String body;
  final String? payload;

  _RecordedNotification({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });
}

class _FakeNotificationService extends NotificationService {
  final List<_RecordedNotification> shown = [];
  bool initialized = false;
  bool permissionRequested = false;

  @override
  Future<void> init({void Function(String? payload)? onTap}) async {
    initialized = true;
  }

  @override
  Future<void> requestPermissionIfNeeded() async {
    permissionRequested = true;
  }

  @override
  Future<void> showNewMailNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    shown.add(_RecordedNotification(id: id, title: title, body: body, payload: payload));
  }
}

class _FakeSseClient extends SseClient {
  final _ctrl = StreamController<SseEvent>.broadcast();

  @override
  Stream<SseEvent> get stream => _ctrl.stream;

  @override
  void connect(String baseUrl, String token) {}

  @override
  void disconnect() {}

  void emit(SseEvent evt) => _ctrl.add(evt);

  @override
  void dispose() {
    _ctrl.close();
  }
}

class _FakeApiClient extends ApiClient {
  List<MailMessage> inboxMessages = [];

  @override
  void configure({required String baseUrl, String? token}) {}

  @override
  Future<({String token, AppUser user})> login({
    required String account,
    required String password,
  }) async {
    return (
      token: 'test-token',
      user: AppUser(id: 1, username: account, email: 'do@example.com'),
    );
  }

  @override
  Future<List<ProviderPreset>> getProviders() async => const [];

  @override
  Future<List<MailAccount>> getAccounts() async => const [];

  @override
  Future<List<MailFolder>> getFolders({int? accountId}) async => const [];

  @override
  Future<MailStats> getStats() async => const MailStats();

  @override
  Future<List<MailTag>> getTags() async => const [];

  @override
  Future<List<MailRule>> getRules() async => const [];

  @override
  Future<List<MailSignature>> getSignatures() async => const [];

  @override
  Future<({List<MailMessage> items, int total})> getMessages({
    String view = 'inbox',
    int? accountId,
    int? folderId,
    int? tagId,
    bool unreadOnly = false,
    bool hasAttachments = false,
    String q = '',
    int page = 1,
    int pageSize = 30,
  }) async {
    return (items: inboxMessages, total: inboxMessages.length);
  }
}

void main() {
  test('buildNewMailNotificationContent formats single, multiple and fallback notifications', () {
    final single = buildNewMailNotificationContent(
      accountLabel: 'QQ 邮箱',
      freshMessages: [_makeMsg(id: 12, fromName: 'GitHub', subject: 'Pull Request Merged')],
    );
    expect(single.title, 'GitHub（QQ 邮箱）');
    expect(single.body, 'Pull Request Merged');
    expect(single.payload, 'msg:12');

    final emptySubj = buildNewMailNotificationContent(
      accountLabel: '',
      freshMessages: [_makeMsg(id: 13, accountLabel: '工作邮箱', fromName: '', fromAddr: 'boss@co.com', subject: '', snippet: '请查收周报')],
    );
    expect(emptySubj.title, 'boss@co.com（工作邮箱）');
    expect(emptySubj.body, '请查收周报');

    final multi = buildNewMailNotificationContent(
      accountLabel: 'QQ 邮箱',
      freshMessages: [
        _makeMsg(id: 21, fromName: 'Alice', subject: '合同确认'),
        _makeMsg(id: 20, fromName: 'Bob', subject: '会议纪要'),
      ],
    );
    expect(multi.title, 'QQ 邮箱 收到 2 封新邮件');
    expect(multi.body, '最新：Alice - 合同确认');
    expect(multi.payload, 'msg:21');

    final fallback = buildNewMailNotificationContent(
      accountLabel: 'QQ 邮箱',
      freshMessages: const [],
      fallbackCount: 3,
    );
    expect(fallback.title, 'MailControl · 新邮件提醒');
    expect(fallback.body, 'QQ 邮箱 收到 3 封新邮件');
    expect(fallback.payload, isNull);

    final taggedMsg = MailMessage(
      id: 31,
      accountId: 1,
      accountLabel: 'QQ 邮箱',
      accountEmail: 'user@qq.com',
      accountColor: '#2563eb',
      folderId: 1,
      folderRole: 'inbox',
      folderName: '收件箱',
      messageIdHeader: '<31@example.com>',
      inReplyTo: '',
      subject: '您的验证码是 123456',
      fromName: 'GitHub',
      fromAddr: 'noreply@github.com',
      toAddrs: 'user@qq.com',
      ccAddrs: '',
      bccAddrs: '',
      snippet: '',
      bodyText: '',
      bodyHtml: '',
      isRead: false,
      isStarred: false,
      isDraft: false,
      hasAttachments: false,
      sentAt: DateTime(2026, 11, 26),
      receivedAt: DateTime(2026, 11, 26),
      tags: [MailTag(id: 5, name: '验证码', color: '#0891b2')],
      attachments: const [],
    );
    final taggedNotif = buildNewMailNotificationContent(
      accountLabel: 'QQ 邮箱',
      freshMessages: [taggedMsg],
    );
    expect(taggedNotif.title, '[验证码] GitHub（QQ 邮箱）');
  });

  test('MailStats.fromJson parses tag_counts and sets hasTagCounts', () {
    final withTags = MailStats.fromJson({
      'inbox_unread': 5,
      'starred_count': 2,
      'drafts_count': 1,
      'account_counts': [
        {'account_id': 1, 'unread_count': 5},
      ],
      'tag_counts': [
        {'tag_id': 10, 'unread_count': 3},
        {'tag_id': 11, 'unread_count': 0},
      ],
    });
    expect(withTags.hasTagCounts, isTrue);
    expect(withTags.tagUnread[10], 3);
    expect(withTags.tagUnread[11], 0);

    final legacy = MailStats.fromJson({
      'inbox_unread': 5,
      'account_counts': [],
    });
    expect(legacy.hasTagCounts, isFalse);
    expect(legacy.tagUnread, isEmpty);
  });

  test('notifies once per new message when logged in and suppresses after logout', () async {
    SharedPreferences.setMockInitialValues({});
    final fakeApi = _FakeApiClient()..inboxMessages = [_makeMsg(id: 100, isRead: false)];
    final fakeSse = _FakeSseClient();
    final fakeNotif = _FakeNotificationService();

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(fakeApi),
        sseClientProvider.overrideWithValue(fakeSse),
        notificationServiceProvider.overrideWithValue(fakeNotif),
      ],
    );
    addTearDown(container.dispose);

    final ok = await container.read(authProvider.notifier).login('do', 'secret');
    expect(ok, isTrue);

    await container.read(mailProvider.notifier).bootstrap();
    expect(fakeNotif.initialized, isTrue);
    expect(fakeNotif.permissionRequested, isTrue);
    // 历史未读邮件（id: 100）不应在刚登录建立基线时弹窗
    expect(fakeNotif.shown, isEmpty);

    // 同步到一封新邮件（id: 101）
    fakeApi.inboxMessages = [_makeMsg(id: 101, subject: '验证码 889900'), _makeMsg(id: 100)];
    fakeSse.emit(SseEvent(type: 'new_messages', accountId: 1, label: 'QQ 邮箱', count: 1));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(fakeNotif.shown.length, 1);
    expect(fakeNotif.shown.first.id, 101);
    expect(fakeNotif.shown.first.body, '验证码 889900');

    // 重复 SSE 事件不应重复弹同一封新邮件
    fakeSse.emit(SseEvent(type: 'new_messages', accountId: 1, label: 'QQ 邮箱', count: 0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fakeNotif.shown.length, 1);

    // 退出登录后收到事件不应触发任何弹窗
    await container.read(authProvider.notifier).logout();
    fakeApi.inboxMessages = [_makeMsg(id: 102, subject: '退出后的消息')];
    fakeSse.emit(SseEvent(type: 'new_messages', accountId: 1, label: 'QQ 邮箱', count: 1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fakeNotif.shown.length, 1);
  });
}
