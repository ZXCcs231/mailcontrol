import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers/mail_provider.dart';
import 'brand_widgets.dart';

class MessageList extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;
  final VoidCallback onAddAccount;
  final ValueChanged<MailMessage> onOpenMessage;

  const MessageList({
    super.key,
    this.onOpenDrawer,
    required this.onAddAccount,
    required this.onOpenMessage,
  });

  @override
  ConsumerState<MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<MessageList> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(mailProvider.notifier).setFilters(q: val.trim());
    });
  }

  String _viewTitle(MailState mail) {
    if (mail.activeFolderId != null) {
      final f = mail.folders.where((e) => e.id == mail.activeFolderId).firstOrNull;
      if (f != null) return f.name;
    }
    if (mail.activeTagId != null) {
      final t = mail.tags.where((e) => e.id == mail.activeTagId).firstOrNull;
      if (t != null) return '标签 · ${t.name}';
    }
    if (mail.activeAccountId != null) {
      final a = mail.accounts.where((e) => e.id == mail.activeAccountId).firstOrNull;
      if (a != null) return a.label;
    }
    return switch (mail.activeView) {
      'starred' => '星标邮件',
      'sent' => '已发送',
      'drafts' => '草稿箱',
      'archive' => '归档邮件',
      'trash' => '回收站',
      _ => '全部收件箱',
    };
  }

  @override
  Widget build(BuildContext context) {
    final mail = ref.watch(mailProvider);
    final notifier = ref.read(mailProvider.notifier);
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: p.listBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                if (widget.onOpenDrawer != null)
                  IconButton(
                    onPressed: widget.onOpenDrawer,
                    icon: const Icon(Icons.menu_rounded),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _viewTitle(mail),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '共 ${mail.totalMessages} 封邮件',
                        style: TextStyle(fontSize: 11.5, color: p.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '同步全部邮箱',
                  onPressed: mail.syncing ? null : () => notifier.syncAllAccounts(),
                  icon: mail.syncing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.sync_rounded, color: p.textSecondary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: (v) => notifier.setFilters(q: v.trim()),
              decoration: InputDecoration(
                hintText: '搜索主题、发件人或正文...',
                isDense: true,
                filled: true,
                fillColor: p.readingBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: p.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: p.borderSubtle),
                ),
                prefixIcon: Icon(Icons.search_rounded, size: 19, color: p.textMuted),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 17),
                        onPressed: () {
                          _searchCtrl.clear();
                          notifier.setFilters(q: '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 6),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('仅看未读', style: TextStyle(fontSize: 12)),
                  selected: mail.unreadOnly,
                  onSelected: (v) => notifier.setFilters(unreadOnly: v),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('含附件', style: TextStyle(fontSize: 12)),
                  selected: mail.hasAttachments,
                  onSelected: (v) => notifier.setFilters(hasAttachments: v),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                if (mail.messages.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      final allSelected = mail.selectedIds.length == mail.messages.length;
                      notifier.selectAllVisible(!allSelected);
                    },
                    child: Text(
                      mail.selectedIds.length == mail.messages.length ? '取消全选' : '全选',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
            ),
          ),
          if (mail.selectedIds.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: p.accentSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.accent.withValues(alpha: 0.25)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      '已选 ${mail.selectedIds.length} 封',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: p.accent),
                    ),
                    const SizedBox(width: 8),
                    TextButton(onPressed: () => notifier.runBatch('mark_read'), child: const Text('标为已读')),
                    TextButton(onPressed: () => notifier.runBatch('mark_unread'), child: const Text('标为未读')),
                    TextButton(onPressed: () => notifier.runBatch('star'), child: const Text('加星')),
                    TextButton(onPressed: () => notifier.runBatch('archive'), child: const Text('归档')),
                    TextButton(
                      onPressed: () => notifier.runBatch('delete'),
                      child: Text('删除', style: TextStyle(color: scheme.error)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: mail.loadingList && mail.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : mail.messages.isEmpty
                    ? _buildEmpty(context, mail, p)
                    : RefreshIndicator(
                        onRefresh: () async {
                          await notifier.syncAllAccounts();
                          await notifier.loadMessages();
                        },
                        child: ListView.separated(
                          itemCount: mail.messages.length,
                          separatorBuilder: (_, _) => Divider(color: p.borderSubtle),
                          itemBuilder: (context, idx) {
                            final msg = mail.messages[idx];
                            final isSelected = mail.selectedMessage?.id == msg.id;
                            final isChecked = mail.selectedIds.contains(msg.id);
                            return _MessageTile(
                              message: msg,
                              isSelected: isSelected,
                              isChecked: isChecked,
                              hasSelectionMode: mail.selectedIds.isNotEmpty,
                              onTap: () => widget.onOpenMessage(msg),
                              onToggleCheck: () => notifier.toggleSelectId(msg.id),
                              onToggleStar: () => notifier.toggleStar(msg),
                              onToggleRead: () => notifier.toggleRead(msg),
                              onArchive: () => notifier.moveMessage(msg.id, 'archive'),
                              onDelete: () => notifier.deleteMessage(msg.id),
                            );
                          },
                        ),
                      ),
          ),
          if (mail.totalMessages > 30)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.borderSubtle))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: mail.page > 1 ? () => notifier.setFilters(page: mail.page - 1) : null,
                    child: const Text('上一页'),
                  ),
                  Text('第 ${mail.page} 页', style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
                  TextButton(
                    onPressed: mail.page * 30 < mail.totalMessages
                        ? () => notifier.setFilters(page: mail.page + 1)
                        : null,
                    child: const Text('下一页'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, MailState mail, AppPalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.mark_email_read_outlined, size: 32, color: p.accent),
            ),
            const SizedBox(height: 14),
            Text(
              mail.accounts.isEmpty ? '还没有绑定邮箱账号' : '当前视图暂无邮件',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              mail.accounts.isEmpty
                  ? '点击下方按钮绑定 QQ、163、Gmail、Outlook 等任意主流邮箱，即可开始统一管理'
                  : '可以点击右上角同步按钮拉取最新邮件，或调整当前筛选条件',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.textSecondary, height: 1.5),
            ),
            if (mail.accounts.isEmpty) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: widget.onAddAccount,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加第一个邮箱'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  final MailMessage message;
  final bool isSelected;
  final bool isChecked;
  final bool hasSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onToggleCheck;
  final VoidCallback onToggleStar;
  final VoidCallback onToggleRead;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _MessageTile({
    required this.message,
    required this.isSelected,
    required this.isChecked,
    required this.hasSelectionMode,
    required this.onTap,
    required this.onToggleCheck,
    required this.onToggleStar,
    required this.onToggleRead,
    required this.onArchive,
    required this.onDelete,
  });

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('HH:mm').format(dt);
    }
    if (dt.year == now.year) {
      return DateFormat('MM/dd').format(dt);
    }
    return DateFormat('yyyy/MM/dd').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final acctColor = parseHexColor(message.accountColor);
    final senderText = message.isDraft
        ? '[草稿] ${message.toAddrs.isEmpty ? "无收件人" : message.toAddrs}'
        : message.senderDisplay;

    return HoverSurface(
      onTap: onTap,
      onLongPress: onToggleCheck,
      builder: (context, hovering) {
        final showCheckbox = hovering || isChecked || hasSelectionMode;
        final bg = isSelected
            ? p.activeBg
            : (hovering ? p.hoverBg : (!message.isRead ? p.accentSoft.withValues(alpha: 0.45) : Colors.transparent));

        return Container(
          color: bg,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: showCheckbox
                    ? Center(
                        child: Checkbox(
                          value: isChecked,
                          onChanged: (_) => onToggleCheck(),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                    : Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SenderAvatar(name: senderText, size: 36),
                          if (!message.isRead)
                            Positioned(
                              right: -1,
                              top: -1,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: p.accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: p.listBg, width: 1.5),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            senderText,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: message.isRead ? FontWeight.w500 : FontWeight.w700,
                              color: p.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (message.hasAttachments)
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Icon(Icons.attach_file_rounded, size: 14, color: p.textMuted),
                          ),
                        Text(
                          _formatDate(message.receivedAt),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: message.isRead ? FontWeight.w400 : FontWeight.w600,
                            color: message.isRead ? p.textMuted : p.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.subject,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: message.isRead ? FontWeight.w500 : FontWeight.w700,
                              color: p.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hovering)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MiniAction(
                                tooltip: message.isRead ? '标为未读' : '标为已读',
                                icon: message.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined,
                                onTap: onToggleRead,
                              ),
                              _MiniAction(
                                tooltip: '归档',
                                icon: Icons.archive_outlined,
                                onTap: onArchive,
                              ),
                              _MiniAction(
                                tooltip: '删除',
                                icon: Icons.delete_outline_rounded,
                                color: scheme.error,
                                onTap: onDelete,
                              ),
                            ],
                          ),
                        GestureDetector(
                          onTap: onToggleStar,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              message.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 18,
                              color: message.isStarred ? Colors.amber.shade600 : p.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (message.snippet.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        message.snippet,
                        style: TextStyle(fontSize: 12.2, color: p.textSecondary, height: 1.38),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (message.tags.isNotEmpty || message.accountLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (message.accountLabel.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: acctColor.withValues(alpha: 0.11),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(color: acctColor, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    message.accountLabel,
                                    style: TextStyle(fontSize: 10.5, color: acctColor, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          for (final tag in message.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: parseHexColor(tag.color).withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tag.name,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: parseHexColor(tag.color),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  const _MiniAction({
    required this.tooltip,
    required this.icon,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: color ?? p.textSecondary),
        ),
      ),
    );
  }
}
