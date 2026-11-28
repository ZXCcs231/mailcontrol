int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool _asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.toLowerCase() == 'true' || v == '1';
  return fallback;
}

String _asStr(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  return v.toString();
}

DateTime _asDate(dynamic v) {
  if (v is String && v.isNotEmpty) {
    return DateTime.tryParse(v)?.toLocal() ?? DateTime.now();
  }
  return DateTime.now();
}

class AppUser {
  final int id;
  final String username;
  final String email;

  AppUser({required this.id, required this.username, required this.email});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: _asInt(j['id']),
        username: _asStr(j['username']),
        email: _asStr(j['email']),
      );
}

class ProviderPreset {
  final String id;
  final String name;
  final List<String> domains;
  final String imapHost;
  final int imapPort;
  final String imapTls;
  final String smtpHost;
  final int smtpPort;
  final String smtpTls;
  final bool needsImapId;
  final String authTip;

  ProviderPreset({
    required this.id,
    required this.name,
    required this.domains,
    required this.imapHost,
    required this.imapPort,
    required this.imapTls,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpTls,
    required this.needsImapId,
    required this.authTip,
  });

  factory ProviderPreset.fromJson(Map<String, dynamic> j) => ProviderPreset(
        id: _asStr(j['id']),
        name: _asStr(j['name']),
        domains: (j['domains'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        imapHost: _asStr(j['imap_host']),
        imapPort: _asInt(j['imap_port'], 993),
        imapTls: _asStr(j['imap_tls'], 'ssl'),
        smtpHost: _asStr(j['smtp_host']),
        smtpPort: _asInt(j['smtp_port'], 465),
        smtpTls: _asStr(j['smtp_tls'], 'ssl'),
        needsImapId: _asBool(j['needs_imap_id']),
        authTip: _asStr(j['auth_tip']),
      );
}

class MailAccount {
  final int id;
  final String label;
  final String emailAddress;
  final String providerId;
  final String imapHost;
  final int imapPort;
  final String imapTls;
  final String smtpHost;
  final int smtpPort;
  final String smtpTls;
  final String username;
  final String color;
  final bool isDefault;
  final bool syncEnabled;
  final int syncIntervalSec;
  final DateTime? lastSyncAt;
  final String lastSyncStatus;
  final String lastSyncError;
  final int unreadCount;

  MailAccount({
    required this.id,
    required this.label,
    required this.emailAddress,
    required this.providerId,
    required this.imapHost,
    required this.imapPort,
    required this.imapTls,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpTls,
    required this.username,
    required this.color,
    required this.isDefault,
    required this.syncEnabled,
    required this.syncIntervalSec,
    this.lastSyncAt,
    required this.lastSyncStatus,
    required this.lastSyncError,
    required this.unreadCount,
  });

  factory MailAccount.fromJson(Map<String, dynamic> j) => MailAccount(
        id: _asInt(j['id']),
        label: _asStr(j['label']),
        emailAddress: _asStr(j['email_address']),
        providerId: _asStr(j['provider_id'], 'custom'),
        imapHost: _asStr(j['imap_host']),
        imapPort: _asInt(j['imap_port'], 993),
        imapTls: _asStr(j['imap_tls'], 'ssl'),
        smtpHost: _asStr(j['smtp_host']),
        smtpPort: _asInt(j['smtp_port'], 465),
        smtpTls: _asStr(j['smtp_tls'], 'ssl'),
        username: _asStr(j['username']),
        color: _asStr(j['color'], '#2563eb'),
        isDefault: _asBool(j['is_default']),
        syncEnabled: _asBool(j['sync_enabled'], true),
        syncIntervalSec: _asInt(j['sync_interval_sec'], 180),
        lastSyncAt: j['last_sync_at'] != null ? DateTime.tryParse(_asStr(j['last_sync_at']))?.toLocal() : null,
        lastSyncStatus: _asStr(j['last_sync_status'], 'idle'),
        lastSyncError: _asStr(j['last_sync_error']),
        unreadCount: _asInt(j['unread_count']),
      );
}

class MailFolder {
  final int id;
  final int accountId;
  final String name;
  final String remoteName;
  final String role;
  final int unreadCount;
  final int totalCount;

  MailFolder({
    required this.id,
    required this.accountId,
    required this.name,
    required this.remoteName,
    required this.role,
    required this.unreadCount,
    required this.totalCount,
  });

  factory MailFolder.fromJson(Map<String, dynamic> j) => MailFolder(
        id: _asInt(j['id']),
        accountId: _asInt(j['account_id']),
        name: _asStr(j['name']),
        remoteName: _asStr(j['remote_name']),
        role: _asStr(j['role'], 'custom'),
        unreadCount: _asInt(j['unread_count']),
        totalCount: _asInt(j['total_count']),
      );
}

class MailTag {
  final int id;
  final String name;
  final String color;

  MailTag({required this.id, required this.name, required this.color});

  factory MailTag.fromJson(Map<String, dynamic> j) => MailTag(
        id: _asInt(j['id']),
        name: _asStr(j['name']),
        color: _asStr(j['color'], '#3b82f6'),
      );
}

class MailAttachment {
  final int id;
  final int messageId;
  final String filename;
  final String contentType;
  final int size;
  final bool isInline;

  MailAttachment({
    required this.id,
    required this.messageId,
    required this.filename,
    required this.contentType,
    required this.size,
    required this.isInline,
  });

  factory MailAttachment.fromJson(Map<String, dynamic> j) => MailAttachment(
        id: _asInt(j['id']),
        messageId: _asInt(j['message_id']),
        filename: _asStr(j['filename'], 'attachment'),
        contentType: _asStr(j['content_type'], 'application/octet-stream'),
        size: _asInt(j['size']),
        isInline: _asBool(j['is_inline']),
      );
}

class MailMessage {
  final int id;
  final int accountId;
  final String accountLabel;
  final String accountEmail;
  final String accountColor;
  final int folderId;
  final String folderRole;
  final String folderName;
  final String messageIdHeader;
  final String inReplyTo;
  final String subject;
  final String fromName;
  final String fromAddr;
  final String toAddrs;
  final String ccAddrs;
  final String bccAddrs;
  final String snippet;
  final String bodyText;
  final String bodyHtml;
  final bool isRead;
  final bool isStarred;
  final bool isDraft;
  final bool hasAttachments;
  final DateTime sentAt;
  final DateTime receivedAt;
  final List<MailTag> tags;
  final List<MailAttachment> attachments;

  MailMessage({
    required this.id,
    required this.accountId,
    required this.accountLabel,
    required this.accountEmail,
    required this.accountColor,
    required this.folderId,
    required this.folderRole,
    required this.folderName,
    required this.messageIdHeader,
    required this.inReplyTo,
    required this.subject,
    required this.fromName,
    required this.fromAddr,
    required this.toAddrs,
    required this.ccAddrs,
    required this.bccAddrs,
    required this.snippet,
    required this.bodyText,
    required this.bodyHtml,
    required this.isRead,
    required this.isStarred,
    required this.isDraft,
    required this.hasAttachments,
    required this.sentAt,
    required this.receivedAt,
    required this.tags,
    required this.attachments,
  });

  String get senderDisplay => fromName.trim().isNotEmpty ? fromName.trim() : fromAddr;

  factory MailMessage.fromJson(Map<String, dynamic> j) => MailMessage(
        id: _asInt(j['id']),
        accountId: _asInt(j['account_id']),
        accountLabel: _asStr(j['account_label']),
        accountEmail: _asStr(j['account_email']),
        accountColor: _asStr(j['account_color'], '#2563eb'),
        folderId: _asInt(j['folder_id']),
        folderRole: _asStr(j['folder_role']),
        folderName: _asStr(j['folder_name']),
        messageIdHeader: _asStr(j['message_id_header']),
        inReplyTo: _asStr(j['in_reply_to']),
        subject: _asStr(j['subject'], '（无主题）'),
        fromName: _asStr(j['from_name']),
        fromAddr: _asStr(j['from_addr']),
        toAddrs: _asStr(j['to_addrs']),
        ccAddrs: _asStr(j['cc_addrs']),
        bccAddrs: _asStr(j['bcc_addrs']),
        snippet: _asStr(j['snippet']),
        bodyText: _asStr(j['body_text']),
        bodyHtml: _asStr(j['body_html']),
        isRead: _asBool(j['is_read']),
        isStarred: _asBool(j['is_starred']),
        isDraft: _asBool(j['is_draft']),
        hasAttachments: _asBool(j['has_attachments']),
        sentAt: _asDate(j['sent_at']),
        receivedAt: _asDate(j['received_at']),
        tags: (j['tags'] as List?)?.map((e) => MailTag.fromJson(Map<String, dynamic>.from(e))).toList() ?? const [],
        attachments:
            (j['attachments'] as List?)?.map((e) => MailAttachment.fromJson(Map<String, dynamic>.from(e))).toList() ??
                const [],
      );
}

class MailStats {
  final int inboxUnread;
  final int starredCount;
  final int draftsCount;
  final Map<int, int> accountUnread;
  final Map<int, int> tagUnread;
  final bool hasTagCounts;

  const MailStats({
    this.inboxUnread = 0,
    this.starredCount = 0,
    this.draftsCount = 0,
    this.accountUnread = const {},
    this.tagUnread = const {},
    this.hasTagCounts = false,
  });

  MailStats copyWith({
    Map<int, int>? tagUnread,
    bool? hasTagCounts,
  }) =>
      MailStats(
        inboxUnread: inboxUnread,
        starredCount: starredCount,
        draftsCount: draftsCount,
        accountUnread: accountUnread,
        tagUnread: tagUnread ?? this.tagUnread,
        hasTagCounts: hasTagCounts ?? this.hasTagCounts,
      );

  factory MailStats.fromJson(Map<String, dynamic> j) {
    final map = <int, int>{};
    for (final item in (j['account_counts'] as List?) ?? const []) {
      final m = Map<String, dynamic>.from(item);
      map[_asInt(m['account_id'])] = _asInt(m['unread_count']);
    }
    final hasTagCounts = j.containsKey('tag_counts') && j['tag_counts'] is List;
    final tagMap = <int, int>{};
    if (hasTagCounts) {
      for (final item in j['tag_counts'] as List) {
        final m = Map<String, dynamic>.from(item);
        tagMap[_asInt(m['tag_id'])] = _asInt(m['unread_count']);
      }
    }
    return MailStats(
      inboxUnread: _asInt(j['inbox_unread']),
      starredCount: _asInt(j['starred_count']),
      draftsCount: _asInt(j['drafts_count']),
      accountUnread: map,
      tagUnread: tagMap,
      hasTagCounts: hasTagCounts,
    );
  }
}

class RuleCondition {
  final String field;
  final String operatorName;
  final String value;

  RuleCondition({required this.field, required this.operatorName, required this.value});

  factory RuleCondition.fromJson(Map<String, dynamic> j) => RuleCondition(
        field: _asStr(j['field'], 'subject'),
        operatorName: _asStr(j['operator'], 'contains'),
        value: _asStr(j['value']),
      );

  Map<String, dynamic> toJson() => {
        'field': field,
        'operator': operatorName,
        'value': value,
      };
}

class RuleAction {
  final String type;
  final String value;

  RuleAction({required this.type, this.value = ''});

  factory RuleAction.fromJson(Map<String, dynamic> j) => RuleAction(
        type: _asStr(j['type'], 'mark_read'),
        value: _asStr(j['value']),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        if (value.isNotEmpty) 'value': value,
      };
}

class MailRule {
  final int id;
  final int? accountId;
  final String name;
  final bool enabled;
  final int priority;
  final String matchMode;
  final List<RuleCondition> conditions;
  final List<RuleAction> actions;

  MailRule({
    required this.id,
    this.accountId,
    required this.name,
    required this.enabled,
    required this.priority,
    required this.matchMode,
    required this.conditions,
    required this.actions,
  });

  factory MailRule.fromJson(Map<String, dynamic> j) => MailRule(
        id: _asInt(j['id']),
        accountId: j['account_id'] != null ? _asInt(j['account_id']) : null,
        name: _asStr(j['name']),
        enabled: _asBool(j['enabled'], true),
        priority: _asInt(j['priority'], 100),
        matchMode: _asStr(j['match_mode'], 'all'),
        conditions:
            (j['conditions'] as List?)?.map((e) => RuleCondition.fromJson(Map<String, dynamic>.from(e))).toList() ??
                const [],
        actions:
            (j['actions'] as List?)?.map((e) => RuleAction.fromJson(Map<String, dynamic>.from(e))).toList() ?? const [],
      );
}

class MailSignature {
  final int id;
  final int? accountId;
  final String name;
  final String contentHtml;
  final bool isDefault;

  MailSignature({
    required this.id,
    this.accountId,
    required this.name,
    required this.contentHtml,
    required this.isDefault,
  });

  factory MailSignature.fromJson(Map<String, dynamic> j) => MailSignature(
        id: _asInt(j['id']),
        accountId: j['account_id'] != null ? _asInt(j['account_id']) : null,
        name: _asStr(j['name']),
        contentHtml: _asStr(j['content_html']),
        isDefault: _asBool(j['is_default']),
      );
}

class SseEvent {
  final String type;
  final int accountId;
  final String label;
  final int count;
  final String message;

  SseEvent({
    required this.type,
    this.accountId = 0,
    this.label = '',
    this.count = 0,
    this.message = '',
  });

  factory SseEvent.fromJson(Map<String, dynamic> j) => SseEvent(
        type: _asStr(j['type']),
        accountId: _asInt(j['account_id']),
        label: _asStr(j['label']),
        count: _asInt(j['count']),
        message: _asStr(j['message']),
      );
}

class TranslateLanguage {
  final String code;
  final String name;

  const TranslateLanguage({required this.code, required this.name});

  factory TranslateLanguage.fromJson(Map<String, dynamic> j) => TranslateLanguage(
        code: _asStr(j['code']),
        name: _asStr(j['name']),
      );
}

const kTranslateLanguages = <TranslateLanguage>[
  TranslateLanguage(code: 'zh-CN', name: '简体中文'),
  TranslateLanguage(code: 'zh-TW', name: '繁体中文'),
  TranslateLanguage(code: 'en', name: '英语'),
  TranslateLanguage(code: 'ja', name: '日语'),
  TranslateLanguage(code: 'ko', name: '韩语'),
  TranslateLanguage(code: 'fr', name: '法语'),
  TranslateLanguage(code: 'de', name: '德语'),
  TranslateLanguage(code: 'es', name: '西班牙语'),
  TranslateLanguage(code: 'ru', name: '俄语'),
  TranslateLanguage(code: 'pt', name: '葡萄牙语'),
  TranslateLanguage(code: 'ar', name: '阿拉伯语'),
];

class MessageTranslation {
  final int messageId;
  final String targetLang;
  final String provider;
  final String translatedSubject;
  final String translatedText;
  final String translatedHtml;
  final bool cached;

  MessageTranslation({
    this.messageId = 0,
    required this.targetLang,
    required this.provider,
    required this.translatedSubject,
    required this.translatedText,
    this.translatedHtml = '',
    this.cached = false,
  });

  factory MessageTranslation.fromJson(Map<String, dynamic> j) => MessageTranslation(
        messageId: _asInt(j['message_id']),
        targetLang: _asStr(j['target_lang']),
        provider: _asStr(j['provider']),
        translatedSubject: _asStr(j['translated_subject']),
        translatedText: _asStr(j['translated_text']),
        translatedHtml: _asStr(j['translated_html']),
        cached: _asBool(j['cached']),
      );
}

class PushChannel {
  final int id;
  final String name;
  final String channelType; // feishu | feishu_app | wecom | dingtalk | webhook
  final bool enabled;
  final String webhookUrl;
  final bool hasSecret;
  final String appId;
  final String targetId;
  final String targetIdType;

  PushChannel({
    required this.id,
    required this.name,
    required this.channelType,
    required this.enabled,
    this.webhookUrl = '',
    this.hasSecret = false,
    this.appId = '',
    this.targetId = '',
    this.targetIdType = 'open_id',
  });

  factory PushChannel.fromJson(Map<String, dynamic> j) => PushChannel(
        id: _asInt(j['id']),
        name: _asStr(j['name']),
        channelType: _asStr(j['channel_type'], 'feishu'),
        enabled: _asBool(j['enabled'], true),
        webhookUrl: _asStr(j['webhook_url']),
        hasSecret: _asBool(j['has_secret']),
        appId: _asStr(j['app_id']),
        targetId: _asStr(j['target_id']),
        targetIdType: _asStr(j['target_id_type'], 'open_id'),
      );
}
