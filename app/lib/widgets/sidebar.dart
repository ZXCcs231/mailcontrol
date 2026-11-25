import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers/mail_provider.dart';

class Sidebar extends ConsumerStatefulWidget {
  final bool inDrawer;
  final VoidCallback onCompose;
  final void Function([MailAccount? existing]) onOpenAccountModal;
  final VoidCallback onOpenRules;
  final VoidCallback onOpenSignatures;
  final VoidCallback onOpenTags;

  const Sidebar({
    super.key,
    required this.inDrawer,
    required this.onCompose,
    required this.onOpenAccountModal,
    required this.onOpenRules,
    required this.onOpenSignatures,
    required this.onOpenTags,
  });

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final Set<int> _expandedAccounts = {};

  void _closeIfDrawer() {
    if (widget.inDrawer && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final mail = ref.watch(mailProvider);
    final notifier = ref.read(mailProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 268,
      color: Theme.of(context).cardTheme.color ?? scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
              child: Row(
                children: [
                  Icon(Icons.mark_email_read_rounded, color: scheme.primary, size: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'MailControl',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: '切换主题',
                    onPressed: () => ref.read(authProvider.notifier).toggleTheme(),
                    icon: Icon(
                      auth.themeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    _closeIfDrawer();
                    widget.onCompose();
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('写邮件'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  _NavItem(
                    icon: Icons.inbox_rounded,
                    label: '全部收件箱',
                    badge: mail.stats.inboxUnread,
                    selected: mail.activeView == 'inbox' && mail.activeAccountId == null && mail.activeFolderId == null,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectView('inbox');
                    },
                  ),
                  _NavItem(
                    icon: Icons.star_outline_rounded,
                    label: '星标邮件',
                    badge: mail.stats.starredCount,
                    selected: mail.activeView == 'starred' && mail.activeAccountId == null,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectView('starred');
                    },
                  ),
                  _NavItem(
                    icon: Icons.send_outlined,
                    label: '已发送',
                    selected: mail.activeView == 'sent' && mail.activeAccountId == null,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectView('sent');
                    },
                  ),
                  _NavItem(
                    icon: Icons.drafts_outlined,
                    label: '草稿箱',
                    badge: mail.stats.draftsCount,
                    selected: mail.activeView == 'drafts' && mail.activeAccountId == null,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectView('drafts');
                    },
                  ),
                  _NavItem(
                    icon: Icons.archive_outlined,
                    label: '归档',
                    selected: mail.activeView == 'archive' && mail.activeAccountId == null,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectView('archive');
                    },
                  ),
                  _NavItem(
                    icon: Icons.delete_outline_rounded,
                    label: '回收站',
                    selected: mail.activeView == 'trash' && mail.activeAccountId == null,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectView('trash');
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Divider(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 4, 4),
                    child: Row(
                      children: [
                        Text(
                          '已绑定邮箱 (${mail.accounts.length})',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '添加邮箱账号',
                          onPressed: () {
                            _closeIfDrawer();
                            widget.onOpenAccountModal();
                          },
                          icon: const Icon(Icons.add_circle_outline, size: 19),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  if (mail.accounts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _closeIfDrawer();
                          widget.onOpenAccountModal();
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('添加第一个邮箱'),
                      ),
                    ),
                  for (final acct in mail.accounts) _buildAccountGroup(context, acct, mail, notifier),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Divider(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 4, 4),
                    child: Row(
                      children: [
                        Text(
                          '标签分类',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '管理标签',
                          onPressed: () {
                            _closeIfDrawer();
                            widget.onOpenTags();
                          },
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  for (final tag in mail.tags)
                    _NavItem(
                      icon: Icons.label_outline_rounded,
                      iconColor: parseHexColor(tag.color),
                      label: tag.name,
                      selected: mail.activeView == 'tag' && mail.activeTagId == tag.id,
                      onTap: () {
                        _closeIfDrawer();
                        notifier.selectTag(tag.id);
                      },
                    ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () {
                            _closeIfDrawer();
                            widget.onOpenRules();
                          },
                          icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
                          label: const Text('自动规则'),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () {
                            _closeIfDrawer();
                            widget.onOpenSignatures();
                          },
                          icon: const Icon(Icons.draw_outlined, size: 17),
                          label: const Text('签名模板'),
                        ),
                      ),
                    ],
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        (auth.user?.username ?? 'U').substring(0, 1).toUpperCase(),
                        style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w700),
                      ),
                    ),
                    title: Text(
                      auth.user?.username ?? '',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      auth.baseUrl,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: '多端同步与连接地址',
                          onPressed: () => _showSyncDialog(context),
                          icon: const Icon(Icons.devices_rounded, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          tooltip: '退出登录',
                          onPressed: () => ref.read(authProvider.notifier).logout(),
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSyncDialog(BuildContext context) async {
    final auth = ref.read(authProvider);
    List<String> lanUrls = [];
    try {
      lanUrls = await ref.read(apiClientProvider).getServerLanUrls();
    } catch (_) {}
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.devices_rounded),
            SizedBox(width: 8),
            Text('多端账号同步'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '同一 MailControl 账号在 Windows 端与手机 App 上共享全部已绑定邮箱、邮件、草稿、标签、自动规则、签名与翻译缓存，无需重复录入，修改后实时自动同步。',
                style: TextStyle(fontSize: 13.5, height: 1.5),
              ),
              const SizedBox(height: 12),
              Text('当前连接地址：${auth.baseUrl}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              if (lanUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('手机端可填写以下局域网地址连接本机：', style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 6),
                for (final u in lanUrls)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: SelectableText(u, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: IconButton(
                      tooltip: '复制地址',
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: u));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制：$u')));
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  Widget _buildAccountGroup(
    BuildContext context,
    MailAccount acct,
    MailState mail,
    MailNotifier notifier,
  ) {
    final isExpanded = _expandedAccounts.contains(acct.id);
    final acctFolders = mail.folders.where((f) => f.accountId == acct.id).toList();
    final unread = mail.stats.accountUnread[acct.id] ?? acct.unreadCount;
    final isSelected = mail.activeAccountId == acct.id && mail.activeFolderId == null;
    final color = parseHexColor(acct.color);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            _closeIfDrawer();
            notifier.selectView('inbox', accountId: acct.id);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected ? scheme.primaryContainer.withValues(alpha: 0.55) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() {
                    if (isExpanded) {
                      _expandedAccounts.remove(acct.id);
                    } else {
                      _expandedAccounts.add(acct.id);
                    }
                  }),
                  child: Icon(
                    isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        acct.label,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        acct.emailAddress,
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unread',
                      style: TextStyle(fontSize: 11, color: scheme.onPrimary, fontWeight: FontWeight.w600),
                    ),
                  ),
                IconButton(
                  tooltip: '立即同步',
                  icon: acct.lastSyncStatus == 'syncing'
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => notifier.syncSingleAccount(acct.id),
                ),
                IconButton(
                  tooltip: '邮箱设置',
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _closeIfDrawer();
                    widget.onOpenAccountModal(acct);
                  },
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              children: [
                for (final f in acctFolders)
                  _NavItem(
                    icon: _folderIcon(f.role),
                    label: f.name,
                    badge: f.unreadCount,
                    selected: mail.activeFolderId == f.id,
                    dense: true,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectFolder(acct.id, f.id);
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _folderIcon(String role) => switch (role) {
        'inbox' => Icons.inbox_outlined,
        'sent' => Icons.send_outlined,
        'drafts' => Icons.drafts_outlined,
        'archive' => Icons.archive_outlined,
        'trash' => Icons.delete_outline,
        'spam' => Icons.report_gmailerrorred_outlined,
        _ => Icons.folder_outlined,
      };
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final int badge;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    this.iconColor,
    required this.label,
    this.badge = 0,
    required this.selected,
    this.dense = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 6 : 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer.withValues(alpha: 0.65) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: dense ? 17 : 19,
                color: iconColor ?? (selected ? scheme.primary : scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: dense ? 13 : 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
