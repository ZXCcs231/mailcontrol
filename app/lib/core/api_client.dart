import 'package:dio/dio.dart';

import '../models/models.dart';

class ApiClient {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  String _baseUrl = 'http://127.0.0.1:8080';
  String? _token;

  String get baseUrl => _baseUrl;
  String? get token => _token;

  void configure({required String baseUrl, String? token}) {
    _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _token = token;
    _dio.options.baseUrl = _baseUrl;
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  String extractError(Object err) {
    if (err is DioException) {
      final data = err.response?.data;
      if (data is Map && data['error'] != null) {
        return data['error'].toString();
      }
      if (err.type == DioExceptionType.connectionError || err.type == DioExceptionType.connectionTimeout) {
        return '无法连接到后端服务（$_baseUrl），请确认服务已启动且地址正确';
      }
      return err.message ?? '网络请求失败';
    }
    return err.toString();
  }

  Future<bool> checkHealth([String? overrideBaseUrl]) async {
    try {
      final url = (overrideBaseUrl ?? _baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
      final resp = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 4))).get('$url/api/health');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<({String token, AppUser user})> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final resp = await _dio.post('/api/auth/register', data: {
      'username': username,
      'email': email,
      'password': password,
    });
    final data = Map<String, dynamic>.from(resp.data);
    return (token: data['token'].toString(), user: AppUser.fromJson(Map<String, dynamic>.from(data['user'])));
  }

  Future<({String token, AppUser user})> login({
    required String account,
    required String password,
  }) async {
    final resp = await _dio.post('/api/auth/login', data: {
      'account': account,
      'password': password,
    });
    final data = Map<String, dynamic>.from(resp.data);
    return (token: data['token'].toString(), user: AppUser.fromJson(Map<String, dynamic>.from(data['user'])));
  }

  Future<AppUser> me() async {
    final resp = await _dio.get('/api/auth/me');
    return AppUser.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<List<String>> getServerLanUrls() async {
    final resp = await _dio.get('/api/server-info');
    final list = (resp.data['lan_urls'] as List?) ?? const [];
    return list.map((e) => e.toString()).toList();
  }

  Future<List<ProviderPreset>> getProviders() async {
    final resp = await _dio.get('/api/providers');
    final list = (resp.data['items'] as List?) ?? const [];
    return list.map((e) => ProviderPreset.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<MailAccount>> getAccounts() async {
    final resp = await _dio.get('/api/accounts');
    final list = (resp.data['items'] as List?) ?? const [];
    return list.map((e) => MailAccount.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Map<String, dynamic>> testAccount(Map<String, dynamic> payload) async {
    final resp = await _dio.post('/api/accounts/test', data: payload);
    return Map<String, dynamic>.from(resp.data);
  }

  Future<MailAccount> createAccount(Map<String, dynamic> payload) async {
    final resp = await _dio.post('/api/accounts', data: payload);
    return MailAccount.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<MailAccount> updateAccount(int id, Map<String, dynamic> payload) async {
    final resp = await _dio.put('/api/accounts/$id', data: payload);
    return MailAccount.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<void> deleteAccount(int id) async {
    await _dio.delete('/api/accounts/$id');
  }

  Future<void> syncAccount(int id) async {
    await _dio.post('/api/accounts/$id/sync');
  }

  Future<List<MailFolder>> getFolders({int? accountId}) async {
    final resp = await _dio.get('/api/folders', queryParameters: {
      'account_id': ?accountId,
    });
    final list = (resp.data['items'] as List?) ?? const [];
    return list.map((e) => MailFolder.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<MailStats> getStats() async {
    final resp = await _dio.get('/api/stats');
    return MailStats.fromJson(Map<String, dynamic>.from(resp.data));
  }

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
    final resp = await _dio.get('/api/messages', queryParameters: {
      'view': view,
      'account_id': ?accountId,
      'folder_id': ?folderId,
      'tag_id': ?tagId,
      if (unreadOnly) 'unread_only': '1',
      if (hasAttachments) 'has_attachments': '1',
      if (q.isNotEmpty) 'q': q,
      'page': page,
      'page_size': pageSize,
    });
    final list = (resp.data['items'] as List?) ?? const [];
    return (
      items: list.map((e) => MailMessage.fromJson(Map<String, dynamic>.from(e))).toList(),
      total: (resp.data['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<MailMessage> getMessage(int id) async {
    final resp = await _dio.get('/api/messages/$id');
    return MailMessage.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<void> patchMessage(
    int id, {
    bool? isRead,
    bool? isStarred,
    String? moveRole,
    int? folderId,
    int? addTagId,
    int? removeTagId,
  }) async {
    await _dio.patch('/api/messages/$id', data: {
      'is_read': ?isRead,
      'is_starred': ?isStarred,
      'move_role': ?moveRole,
      'folder_id': ?folderId,
      'add_tag_id': ?addTagId,
      'remove_tag_id': ?removeTagId,
    });
  }

  Future<void> deleteMessage(int id, {bool permanent = false}) async {
    await _dio.delete('/api/messages/$id', queryParameters: {
      if (permanent) 'permanent': '1',
    });
  }

  Future<void> batchMessages(List<int> ids, String action, {int? tagId}) async {
    await _dio.post('/api/messages/batch', data: {
      'ids': ids,
      'action': action,
      'tag_id': ?tagId,
    });
  }

  Future<void> sendMessage({
    required int accountId,
    required String to,
    String cc = '',
    String bcc = '',
    required String subject,
    required String bodyText,
    required String bodyHtml,
    String inReplyTo = '',
    int? draftId,
    List<({String name, String path})> attachments = const [],
  }) async {
    final form = FormData.fromMap({
      'account_id': accountId.toString(),
      'to': to,
      'cc': cc,
      'bcc': bcc,
      'subject': subject,
      'body_text': bodyText,
      'body_html': bodyHtml,
      'in_reply_to': inReplyTo,
      if (draftId != null) 'draft_id': draftId.toString(),
    });
    for (final f in attachments) {
      form.files.add(MapEntry('attachments', await MultipartFile.fromFile(f.path, filename: f.name)));
    }
    await _dio.post('/api/messages/send', data: form);
  }

  Future<int> saveDraft({
    int? draftId,
    required int accountId,
    required String to,
    String cc = '',
    String bcc = '',
    required String subject,
    required String bodyText,
    required String bodyHtml,
  }) async {
    final body = {
      'account_id': accountId,
      'to': to,
      'cc': cc,
      'bcc': bcc,
      'subject': subject,
      'body_text': bodyText,
      'body_html': bodyHtml,
    };
    final resp = draftId != null
        ? await _dio.put('/api/messages/drafts/$draftId', data: body)
        : await _dio.post('/api/messages/drafts', data: body);
    return (resp.data['id'] as num?)?.toInt() ?? draftId ?? 0;
  }

  Future<void> downloadAttachment(int attachmentId, String savePath) async {
    await _dio.download('/api/attachments/$attachmentId/download', savePath);
  }

  Future<List<MailTag>> getTags() async {
    final resp = await _dio.get('/api/tags');
    final list = (resp.data['items'] as List?) ?? const [];
    return list.map((e) => MailTag.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<MailTag> createTag(String name, String color) async {
    final resp = await _dio.post('/api/tags', data: {'name': name, 'color': color});
    return MailTag.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<MailTag> updateTag(int id, String name, String color) async {
    final resp = await _dio.put('/api/tags/$id', data: {'name': name, 'color': color});
    return MailTag.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<void> deleteTag(int id) async {
    await _dio.delete('/api/tags/$id');
  }

  Future<List<MailRule>> getRules() async {
    final resp = await _dio.get('/api/rules');
    final list = (resp.data['items'] as List?) ?? const [];
    return list.map((e) => MailRule.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<MailRule> createRule(Map<String, dynamic> payload) async {
    final resp = await _dio.post('/api/rules', data: payload);
    return MailRule.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<MailRule> updateRule(int id, Map<String, dynamic> payload) async {
    final resp = await _dio.put('/api/rules/$id', data: payload);
    return MailRule.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<void> deleteRule(int id) async {
    await _dio.delete('/api/rules/$id');
  }

  Future<int> runRule(int id) async {
    final resp = await _dio.post('/api/rules/$id/run');
    return (resp.data['matched'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> getRulePresets() async {
    final resp = await _dio.get('/api/rules/presets');
    final list = (resp.data['items'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<int> applyRulePresets({List<String>? presetIds}) async {
    final resp = await _dio.post('/api/rules/presets/apply', data: {
      'preset_ids': ?presetIds,
    });
    return (resp.data['added'] as num?)?.toInt() ?? 0;
  }

  Future<List<MailSignature>> getSignatures() async {
    final resp = await _dio.get('/api/signatures');
    final list = (resp.data['items'] as List?) ?? const [];
    return list.map((e) => MailSignature.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<MailSignature> createSignature(Map<String, dynamic> payload) async {
    final resp = await _dio.post('/api/signatures', data: payload);
    return MailSignature.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<MailSignature> updateSignature(int id, Map<String, dynamic> payload) async {
    final resp = await _dio.put('/api/signatures/$id', data: payload);
    return MailSignature.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<void> deleteSignature(int id) async {
    await _dio.delete('/api/signatures/$id');
  }

  Future<List<TranslateLanguage>> getTranslateLanguages() async {
    final resp = await _dio.get('/api/translate/languages');
    final list = (resp.data['items'] as List?) ?? const [];
    return list.map((e) => TranslateLanguage.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<MessageTranslation> translateMessage(
    int messageId,
    String targetLang, {
    bool force = false,
  }) async {
    final resp = await _dio.post(
      '/api/messages/$messageId/translate',
      data: {'target_lang': targetLang, 'force': force},
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    );
    return MessageTranslation.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<MessageTranslation> translateText({
    required String text,
    String subject = '',
    required String targetLang,
  }) async {
    final resp = await _dio.post(
      '/api/translate/text',
      data: {'text': text, 'subject': subject, 'target_lang': targetLang},
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    );
    return MessageTranslation.fromJson(Map<String, dynamic>.from(resp.data));
  }
}
