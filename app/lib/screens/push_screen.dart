import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers/mail_provider.dart';
import '../widgets/brand_widgets.dart';

class PushScreen extends ConsumerStatefulWidget {
  final bool isDialog;
  const PushScreen({super.key, this.isDialog = false});

  @override
  ConsumerState<PushScreen> createState() => _PushScreenState();
}

class _PushScreenState extends ConsumerState<PushScreen> {
  List<PushChannel> _channels = const [];
  bool _loading = true;
  int? _testingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(apiClientProvider).getPushChannels();
      if (mounted) {
        setState(() {
          _channels = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(apiClientProvider).extractError(e))),
        );
      }
    }
  }

  String _typeLabel(String type) => switch (type) {
        'feishu' => '飞书群机器人',
        'feishu_app' => '飞书应用机器人',
        'wecom' => '企业微信机器人',
        'dingtalk' => '钉钉机器人',
        'webhook' => '自定义 Webhook',
        _ => type,
      };

  Color _typeColor(String type) => switch (type) {
        'feishu' || 'feishu_app' => const Color(0xFF00B96B),
        'wecom' => const Color(0xFF07C160),
        'dingtalk' => const Color(0xFF007FFF),
        _ => const Color(0xFF6366F1),
      };

  Future<void> _openEditor([PushChannel? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '飞书收信提醒');
    final webhookCtrl = TextEditingController(text: existing?.webhookUrl ?? '');
    final secretCtrl = TextEditingController();
    final appIdCtrl = TextEditingController(text: existing?.appId ?? '');
    final targetIdCtrl = TextEditingController(text: existing?.targetId ?? '');
    String channelType = existing?.channelType ?? 'feishu';
    String targetIdType = existing?.targetIdType ?? 'open_id';
    bool enabled = existing?.enabled ?? true;
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final p = ctx.palette;
          return AlertDialog(
            title: Text(existing != null ? '编辑推送通道' : '添加推送通道'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '通道名称 *',
                        hintText: '如：我的飞书提醒',
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppDropdownField<String>(
                      value: channelType,
                      decoration: const InputDecoration(labelText: '推送方式', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'feishu', child: Text('飞书群机器人 (Webhook，最简单)')),
                        DropdownMenuItem(value: 'feishu_app', child: Text('飞书自建应用机器人 (私聊 / 群聊)')),
                        DropdownMenuItem(value: 'wecom', child: Text('企业微信群机器人')),
                        DropdownMenuItem(value: 'dingtalk', child: Text('钉钉群机器人')),
                        DropdownMenuItem(value: 'webhook', child: Text('自定义通用 Webhook')),
                      ],
                      onChanged: (v) => setModalState(() {
                        channelType = v ?? 'feishu';
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (channelType == 'feishu_app') ...[
                      TextField(
                        controller: appIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'App ID *',
                          hintText: '如：cli_a1b2c3d4e5f6',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: secretCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: (existing != null && existing.hasSecret)
                              ? 'App Secret（留空保持不变）'
                              : 'App Secret *',
                          hintText: '飞书开放平台应用凭证密钥',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: AppDropdownField<String>(
                              value: targetIdType,
                              decoration: const InputDecoration(labelText: '接收者类型', isDense: true),
                              items: const [
                                DropdownMenuItem(value: 'open_id', child: Text('open_id')),
                                DropdownMenuItem(value: 'chat_id', child: Text('chat_id')),
                                DropdownMenuItem(value: 'user_id', child: Text('user_id')),
                                DropdownMenuItem(value: 'email', child: Text('email')),
                              ],
                              onChanged: (v) => setModalState(() => targetIdType = v ?? 'open_id'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: targetIdCtrl,
                              decoration: const InputDecoration(
                                labelText: '接收者 ID *',
                                hintText: 'ou_xxxx 或 oc_xxxx',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      TextField(
                        controller: webhookCtrl,
                        decoration: InputDecoration(
                          labelText: 'Webhook 地址 *',
                          hintText: channelType == 'feishu'
                              ? 'https://open.feishu.cn/open-apis/bot/v2/hook/...'
                              : 'https://...',
                        ),
                      ),
                      if (channelType == 'feishu' || channelType == 'dingtalk' || channelType == 'webhook') ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: secretCtrl,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: (existing != null && existing.hasSecret)
                                ? '签名密钥（留空保持不变）'
                                : (channelType == 'webhook' ? '请求头签名密钥（选填）' : '安全签名密钥（选填，若开启加签则填写）'),
                            hintText: channelType == 'feishu' ? '飞书机器人「签名校验」密钥（未开启可留空）' : '',
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.accentSoft.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        channelType == 'feishu'
                            ? '提示：在飞书创建一个只有你自己的群 → 群设置 → 群机器人 → 添加自定义机器人 → 复制 Webhook 地址粘贴到上方即可，手机退出 MailControl 后也能通过飞书系统级通道秒收提醒。'
                            : (channelType == 'feishu_app'
                                ? '提示：使用飞书自建应用可将邮件卡片直接私聊推送给你本人（open_id），请确保已在飞书后台为应用开启「获取与发送单聊/群组消息」权限并发布版本。'
                                : '提示：配置并启用后，云端收到新邮件会自动推送卡片或通知到该地址，不消耗手机后台电量。'),
                        style: TextStyle(fontSize: 12, color: p.textSecondary, height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用该推送通道', style: TextStyle(fontSize: 14)),
                      value: enabled,
                      onChanged: (v) => setModalState(() => enabled = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (nameCtrl.text.trim().isEmpty) return;
                        setModalState(() => saving = true);
                        try {
                          final payload = {
                            'name': nameCtrl.text.trim(),
                            'channel_type': channelType,
                            'enabled': enabled,
                            'webhook_url': webhookCtrl.text.trim(),
                            'secret': secretCtrl.text.trim(),
                            'app_id': appIdCtrl.text.trim(),
                            'target_id': targetIdCtrl.text.trim(),
                            'target_id_type': targetIdType,
                          };
                          final api = ref.read(apiClientProvider);
                          if (existing != null) {
                            await api.updatePushChannel(existing.id, payload);
                          } else {
                            await api.createPushChannel(payload);
                          }
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setModalState(() => saving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(ref.read(apiClientProvider).extractError(e))),
                            );
                          }
                        }
                      },
                child: Text(saving ? '保存中...' : '保存'),
              ),
            ],
          );
        },
      ),
    );
    nameCtrl.dispose();
    webhookCtrl.dispose();
    secretCtrl.dispose();
    appIdCtrl.dispose();
    targetIdCtrl.dispose();

    if (saved == true) {
      await _load();
    }
  }

  Future<void> _toggleEnabled(PushChannel ch, bool val) async {
    try {
      await ref.read(apiClientProvider).updatePushChannel(ch.id, {
        'name': ch.name,
        'channel_type': ch.channelType,
        'enabled': val,
        'webhook_url': ch.webhookUrl,
        'app_id': ch.appId,
        'target_id': ch.targetId,
        'target_id_type': ch.targetIdType,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(apiClientProvider).extractError(e))),
        );
      }
    }
  }

  Future<void> _testChannel(PushChannel ch) async {
    setState(() => _testingId = ch.id);
    try {
      final msg = await ref.read(apiClientProvider).testPushChannel(ch.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(apiClientProvider).extractError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _testingId = null);
    }
  }

  Future<void> _deleteChannel(PushChannel ch) async {
    try {
      await ref.read(apiClientProvider).deletePushChannel(ch.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(apiClientProvider).extractError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              if (!widget.isDialog)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('离线消息推送通道', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(
                      '由云端服务端直推飞书 / 企微 / 钉钉，彻底退出 App 也能秒级弹窗',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加通道'),
              ),
              if (widget.isDialog)
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _channels.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
                              child: Icon(Icons.notifications_active_outlined, size: 30, color: p.accent),
                            ),
                            const SizedBox(height: 14),
                            const Text('尚未配置离线推送通道', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text(
                              '绑定飞书机器人后，即使手机彻底划掉退出 MailControl、无任何顶部保活条，也能通过飞书系统通道秒收新邮件与验证码。',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: p.textSecondary, height: 1.5),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: () => _openEditor(),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('立即配置飞书推送'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: _channels.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final ch = _channels[idx];
                        final badgeColor = _typeColor(ch.channelType);
                        final isTesting = _testingId == ch.id;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              ch.name,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: badgeColor.withValues(alpha: 0.14),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _typeLabel(ch.channelType),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: badgeColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        ch.channelType == 'feishu_app'
                                            ? 'App: ${ch.appId} -> ${ch.targetIdType}:${ch.targetId}'
                                            : ch.webhookUrl,
                                        style: TextStyle(fontSize: 12, color: p.textMuted),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: isTesting ? null : () => _testChannel(ch),
                                  child: isTesting
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('测试'),
                                ),
                                Switch(
                                  value: ch.enabled,
                                  onChanged: (v) => _toggleEnabled(ch, v),
                                ),
                                IconButton(
                                  tooltip: '编辑',
                                  icon: const Icon(Icons.edit_outlined, size: 19),
                                  onPressed: () => _openEditor(ch),
                                ),
                                IconButton(
                                  tooltip: '删除',
                                  icon: const Icon(Icons.delete_outline, size: 19),
                                  onPressed: () => _deleteChannel(ch),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );

    if (widget.isDialog) return body;
    return Scaffold(body: SafeArea(child: body));
  }
}
