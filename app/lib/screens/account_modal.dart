import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers/mail_provider.dart';
import '../widgets/brand_widgets.dart';

class AccountModal extends ConsumerStatefulWidget {
  final MailAccount? existing;
  final bool isDialog;

  const AccountModal({super.key, this.existing, this.isDialog = false});

  @override
  ConsumerState<AccountModal> createState() => _AccountModalState();
}

class _AccountModalState extends ConsumerState<AccountModal> {
  static const _colors = [
    '#2563eb',
    '#16a34a',
    '#dc2626',
    '#d97706',
    '#7c3aed',
    '#0891b2',
    '#db2777',
    '#4f46e5',
  ];

  final _labelCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _imapHostCtrl = TextEditingController();
  final _imapPortCtrl = TextEditingController(text: '993');
  final _smtpHostCtrl = TextEditingController();
  final _smtpPortCtrl = TextEditingController(text: '465');
  final _intervalCtrl = TextEditingController(text: '180');

  String _providerId = 'qq';
  String _imapTls = 'ssl';
  String _smtpTls = 'ssl';
  String _color = '#2563eb';
  bool _isDefault = false;
  bool _syncEnabled = true;
  bool _showAdvanced = false;
  bool _testing = false;
  bool _saving = false;
  Map<String, dynamic>? _testResult;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _labelCtrl.text = e.label;
      _emailCtrl.text = e.emailAddress;
      _usernameCtrl.text = e.username;
      _imapHostCtrl.text = e.imapHost;
      _imapPortCtrl.text = e.imapPort.toString();
      _smtpHostCtrl.text = e.smtpHost;
      _smtpPortCtrl.text = e.smtpPort.toString();
      _intervalCtrl.text = e.syncIntervalSec.toString();
      _providerId = e.providerId;
      _imapTls = e.imapTls;
      _smtpTls = e.smtpTls;
      _color = e.color;
      _isDefault = e.isDefault;
      _syncEnabled = e.syncEnabled;
      _showAdvanced = true;
    } else {
      Future.microtask(() {
        final presets = ref.read(mailProvider).providers;
        if (presets.isNotEmpty) {
          _applyPreset(presets.first);
        }
      });
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _imapHostCtrl.dispose();
    _imapPortCtrl.dispose();
    _smtpHostCtrl.dispose();
    _smtpPortCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(ProviderPreset p) {
    setState(() {
      _providerId = p.id;
      if (_labelCtrl.text.trim().isEmpty || widget.existing == null) {
        _labelCtrl.text = p.id == 'custom' ? '' : p.name;
      }
      _imapHostCtrl.text = p.imapHost;
      _imapPortCtrl.text = p.imapPort.toString();
      _imapTls = p.imapTls;
      _smtpHostCtrl.text = p.smtpHost;
      _smtpPortCtrl.text = p.smtpPort.toString();
      _smtpTls = p.smtpTls;
      if (p.id == 'custom') {
        _showAdvanced = true;
      }
    });
  }

  void _onEmailChanged(String value) {
    if (widget.existing != null) return;
    final parts = value.trim().toLowerCase().split('@');
    if (parts.length == 2 && parts[1].isNotEmpty) {
      final presets = ref.read(mailProvider).providers;
      for (final p in presets) {
        if (p.domains.contains(parts[1])) {
          _applyPreset(p);
          break;
        }
      }
    }
  }

  Map<String, dynamic> _buildPayload() => {
        if (widget.existing != null) 'account_id': widget.existing!.id,
        'label': _labelCtrl.text.trim(),
        'email_address': _emailCtrl.text.trim(),
        'provider_id': _providerId,
        'imap_host': _imapHostCtrl.text.trim(),
        'imap_port': int.tryParse(_imapPortCtrl.text.trim()) ?? 993,
        'imap_tls': _imapTls,
        'smtp_host': _smtpHostCtrl.text.trim(),
        'smtp_port': int.tryParse(_smtpPortCtrl.text.trim()) ?? 465,
        'smtp_tls': _smtpTls,
        'username': _usernameCtrl.text.trim().isEmpty ? _emailCtrl.text.trim() : _usernameCtrl.text.trim(),
        'password': _passwordCtrl.text,
        'color': _color,
        'is_default': _isDefault,
        'sync_enabled': _syncEnabled,
        'sync_interval_sec': int.tryParse(_intervalCtrl.text.trim()) ?? 180,
      };

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final res = await ref.read(apiClientProvider).testAccount(_buildPayload());
      if (mounted) setState(() => _testResult = res);
    } catch (e) {
      if (mounted) {
        setState(() => _testResult = {
              'success': false,
              'message': ref.read(apiClientProvider).extractError(e),
            });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (_emailCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写邮箱地址')));
      return;
    }
    if (widget.existing == null && _passwordCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写邮箱授权码或密码')));
      return;
    }

    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      if (widget.existing != null) {
        await api.updateAccount(widget.existing!.id, _buildPayload());
      } else {
        await api.createAccount(_buildPayload());
      }
      await Future.wait([
        ref.read(mailProvider.notifier).refreshMetadata(),
        ref.read(mailProvider.notifier).loadMessages(silent: true),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.existing != null ? '邮箱配置已更新' : '邮箱添加成功，正在后台同步邮件')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(apiClientProvider).extractError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除邮箱'),
        content: Text('确定移除 ${widget.existing!.emailAddress} 吗？该操作会清理本地缓存的邮件数据。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(apiClientProvider).deleteAccount(widget.existing!.id);
    await Future.wait([
      ref.read(mailProvider.notifier).refreshMetadata(),
      ref.read(mailProvider.notifier).loadMessages(),
    ]);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(mailProvider).providers;
    final currentPreset = presets.where((p) => p.id == _providerId).firstOrNull;
    final scheme = Theme.of(context).colorScheme;

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
          child: Row(
            children: [
              Text(
                widget.existing != null ? '编辑邮箱账号' : '添加主流邮箱账号',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (widget.existing != null)
                TextButton.icon(
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: scheme.error, size: 18),
                  label: Text('删除', style: TextStyle(color: scheme.error)),
                ),
              if (widget.isDialog)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (presets.isNotEmpty) ...[
                  const Text('选择邮箱服务商（输入邮箱可自动识别）', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in presets)
                        ChoiceChip(
                          label: Text(p.name, style: const TextStyle(fontSize: 12.5)),
                          selected: _providerId == p.id,
                          onSelected: (_) => _applyPreset(p),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (currentPreset != null && currentPreset.authTip.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentPreset.authTip,
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailCtrl,
                        onChanged: _onEmailChanged,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: '邮箱地址 *', hintText: 'example@qq.com'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _labelCtrl,
                        decoration: const InputDecoration(labelText: '账号备注名称', hintText: '如：个人QQ / 工作邮箱'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: widget.existing != null ? '授权码 / 密码（留空则保持不变）' : '授权码 / 应用专用密码 *',
                    hintText: '填入邮箱授权码而非网页登录密码',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('账号标识色：', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    for (final c in _colors)
                      GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: parseHexColor(c),
                            shape: BoxShape.circle,
                            border: _color == c ? Border.all(color: scheme.onSurface, width: 2.5) : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('设为默认发件邮箱', style: TextStyle(fontSize: 14)),
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开启后台自动定时同步', style: TextStyle(fontSize: 14)),
                  value: _syncEnabled,
                  onChanged: (v) => setState(() => _syncEnabled = v),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                  icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
                  label: const Text('IMAP / SMTP 服务器高级设置'),
                ),
                if (_showAdvanced) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(labelText: '登录用户名（通常与邮箱地址相同）', isDense: true),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _imapHostCtrl,
                          decoration: const InputDecoration(labelText: 'IMAP 服务器', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _imapPortCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '端口', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: AppDropdownField<String>(
                          value: _imapTls,
                          decoration: const InputDecoration(labelText: '加密', isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'ssl', child: Text('SSL/TLS')),
                            DropdownMenuItem(value: 'starttls', child: Text('STARTTLS')),
                            DropdownMenuItem(value: 'none', child: Text('无')),
                          ],
                          onChanged: (v) => setState(() => _imapTls = v ?? 'ssl'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _smtpHostCtrl,
                          decoration: const InputDecoration(labelText: 'SMTP 服务器', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _smtpPortCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '端口', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: AppDropdownField<String>(
                          value: _smtpTls,
                          decoration: const InputDecoration(labelText: '加密', isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'ssl', child: Text('SSL/TLS')),
                            DropdownMenuItem(value: 'starttls', child: Text('STARTTLS')),
                            DropdownMenuItem(value: 'none', child: Text('无')),
                          ],
                          onChanged: (v) => setState(() => _smtpTls = v ?? 'ssl'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _intervalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '自动同步间隔（秒，最小 30）', isDense: true),
                  ),
                ],
                if (_testResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_testResult!['success'] == true ? Colors.green : scheme.error).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (_testResult!['success'] == true ? Colors.green : scheme.error).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      (_testResult!['message'] ?? '').toString(),
                      style: TextStyle(
                        fontSize: 13,
                        color: _testResult!['success'] == true ? Colors.green.shade800 : scheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering_rounded, size: 18),
                label: const Text('测试连接'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('保存邮箱'),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.isDialog) return content;
    return Scaffold(body: SafeArea(child: content));
  }
}
