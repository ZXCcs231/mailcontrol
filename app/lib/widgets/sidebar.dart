import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers/mail_provider.dart';
import 'brand_widgets.dart';

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
    final p = context.palette;

    return Container(
      width: 266,
      color: p.sidebarBg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                (Platform.isWindows && !widget.inDrawer) ? 6 : 14,
                10,
                12,
              ),
              child: Row(
                children: [
                  const MailControlLogo(size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'MailControl',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '切换浅色/深色主题',
                    onPressed: () => ref.read(authProvider.notifier).toggleTheme(),
                    icon: Icon(
                      auth.themeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      size: 19,
                      color: p.textSecondary,
                    ),
                    visualDensity: VisualDensity.compact,
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
                  icon: const Icon(Icons.edit_square, size: 17),
                  label: const Text('写邮件'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                children: [
                  _NavItem(
                    icon: Icons.all_inbox_rounded,
                    label: '全部收件箱',
                    badge: mail.stats.inboxUnread,
                    selected: mail.activeView == 'inbox' && mail.activeAccountId == null && mail.activeFolderId == null,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectView('inbox');
                    },
                  ),
                  _NavItem(
                    icon: Icons.star_rounded,
                    label: '星标邮件',
                    badge: mail.stats.starredCount,
                    selected: mail.activeView == 'starred' && mail.activeAccountId == null,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectView('starred');
                    },
                  ),
                  _NavItem(
                    icon: Icons.send_rounded,
                    label: '已发送',
                    selected: mail.activeView == 'sent' && mail.activeAccountId == null,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectView('sent');
                    },
                  ),
                  _NavItem(
                    icon: Icons.drafts_rounded,
                    label: '草稿箱',
                    badge: mail.stats.draftsCount,
                    selected: mail.activeView == 'drafts' && mail.activeAccountId == null,
                    onTap: () {
                      _closeIfDrawer();
                      notifier.selectView('drafts');
                    },
                  ),
                  _NavItem(
                    icon: Icons.archive_rounded,
                    label: '归档邮件',
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
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 2, 6),
                    child: Row(
                      children: [
                        Text(
                          '已绑定邮箱 (${mail.accounts.length})',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textMuted),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '添加邮箱账号',
                          onPressed: () {
                            _closeIfDrawer();
                            widget.onOpenAccountModal();
                          },
                          icon: Icon(Icons.add_rounded, size: 19, color: p.textSecondary),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  if (mail.accounts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _closeIfDrawer();
                          widget.onOpenAccountModal();
                        },
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('添加第一个邮箱'),
                      ),
                    ),
                  for (final acct in mail.accounts) _buildAccountGroup(context, acct, mail, notifier),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 2, 6),
                    child: Builder(
                      builder: (context) {
                        final totalTagUnread = mail.tags.fold<int>(
                          0,
                          (sum, t) => sum + (mail.stats.tagUnread[t.id] ?? 0),
                        );
                        return Row(
                          children: [
                            Text(
                              '标签分类',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textMuted),
                            ),
                            if (totalTagUnread > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: p.accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$totalTagUnread',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            IconButton(
                              tooltip: '管理标签',
                              onPressed: () {
                                _closeIfDrawer();
                                widget.onOpenTags();
                              },
                              icon: Icon(Icons.tune_rounded, size: 17, color: p.textSecondary),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  for (final tag in mail.tags)
                    _NavItem(
                      icon: Icons.label_rounded,
                      iconColor: parseHexColor(tag.color),
                      label: tag.name,
                      badge: mail.stats.tagUnread[tag.id] ?? 0,
                      badgeColor: parseHexColor(tag.color),
                      selected: mail.activeView == 'tag' && mail.activeTagId == tag.id,
                      onTap: () {
                        _closeIfDrawer();
                        notifier.selectTag(tag.id);
                      },
                    ),
                ],
              ),
            ),
            Divider(color: p.borderSubtle),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
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
                          icon: Icon(Icons.auto_fix_high_rounded, size: 16, color: p.textSecondary),
                          label: Text('自动规则', style: TextStyle(fontSize: 12.5, color: p.textPrimary)),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () {
                            _closeIfDrawer();
                            widget.onOpenSignatures();
                          },
                          icon: Icon(Icons.draw_rounded, size: 16, color: p.textSecondary),
                          label: Text('签名模板', style: TextStyle(fontSize: 12.5, color: p.textPrimary)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.surfaceElevated.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        SenderAvatar(name: auth.user?.username ?? 'U', size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                auth.user?.username ?? '',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                auth.baseUrl,
                                style: TextStyle(fontSize: 10.5, color: p.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '多端同步与连接地址',
                          onPressed: () => _showSyncDialog(context),
                          icon: Icon(Icons.devices_rounded, size: 17, color: p.textSecondary),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          tooltip: '退出登录',
                          onPressed: () => ref.read(authProvider.notifier).logout(),
                          icon: Icon(Icons.logout_rounded, size: 17, color: p.textSecondary),
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
                const Text('可用服务端地址（点击复制）：', style: TextStyle(fontSize: 12.5)),
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
    final p = context.palette;

    return Column(
      children: [
        HoverSurface(
          onTap: () {
            _closeIfDrawer();
            notifier.selectView('inbox', accountId: acct.id);
          },
          builder: (context, hovering) => Container(
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            padding: const EdgeInsets.fromLTRB(6, 7, 4, 7),
            decoration: BoxDecoration(
              color: isSelected ? p.activeBg : (hovering ? p.hoverBg : Colors.transparent),
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
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                      size: 17,
                      color: p.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ProviderBadge(providerId: acct.providerId, fallbackColor: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        acct.label,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        acct.emailAddress,
                        style: TextStyle(fontSize: 11, color: p.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (hovering || acct.lastSyncStatus == 'syncing')
                  IconButton(
                    tooltip: '立即同步',
                    icon: acct.lastSyncStatus == 'syncing'
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.sync_rounded, size: 15, color: p.textSecondary),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => notifier.syncSingleAccount(acct.id),
                  ),
                if (hovering)
                  IconButton(
                    tooltip: '邮箱设置',
                    icon: Icon(Icons.settings_outlined, size: 15, color: p.textSecondary),
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
        'inbox' => Icons.inbox_rounded,
        'sent' => Icons.send_rounded,
        'drafts' => Icons.drafts_rounded,
        'archive' => Icons.archive_rounded,
        'trash' => Icons.delete_outline_rounded,
        'spam' => Icons.report_gmailerrorred_rounded,
        _ => Icons.folder_rounded,
      };
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final int badge;
  final Color? badgeColor;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    this.iconColor,
    required this.label,
    this.badge = 0,
    this.badgeColor,
    required this.selected,
    this.dense = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasBadge = badge > 0;
    final activeBadgeBg = badgeColor ?? p.accent;
    return HoverSurface(
      onTap: onTap,
      builder: (context, hovering) => Container(
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 6 : 8),
        decoration: BoxDecoration(
          color: selected ? p.activeBg : (hovering ? p.hoverBg : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: dense ? 16 : 18,
              color: iconColor ?? (selected ? p.accent : p.textSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: dense ? 12.8 : 13.5,
                  fontWeight: (selected || hasBadge) ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? p.accent : p.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasBadge)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? p.accent : (badgeColor != null ? activeBadgeBg : p.hoverBg),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: (selected || badgeColor != null) ? Colors.white : p.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
