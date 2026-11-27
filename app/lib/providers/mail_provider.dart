import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../core/api_client.dart';
import '../core/local_server_manager.dart';
import '../core/notification_service.dart';
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
  final List<String> savedServers;
  final String? token;
  final AppUser? user;
  final ThemeMode themeMode;
  final String? error;

  const AuthState({
    this.initialized = false,
    this.loading = false,
    this.baseUrl = 'http://127.0.0.1:8080',
    this.savedServers = const ['http://127.0.0.1:8080'],
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
    List<String>? savedServers,
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
        savedServers: savedServers ?? this.savedServers,
        token: clearToken ? null : (token ?? this.token),
        user: clearUser ? null : (user ?? this.user),
        themeMode: themeMode ?? this.themeMode,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuthNotifier extends Notifier<AuthState> {
  static const _kBaseUrl = 'mailcontrol_base_url';
  static const _kSavedServers = 'mailcontrol_saved_servers';
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
    final rawServers = prefs.getStringList(_kSavedServers) ?? const [];
    final serverList = <String>[
      savedUrl,
      for (final s in rawServers)
        if (s.trim().isNotEmpty && s.trim() != savedUrl) s.trim(),
      if (savedUrl != 'http://127.0.0.1:8080' && !rawServers.contains('http://127.0.0.1:8080'))
        'http://127.0.0.1:8080',
    ];
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
        unawaited(ref.read(notificationServiceProvider).stopAndroidPushService());
      }
    } else {
      unawaited(ref.read(notificationServiceProvider).stopAndroidPushService());
    }

    state = state.copyWith(
      initialized: true,
      baseUrl: savedUrl,
      savedServers: serverList,
      token: validToken,
      clearToken: validToken == null,
      user: user,
      clearUser: user == null,
      themeMode: themeMode,
    );
  }

  Future<void> setBaseUrl(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, normalized);
    ref.read(apiClientProvider).configure(baseUrl: normalized, token: state.token);
    state = state.copyWith(baseUrl: normalized, clearError: true);
  }

  Future<void> rememberServer(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return;
    final next = <String>[
      normalized,
      for (final s in state.savedServers)
        if (s != normalized) s,
    ];
    if (next.length > 8) next.removeRange(8, next.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSavedServers, next);
    state = state.copyWith(savedServers: next);
  }

  Future<void> removeSavedServer(String url) async {
    final next = state.savedServers.where((s) => s != url).toList();
    if (next.isEmpty) next.add('http://127.0.0.1:8080');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSavedServers, next);
    state = state.copyWith(savedServers: next);
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
      await rememberServer(state.baseUrl);
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
      await rememberServer(state.baseUrl);
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
    unawaited(ref.read(notificationServiceProvider).stopAndroidPushService());
    ref.read(mailProvider.notifier).resetNotificationState();
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
  final int? openingMessageId;
  final bool syncing;
  final String? toastMessage;
  final int? pendingOpenMessageId;

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
    this.openingMessageId,
    this.syncing = false,
    this.toastMessage,
    this.pendingOpenMessageId,
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
    int? openingMessageId,
    bool clearOpeningMessageId = false,
    bool? syncing,
    String? toastMessage,
    bool clearToast = false,
    int? pendingOpenMessageId,
    bool clearPendingOpenMessageId = false,
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
        openingMessageId: clearOpeningMessageId ? null : (openingMessageId ?? this.openingMessageId),
        syncing: syncing ?? this.syncing,
        toastMessage: clearToast ? null : (toastMessage ?? this.toastMessage),
        pendingOpenMessageId: clearPendingOpenMessageId
            ? null
            : (pendingOpenMessageId ?? this.pendingOpenMessageId),
      );
}

class MailNotifier extends Notifier<MailState> {
  StreamSubscription<SseEvent>? _sseSub;
  Timer? _fallbackPollTimer;
  bool _notifBaselineReady = false;
  int _highestSeenInboxId = 0;
  final Set<int> _notifiedIds = <int>{};
  bool _pollingNewMessages = false;
  int _openSeq = 0;

  @override
  MailState build() {
    ref.onDispose(() {
      _sseSub?.cancel();
      _fallbackPollTimer?.cancel();
    });
    return const MailState();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  void resetNotificationState() {
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = null;
    _notifBaselineReady = false;
    _highestSeenInboxId = 0;
    _notifiedIds.clear();
  }

  Future<void> bootstrap() async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return;

    final notif = ref.read(notificationServiceProvider);
    await notif.init(onTap: _handleNotificationTap);
    if (Platform.isAndroid) {
      await notif.requestPermissionIfNeeded();
      await notif.startAndroidPushService(baseUrl: auth.baseUrl, token: auth.token!);
      final pendingId = await notif.consumePendingAndroidMessageId();
      if (pendingId != null && pendingId > 0) {
        _handleNotificationTap('msg:$pendingId');
      }
    } else {
      unawaited(notif.requestPermissionIfNeeded());
    }

    final sse = ref.read(sseClientProvider);
    sse.connect(auth.baseUrl, auth.token!);
    _sseSub?.cancel();
    _sseSub = sse.stream.listen(_handleSseEvent);

    await Future.wait([
      loadProviders(),
      refreshMetadata(),
      loadMessages(),
    ]);

    await _initNotificationBaseline();
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _pollNewInboxMessages(),
    );
  }

  Future<void> _initNotificationBaseline() async {
    if (!ref.read(authProvider).isAuthenticated) return;
    try {
      final res = await _api.getMessages(view: 'inbox', page: 1, pageSize: 20);
      for (final m in res.items) {
        if (m.id > _highestSeenInboxId) {
          _highestSeenInboxId = m.id;
        }
      }
    } catch (_) {
      for (final m in state.messages) {
        if (m.id > _highestSeenInboxId) {
          _highestSeenInboxId = m.id;
        }
      }
    } finally {
      _notifBaselineReady = true;
    }
  }

  void _handleSseEvent(SseEvent evt) {
    if (evt.type == 'sync_started') {
      state = state.copyWith(syncing: true);
    } else if (evt.type == 'sync_completed') {
      state = state.copyWith(syncing: false);
      refreshMetadata();
      loadMessages(silent: true);
    } else if (evt.type == 'new_messages') {
      if (!ref.read(authProvider).isAuthenticated) return;
      state = state.copyWith(toastMessage: '${evt.label} 收到 ${evt.count} 封新邮件');
      refreshMetadata();
      loadMessages(silent: true);
      unawaited(_notifyFromSseNewMessages(evt));
    } else if (evt.type == 'sync_error') {
      state = state.copyWith(syncing: false, toastMessage: '${evt.label} 同步异常：${evt.message}');
      refreshMetadata();
    } else if (evt.type == 'data_changed') {
      refreshMetadata();
      loadMessages(silent: true);
    }
  }

  Future<void> _notifyFromSseNewMessages(SseEvent evt) async {
    if (!ref.read(authProvider).isAuthenticated) return;
    final notif = ref.read(notificationServiceProvider);
    if (Platform.isAndroid && notif.androidPushServiceActive) {
      return;
    }
    List<MailMessage> fresh = const [];
    try {
      final res = await _api.getMessages(
        view: 'inbox',
        accountId: evt.accountId > 0 ? evt.accountId : null,
        page: 1,
        pageSize: 5,
      );
      if (!ref.read(authProvider).isAuthenticated) return;
      fresh = res.items
          .where((m) => m.id > _highestSeenInboxId && !_notifiedIds.contains(m.id))
          .toList();
      for (final m in fresh) {
        if (m.id > _highestSeenInboxId) _highestSeenInboxId = m.id;
        _notifiedIds.add(m.id);
      }
    } catch (_) {}

    if (fresh.isEmpty && evt.count <= 0) return;

    final content = buildNewMailNotificationContent(
      accountLabel: evt.label,
      freshMessages: fresh,
      fallbackCount: evt.count,
    );
    final notifId = fresh.isNotEmpty
        ? fresh.first.id
        : (DateTime.now().millisecondsSinceEpoch & 0x7fffffff);
    await notif.showNewMailNotification(
          id: notifId,
          title: content.title,
          body: content.body,
          payload: content.payload,
        );
  }

  Future<void> _pollNewInboxMessages() async {
    if (_pollingNewMessages || !_notifBaselineReady || !ref.read(authProvider).isAuthenticated) {
      return;
    }
    _pollingNewMessages = true;
    try {
      final res = await _api.getMessages(view: 'inbox', page: 1, pageSize: 15);
      if (!ref.read(authProvider).isAuthenticated) return;

      final freshUnread = res.items
          .where((m) => !m.isRead && m.id > _highestSeenInboxId && !_notifiedIds.contains(m.id))
          .toList();
      for (final m in res.items) {
        if (m.id > _highestSeenInboxId) {
          _highestSeenInboxId = m.id;
        }
      }
      for (final m in freshUnread) {
        _notifiedIds.add(m.id);
      }

      if (freshUnread.isNotEmpty) {
        final notif = ref.read(notificationServiceProvider);
        if (!(Platform.isAndroid && notif.androidPushServiceActive)) {
          final content = buildNewMailNotificationContent(
            accountLabel: freshUnread.first.accountLabel,
            freshMessages: freshUnread,
          );
          await notif.showNewMailNotification(
                id: freshUnread.first.id,
                title: content.title,
                body: content.body,
                payload: content.payload,
              );
        }
        unawaited(refreshMetadata());
        unawaited(loadMessages(silent: true));
      }
    } catch (_) {
    } finally {
      _pollingNewMessages = false;
    }
  }

  void _handleNotificationTap(String? payload) {
    if (Platform.isWindows) {
      try {
        WindowManager.instance.getCurrent()?.show();
      } catch (_) {}
    }
    if (!ref.read(authProvider).isAuthenticated) return;
    if (payload != null && payload.startsWith('msg:')) {
      final id = int.tryParse(payload.substring(4));
      if (id != null) {
        unawaited(openMessage(id));
        if (!Platform.isWindows) {
          state = state.copyWith(pendingOpenMessageId: id);
        }
      }
    }
  }

  void clearPendingOpenMessageId() {
    state = state.copyWith(clearPendingOpenMessageId: true);
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
      var stats = results[2] as MailStats;
      final tags = results[3] as List<MailTag>;
      if (!stats.hasTagCounts && tags.isNotEmpty) {
        final fallbackCounts = <int, int>{};
        await Future.wait(
          tags.map((t) async {
            try {
              final r = await _api.getMessages(
                view: 'tag',
                tagId: t.id,
                unreadOnly: true,
                page: 1,
                pageSize: 1,
              );
              fallbackCounts[t.id] = r.total;
            } catch (_) {}
          }),
        );
        stats = stats.copyWith(tagUnread: fallbackCounts);
      }
      state = state.copyWith(
        accounts: results[0] as List<MailAccount>,
        folders: results[1] as List<MailFolder>,
        stats: stats,
        tags: tags,
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
    if (state.loadingDetail && state.openingMessageId == id) return;
    final seq = ++_openSeq;
    state = state.copyWith(loadingDetail: true, openingMessageId: id);
    try {
      final msg = await _api.getMessage(id);
      if (seq != _openSeq) return;
      if (!msg.isRead) {
        final updatedList = state.messages
            .map((m) => m.id == id ? _copyMessageRead(m, true) : m)
            .toList();
        state = state.copyWith(
          selectedMessage: _copyMessageRead(msg, true),
          messages: updatedList,
          loadingDetail: false,
          clearOpeningMessageId: true,
        );
        unawaited(_markMessageReadInBackground(id));
      } else {
        state = state.copyWith(
          selectedMessage: msg,
          loadingDetail: false,
          clearOpeningMessageId: true,
        );
      }
    } catch (_) {
      if (seq != _openSeq) return;
      state = state.copyWith(
        loadingDetail: false,
        clearOpeningMessageId: true,
        toastMessage: '加载邮件失败，请稍后重试',
      );
    }
  }

  Future<void> _markMessageReadInBackground(int id) async {
    try {
      await _api.patchMessage(id, isRead: true);
      await refreshMetadata();
    } catch (_) {}
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
    await Future.wait([loadMessages(silent: true), refreshMetadata()]);
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

  Future<void> renameAccount(MailAccount acct, String newLabel) async {
    final trimmed = newLabel.trim();
    if (trimmed.isEmpty || trimmed == acct.label) return;
    await _api.updateAccount(acct.id, {
      'account_id': acct.id,
      'label': trimmed,
      'email_address': acct.emailAddress,
      'provider_id': acct.providerId,
      'imap_host': acct.imapHost,
      'imap_port': acct.imapPort,
      'imap_tls': acct.imapTls,
      'smtp_host': acct.smtpHost,
      'smtp_port': acct.smtpPort,
      'smtp_tls': acct.smtpTls,
      'username': acct.username.isEmpty ? acct.emailAddress : acct.username,
      'password': '',
      'color': acct.color,
      'is_default': acct.isDefault,
      'sync_enabled': acct.syncEnabled,
      'sync_interval_sec': acct.syncIntervalSec,
    });
    await Future.wait([refreshMetadata(), loadMessages(silent: true)]);
    await refreshSelectedIfAccount(acct.id);
    state = state.copyWith(toastMessage: '邮箱名称已更新为「$trimmed」');
  }

  Future<void> refreshSelectedIfAccount(int accountId) async {
    final selected = state.selectedMessage;
    if (selected != null && selected.accountId == accountId) {
      try {
        final detail = await _api.getMessage(selected.id);
        state = state.copyWith(selectedMessage: detail);
      } catch (_) {}
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
