import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../providers/mail_provider.dart';
import '../widgets/brand_widgets.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isRegister = false;
  bool _showServerConfig = false;
  bool _obscurePassword = true;
  bool _checkingServer = false;
  String? _serverStatus;
  bool _serverOk = false;

  final _serverCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _serverCtrl.text = ref.read(authProvider).baseUrl;
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkServer() async {
    setState(() {
      _checkingServer = true;
      _serverStatus = null;
    });
    final url = _serverCtrl.text.trim();
    await ref.read(authProvider.notifier).setBaseUrl(url);
    final ok = await ref.read(apiClientProvider).checkHealth(url);
    if (ok) {
      await ref.read(authProvider.notifier).rememberServer(url);
    }
    if (!mounted) return;
    setState(() {
      _checkingServer = false;
      _serverOk = ok;
      _serverStatus = ok ? '后端服务连接正常（已记录到常用地址）' : '无法连接到该地址，请确认后端已启动或端口已放行';
    });
  }

  Future<void> _startLocalServer() async {
    setState(() {
      _checkingServer = true;
      _serverStatus = '正在启动本地后端服务...';
    });
    final mgr = ref.read(localServerProvider);
    final started = await mgr.startIfNeeded();
    if (!started) {
      if (!mounted) return;
      setState(() {
        _checkingServer = false;
        _serverOk = false;
        _serverStatus = '未找到 mailcontrol-server.exe，请先编译或填入云端服务器地址';
      });
      return;
    }
    _serverCtrl.text = 'http://127.0.0.1:8080';
    await _checkServer();
    if (mounted && _serverOk) {
      setState(() {
        _serverStatus = '本地服务连接正常（提示：本地数据库与云端账号相互独立，首次使用请先注册本地账号）';
      });
    }
  }

  Future<void> _submit() async {
    final url = _serverCtrl.text.trim();
    if (url.isNotEmpty) {
      await ref.read(authProvider.notifier).setBaseUrl(url);
    }

    final notifier = ref.read(authProvider.notifier);
    if (_isRegister) {
      await notifier.register(
        _usernameCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
    } else {
      await notifier.login(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final localMgr = ref.watch(localServerProvider);
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: p.readingBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 840;
            final formCard = _buildFormPanel(context, auth, localMgr, p, scheme);

            if (!isWide) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.surfaceElevated,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: p.borderSubtle),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: formCard,
                    ),
                  ),
                ),
              );
            }

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Container(
                  width: 880,
                  decoration: BoxDecoration(
                    color: p.surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: p.borderSubtle),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                        blurRadius: 36,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: _buildBrandPanel(context)),
                        Expanded(
                          flex: 6,
                          child: Padding(
                            padding: const EdgeInsets.all(34),
                            child: formCard,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(34),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF1D4ED8), Color(0xFF2563EB)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MailControlLogo(size: 46),
          const SizedBox(height: 24),
          const Text(
            'MailControl',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '一个账号，在 Windows 与手机端统一管理所有主流邮箱。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 28),
          const _FeatureLine(icon: Icons.all_inbox_rounded, text: '统一收件箱聚合 QQ / 163 / Gmail / Outlook 等 12 类邮箱'),
          const SizedBox(height: 14),
          const _FeatureLine(icon: Icons.devices_rounded, text: '电脑与手机端同一账号实时同步，配置与邮件零重复录入'),
          const SizedBox(height: 14),
          const _FeatureLine(icon: Icons.translate_rounded, text: '内置多渠道免费翻译插件，支持读信与写信一键翻译'),
          const SizedBox(height: 14),
          const _FeatureLine(icon: Icons.verified_user_outlined, text: 'AES-256-GCM 授权码加密存储与自动分类规则引擎'),
        ],
      ),
    );
  }

  Widget _buildFormPanel(
    BuildContext context,
    AuthState auth,
    dynamic localMgr,
    AppPalette p,
    ColorScheme scheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (MediaQuery.of(context).size.width < 840) ...[
              const MailControlLogo(size: 38),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isRegister ? '创建 MailControl 账号' : '登录工作台',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '连接服务器：${auth.baseUrl}',
                    style: TextStyle(fontSize: 12, color: p.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _showServerConfig = !_showServerConfig),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: _showServerConfig ? p.accentSoft : p.hoverBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _showServerConfig ? p.accent.withValues(alpha: 0.4) : p.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dns_outlined, size: 16, color: _showServerConfig ? p.accent : p.textSecondary),
                    const SizedBox(width: 5),
                    Text(
                      '服务器',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _showServerConfig ? p.accent : p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_showServerConfig) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.readingBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '后端服务地址（填写你的服务器地址或局域网地址）',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textSecondary),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _serverCtrl,
                  decoration: const InputDecoration(
                    hintText: 'http://服务器IP:18080 或 https://域名',
                    isDense: true,
                  ),
                ),
                if (auth.savedServers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('常用地址（点击快速切换）', style: TextStyle(fontSize: 11.5, color: p.textMuted)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in auth.savedServers)
                        InputChip(
                          label: Text(
                            s,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: s == auth.baseUrl ? FontWeight.w600 : FontWeight.w400,
                              color: s == auth.baseUrl ? p.accent : p.textPrimary,
                            ),
                          ),
                          selected: s == auth.baseUrl,
                          showCheckmark: false,
                          selectedColor: p.accentSoft,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _serverCtrl.text = s;
                            _checkServer();
                          },
                          onDeleted: auth.savedServers.length > 1
                              ? () => ref.read(authProvider.notifier).removeSavedServer(s)
                              : null,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _checkingServer ? null : _checkServer,
                      icon: const Icon(Icons.network_check_rounded, size: 17),
                      label: const Text('测试连接'),
                    ),
                    if (localMgr.isSupported)
                      FilledButton.tonalIcon(
                        onPressed: _checkingServer ? null : _startLocalServer,
                        icon: const Icon(Icons.play_arrow_rounded, size: 17),
                        label: const Text('一键启动本地服务'),
                      ),
                  ],
                ),
                if (_serverStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _serverStatus!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _serverOk ? const Color(0xFF059669) : scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('登录')),
            ButtonSegment(value: true, label: Text('注册账号')),
          ],
          selected: {_isRegister},
          onSelectionChanged: (v) => setState(() => _isRegister = v.first),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _usernameCtrl,
          decoration: InputDecoration(
            labelText: _isRegister ? '用户名' : '用户名或邮箱',
            prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
          ),
          textInputAction: TextInputAction.next,
        ),
        if (_isRegister) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '系统账号标识邮箱（仅作登录标识）',
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
            ),
            textInputAction: TextInputAction.next,
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          onSubmitted: (_) => auth.loading ? null : _submit(),
          decoration: InputDecoration(
            labelText: _isRegister ? '密码（至少 6 位）' : '密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
            ),
          ),
        ),
        if (auth.error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              auth.error!,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: auth.loading ? null : _submit,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: auth.loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isRegister ? '注册并进入工作台' : '登录'),
        ),
      ],
    );
  }
}

class _FeatureLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.92)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.90),
              fontSize: 12.8,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
