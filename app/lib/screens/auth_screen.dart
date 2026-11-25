import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../providers/mail_provider.dart';

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
    if (!mounted) return;
    setState(() {
      _checkingServer = false;
      _serverOk = ok;
      _serverStatus = ok ? '后端服务连接正常' : '无法连接到该地址，请确认后端已启动';
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
        _serverStatus = '未找到 mailcontrol-server.exe，请先编译或手动启动后端';
      });
      return;
    }
    _serverCtrl.text = 'http://127.0.0.1:8080';
    await _checkServer();
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.mark_email_read_rounded, color: scheme.primary, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MailControl',
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                Text(
                                  '一个账号，统一管理所有主流邮箱',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '服务器设置',
                            onPressed: () => setState(() => _showServerConfig = !_showServerConfig),
                            icon: Icon(
                              Icons.dns_outlined,
                              color: _showServerConfig ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_showServerConfig) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '后端服务器地址（手机端请填电脑局域网 IP）',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _serverCtrl,
                                decoration: const InputDecoration(
                                  hintText: 'http://192.168.1.100:8080',
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _checkingServer ? null : _checkServer,
                                    icon: const Icon(Icons.network_check, size: 18),
                                    label: const Text('测试连接'),
                                  ),
                                  if (localMgr.isSupported)
                                    FilledButton.tonalIcon(
                                      onPressed: _checkingServer ? null : _startLocalServer,
                                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                      label: const Text('一键启动本地服务'),
                                    ),
                                ],
                              ),
                              if (_serverStatus != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _serverStatus!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _serverOk ? Colors.green : scheme.error,
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
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      if (_isRegister) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: '系统通知邮箱',
                            prefixIcon: Icon(Icons.email_outlined),
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
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          ),
                        ),
                      ),
                      if (auth.error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            auth.error!,
                            style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: auth.loading ? null : _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: auth.loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isRegister ? '注册并进入工作台' : '登录'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '当前连接：${auth.baseUrl}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
