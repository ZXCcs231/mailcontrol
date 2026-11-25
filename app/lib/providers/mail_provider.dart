import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/local_server_manager.dart';
import '../core/sse_client.dart';
import '../models/models.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final sseClientProvider = Provider<SseClient>((ref) {
  final client = SseClient();
  ref.onDispose(client.dispose);
  return client;
});
final localServerProvider = Provider<LocalServerManager>((ref) {
  final mgr = LocalServerManager();
  ref.onDispose(mgr.stop);
  return mgr;
});

class AuthState {
  final bool initialized;
  final bool loading;
  final String baseUrl;
  final String? token;
  final AppUser? user;
  final ThemeMode themeMode;
  final String? error;

  const AuthState({
    this.initialized = false,
    this.loading = false,
    this.baseUrl = 'http://127.0.0.1:8080',
    this.token,
    this.user,
    this.themeMode = ThemeMode.system,
    this.error,
  });

  bool get isAuthenticated => token != null && token!.isNotEmpty && user != null;

  AuthState copyWith({
    bool? initialized,
    bool? loading,
    String? baseUrl,
    String? token,
    bool clearToken = false,
    AppUser? user,
    bool clearUser = false,
    ThemeMode? themeMode,
    String? error,
    bool clearError = false,
  }) =>
      AuthState(
        initialized: initialized ?? this.initialized,
        loading: loading ?? this.loading,
        baseUrl: baseUrl ?? this.baseUrl,
        token: clearToken ? null : (token ?? this.token),
        user: clearUser ? null : (user ?? this.user),
        themeMode: themeMode ?? this.themeMode,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuthNotifier extends Notifier<AuthState> {
  static const _kBaseUrl = 'mailcontrol_base_url';
  static const _kToken = 'mailcontrol_token';
  static const _kTheme = 'mailcontrol_theme';

  @override
  AuthState build() {
    Future.microtask(init);
    return const AuthState();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_kBaseUrl) ?? 'http://127.0.0.1:8080';
    final savedToken = prefs.getString(_kToken);
    final savedTheme = prefs.getString(_kTheme) ?? 'system';

    final themeMode = switch (savedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final api = ref.read(apiClientProvider);
    api.configure(baseUrl: savedUrl, token: savedToken);

    AppUser? user;
    String? validToken = savedToken;

    if (savedToken != null && savedToken.isNotEmpty) {
      try {
        user = await api.me();
      } catch (_) {
        validToken = null;
        await prefs.remove(_kToken);
        api.configure(baseUrl: savedUrl, token: null);
      }
    }

    state = state.copyWith(
      initialized: true,
      baseUrl: savedUrl,
      token: validToken,
      clearToken: validToken == null,
      user: user,
      clearUser: user == null,
      themeMode: themeMode,
    );
  }

  Future<void> setBaseUrl(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, normalized);
    ref.read(apiClientProvider).configure(baseUrl: normalized, token: state.token);
    state = state.copyWith(baseUrl: normalized, clearError: true);
  }

  Future<void> toggleTheme() async {
    final next = state.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, next == ThemeMode.dark ? 'dark' : 'light');
    state = state.copyWith(themeMode: next);
  }

  Future<bool> login(String account, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(apiClientProvider);
      api.configure(baseUrl: state.baseUrl);
      final res = await api.login(account: account, password: password);
      api.configure(baseUrl: state.baseUrl, token: res.token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kToken, res.token);
      state = state.copyWith(loading: false, token: res.token, user: res.user);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: ref.read(apiClientProvider).extractError(e));
      return false;
    }
  }

  Future<bool> register(String username, String email, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(apiClientProvider);
      api.configure(baseUrl: state.baseUrl);
      final res = await api.register(username: username, email: email, password: password);
      api.configure(baseUrl: state.baseUrl, token: res.token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kToken, res.token);
      state = state.copyWith(loading: false, token: res.token, user: res.user);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: ref.read(apiClientProvider).extractError(e));
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    ref.read(sseClientProvider).disconnect();
    ref.read(apiClientProvider).configure(baseUrl: state.baseUrl, token: null);
    state = state.copyWith(clearToken: true, clearUser: true, clearError: true);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class MailState {
  final List<ProviderPreset> providers;
  final List<MailAccount> accounts;
  final List<MailFolder> folders;
  final MailStats stats;
  final List<MailTag> tags;
  final List<MailRule> rules;
  final List<MailSignature> signatures;
  final List<MailMessage> messages;
  final int totalMessages;
  final MailMessage? selectedMessage;
  final Set<int> selectedIds;
  final String activeView; // inbox | starred | sent | drafts | archive | trash
  final int? activeAccountId;
  final int? activeFolderId;
  final int? activeTagId;
  final bool unreadOnly;
  final bool hasAttachments;
  final String searchQuery;
  final int page;
  final bool loadingList;
  final bool loadingDetail;
  final bool syncing;
  final String? toastMessage;

  const MailState({
    this.providers = const [],
    this.accounts = const [],
    this.folders = const [],
    this.stats = const MailStats(),
    this.tags = const [],
    this.rules = const [],
    this.signatures = const [],
    this.messages = const [],
    this.totalMessages = 0,
    this.selectedMessage,
    this.selectedIds = const {},
    this.activeView = 'inbox',
    this.activeAccountId,
    this.activeFolderId,
    this.activeTagId,
    this.unreadOnly = false,
    this.hasAttachments = false,
    this.searchQuery = '',
    this.page = 1,
    this.loadingList = false,
    this.loadingDetail = false,
    this.syncing = false,
    this.toastMessage,
  });

  MailState copyWith({
    List<ProviderPreset>? providers,
    List<MailAccount>? accounts,
    List<MailFolder>? folders,
    MailStats? stats,
    List<MailTag>? tags,
    List<MailRule>? rules,
    List<MailSignature>? signatures,
    List<MailMessage>? messages,
    int? totalMessages,
    MailMessage? selectedMessage,
    bool clearSelectedMessage = false,
    Set<int>? selectedIds,
    String? activeView,
    int? activeAccountId,
    bool clearActiveAccount = false,
    int? activeFolderId,
    bool clearActiveFolder = false,
    int? activeTagId,
    bool clearActiveTag = false,
    bool? unreadOnly,
    bool? hasAttachments,
    String? searchQuery,
    int? page,
    bool? loadingList,
    bool? loadingDetail,
    bool? syncing,
    String? toastMessage,
    bool clearToast = false,
  }) =>
      MailState(
        providers: providers ?? this.providers,
        accounts: accounts ?? this.accounts,
        folders: folders ?? this.folders,
        stats: stats ?? this.stats,
        tags: tags ?? this.tags,
        rules: rules ?? this.rules,
        signatures: signatures ?? this.signatures,
        messages: messages ?? this.messages,
        totalMessages: totalMessages ?? this.totalMessages,
        selectedMessage: clearSelectedMessage ? null : (selectedMessage ?? this.selectedMessage),
        selectedIds: selectedIds ?? this.selectedIds,
        activeView: activeView ?? this.activeView,
        activeAccountId: clearActiveAccount ? null : (activeAccountId ?? this.activeAccountId),
        activeFolderId: clearActiveFolder ? null : (activeFolderId ?? this.activeFolderId),
        activeTagId: clearActiveTag ? null : (activeTagId ?? this.activeTagId),
        unreadOnly: unreadOnly ?? this.unreadOnly,
        hasAttachments: hasAttachments ?? this.hasAttachments,
        searchQuery: searchQuery ?? this.searchQuery,
        page: page ?? this.page,
        loadingList: loadingList ?? this.loadingList,
        loadingDetail: loadingDetail ?? this.loadingDetail,
        syncing: syncing ?? this.syncing,
        toastMessage: clearToast ? null : (toastMessage ?? this.toastMessage),
      );
}

class MailNotifier extends Notifier<MailState> {
  StreamSubscription<SseEvent>? _sseSub;

  @override
  MailState build() {
    ref.onDispose(() {
      _sseSub?.cancel();
    });
    return const MailState();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> bootstrap() async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return;

    final sse = ref.read(sseClientProvider);
    sse.connect(auth.baseUrl, auth.token!);
    _sseSub?.cancel();
    _sseSub = sse.stream.listen(_handleSseEvent);

    await Future.wait([
      loadProviders(),
      refreshMetadata(),
      loadMessages(),
    ]);
  }

  void _handleSseEvent(SseEvent evt) {
    if (evt.type == 'sync_started') {
      state = state.copyWith(syncing: true);
    } else if (evt.type == 'sync_completed') {
      state = state.copyWith(syncing: false);
      refreshMetadata();
      loadMessages(silent: true);
    } else if (evt.type == 'new_messages') {
      state = state.copyWith(toastMessage: '${evt.label} 收到 ${evt.count} 封新邮件');
      refreshMetadata();
      loadMessages(silent: true);
    } else if (evt.type == 'sync_error') {
      state = state.copyWith(syncing: false, toastMessage: '${evt.label} 同步异常：${evt.message}');
      refreshMetadata();
    } else if (evt.type == 'data_changed') {
      refreshMetadata();
      loadMessages(silent: true);
    }
  }

  void clearToast() {
    state = state.copyWith(clearToast: true);
  }

  Future<void> loadProviders() async {
    try {
      final list = await _api.getProviders();
      state = state.copyWith(providers: list);
    } catch (_) {}
  }

  Future<void> refreshMetadata() async {
    try {
      final results = await Future.wait([
        _api.getAccounts(),
        _api.getFolders(),
        _api.getStats(),
        _api.getTags(),
        _api.getRules(),
        _api.getSignatures(),
      ]);
      state = state.copyWith(
        accounts: results[0] as List<MailAccount>,
        folders: results[1] as List<MailFolder>,
        stats: results[2] as MailStats,
        tags: results[3] as List<MailTag>,
        rules: results[4] as List<MailRule>,
        signatures: results[5] as List<MailSignature>,
      );
    } catch (_) {}
  }

  Future<void> loadMessages({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(loadingList: true);
    }
    try {
      final res = await _api.getMessages(
        view: state.activeView,
        accountId: state.activeAccountId,
        folderId: state.activeFolderId,
        tagId: state.activeTagId,
        unreadOnly: state.unreadOnly,
        hasAttachments: state.hasAttachments,
        q: state.searchQuery,
        page: state.page,
      );
      state = state.copyWith(
        messages: res.items,
        totalMessages: res.total,
        loadingList: false,
        selectedIds: {},
      );
    } catch (_) {
      state = state.copyWith(loadingList: false);
    }
  }

  Future<void> selectView(String view, {int? accountId}) async {
    state = state.copyWith(
      activeView: view,
      activeAccountId: accountId,
      clearActiveAccount: accountId == null,
      clearActiveFolder: true,
      clearActiveTag: true,
      page: 1,
      clearSelectedMessage: true,
    );
    await loadMessages();
  }

  Future<void> selectFolder(int accountId, int folderId) async {
    state = state.copyWith(
      activeView: 'folder',
      activeAccountId: accountId,
      activeFolderId: folderId,
      clearActiveTag: true,
      page: 1,
      clearSelectedMessage: true,
    );
    await loadMessages();
  }

  Future<void> selectTag(int tagId) async {
    state = state.copyWith(
      activeView: 'tag',
      activeTagId: tagId,
      clearActiveAccount: true,
      clearActiveFolder: true,
      page: 1,
      clearSelectedMessage: true,
    );
    await loadMessages();
  }

  Future<void> setFilters({bool? unreadOnly, bool? hasAttachments, String? q, int? page}) async {
    state = state.copyWith(
      unreadOnly: unreadOnly ?? state.unreadOnly,
      hasAttachments: hasAttachments ?? state.hasAttachments,
      searchQuery: q ?? state.searchQuery,
      page: page ?? 1,
    );
    await loadMessages();
  }

  Future<void> openMessage(int id) async {
    state = state.copyWith(loadingDetail: true);
    try {
      final msg = await _api.getMessage(id);
      if (!msg.isRead) {
        await _api.patchMessage(id, isRead: true);
        final updatedList = state.messages
            .map((m) => m.id == id ? _copyMessageRead(m, true) : m)
            .toList();
        state = state.copyWith(
          selectedMessage: _copyMessageRead(msg, true),
          messages: updatedList,
          loadingDetail: false,
        );
        unawaited(refreshMetadata());
      } else {
        state = state.copyWith(selectedMessage: msg, loadingDetail: false);
      }
    } catch (_) {
      state = state.copyWith(loadingDetail: false);
    }
  }

  void toggleSelectId(int id) {
    final next = Set<int>.from(state.selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = state.copyWith(selectedIds: next);
  }

  void selectAllVisible(bool select) {
    if (select) {
      state = state.copyWith(selectedIds: state.messages.map((e) => e.id).toSet());
    } else {
      state = state.copyWith(selectedIds: {});
    }
  }

  Future<void> toggleStar(MailMessage msg) async {
    final next = !msg.isStarred;
    await _api.patchMessage(msg.id, isStarred: next);
    await Future.wait([loadMessages(silent: true), refreshMetadata()]);
    if (state.selectedMessage?.id == msg.id) {
      final detail = await _api.getMessage(msg.id);
      state = state.copyWith(selectedMessage: detail);
    }
  }

  Future<void> toggleRead(MailMessage msg) async {
    final next = !msg.isRead;
    await _api.patchMessage(msg.id, isRead: next);
    await Future.wait([loadMessages(silent: true), refreshMetadata()]);
    if (state.selectedMessage?.id == msg.id) {
      final detail = await _api.getMessage(msg.id);
      state = state.copyWith(selectedMessage: detail);
    }
  }

  Future<void> moveMessage(int id, String role) async {
    await _api.patchMessage(id, moveRole: role);
    if (state.selectedMessage?.id == id) {
      state = state.copyWith(clearSelectedMessage: true);
    }
    await Future.wait([loadMessages(silent: true), refreshMetadata()]);
  }

  Future<void> deleteMessage(int id) async {
    await _api.deleteMessage(id);
    if (state.selectedMessage?.id == id) {
      state = state.copyWith(clearSelectedMessage: true);
    }
    await Future.wait([loadMessages(silent: true), refreshMetadata()]);
  }

  Future<void> toggleMessageTag(int msgId, int tagId, bool hasTag) async {
    if (hasTag) {
      await _api.patchMessage(msgId, removeTagId: tagId);
    } else {
      await _api.patchMessage(msgId, addTagId: tagId);
    }
    await loadMessages(silent: true);
    if (state.selectedMessage?.id == msgId) {
      final detail = await _api.getMessage(msgId);
      state = state.copyWith(selectedMessage: detail);
    }
  }

  Future<void> runBatch(String action, {int? tagId}) async {
    if (state.selectedIds.isEmpty) return;
    await _api.batchMessages(state.selectedIds.toList(), action, tagId: tagId);
    state = state.copyWith(selectedIds: {}, clearSelectedMessage: action == 'delete' || action == 'archive');
    await Future.wait([loadMessages(silent: true), refreshMetadata()]);
  }

  Future<void> syncAllAccounts() async {
    if (state.accounts.isEmpty) return;
    state = state.copyWith(syncing: true);
    for (final a in state.accounts) {
      try {
        await _api.syncAccount(a.id);
      } catch (_) {}
    }
    state = state.copyWith(toastMessage: '已触发全部邮箱同步');
  }

  Future<void> syncSingleAccount(int accountId) async {
    state = state.copyWith(syncing: true);
    try {
      await _api.syncAccount(accountId);
    } catch (_) {
      state = state.copyWith(syncing: false);
    }
  }

  MailMessage _copyMessageRead(MailMessage m, bool read) => MailMessage(
        id: m.id,
        accountId: m.accountId,
        accountLabel: m.accountLabel,
        accountEmail: m.accountEmail,
        accountColor: m.accountColor,
        folderId: m.folderId,
        folderRole: m.folderRole,
        folderName: m.folderName,
        messageIdHeader: m.messageIdHeader,
        inReplyTo: m.inReplyTo,
        subject: m.subject,
        fromName: m.fromName,
        fromAddr: m.fromAddr,
        toAddrs: m.toAddrs,
        ccAddrs: m.ccAddrs,
        bccAddrs: m.bccAddrs,
        snippet: m.snippet,
        bodyText: m.bodyText,
        bodyHtml: m.bodyHtml,
        isRead: read,
        isStarred: m.isStarred,
        isDraft: m.isDraft,
        hasAttachments: m.hasAttachments,
        sentAt: m.sentAt,
        receivedAt: m.receivedAt,
        tags: m.tags,
        attachments: m.attachments,
      );
}

final mailProvider = NotifierProvider<MailNotifier, MailState>(MailNotifier.new);
