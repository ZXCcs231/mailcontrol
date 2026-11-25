import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers/mail_provider.dart';

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
      if (t != null) return '标签：${t.name}';
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
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              if (widget.onOpenDrawer != null)
                IconButton(
                  onPressed: widget.onOpenDrawer,
                  icon: const Icon(Icons.menu_rounded),
                ),
              Expanded(
                child: Text(
                  _viewTitle(mail),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '共 ${mail.totalMessages} 封',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '同步全部邮箱',
                onPressed: mail.syncing ? null : () => notifier.syncAllAccounts(),
                icon: mail.syncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            onSubmitted: (v) => notifier.setFilters(q: v.trim()),
            decoration: InputDecoration(
              hintText: '搜索主题、发件人、正文...',
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
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
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              FilterChip(
                label: const Text('仅看未读'),
                selected: mail.unreadOnly,
                onSelected: (v) => notifier.setFilters(unreadOnly: v),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('含附件'),
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
                  child: Text(mail.selectedIds.length == mail.messages.length ? '取消全选' : '全选'),
                ),
            ],
          ),
        ),
        if (mail.selectedIds.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text('已选 ${mail.selectedIds.length} 封', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
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
        const Divider(),
        Expanded(
          child: mail.loadingList && mail.messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : mail.messages.isEmpty
                  ? _buildEmpty(context, mail)
                  : RefreshIndicator(
                      onRefresh: () async {
                        await notifier.syncAllAccounts();
                        await notifier.loadMessages();
                      },
                      child: ListView.separated(
                        itemCount: mail.messages.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, idx) {
                          final msg = mail.messages[idx];
                          final isSelected = mail.selectedMessage?.id == msg.id;
                          final isChecked = mail.selectedIds.contains(msg.id);
                          return _MessageTile(
                            message: msg,
                            isSelected: isSelected,
                            isChecked: isChecked,
                            onTap: () => widget.onOpenMessage(msg),
                            onToggleCheck: () => notifier.toggleSelectId(msg.id),
                            onToggleStar: () => notifier.toggleStar(msg),
                          );
                        },
                      ),
                    ),
        ),
        if (mail.totalMessages > 30)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: mail.page > 1 ? () => notifier.setFilters(page: mail.page - 1) : null,
                  child: const Text('上一页'),
                ),
                Text('第 ${mail.page} 页'),
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
    );
  }

  Widget _buildEmpty(BuildContext context, MailState mail) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 52, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              mail.accounts.isEmpty ? '还没有绑定邮箱账号' : '当前视图暂无邮件',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              mail.accounts.isEmpty
                  ? '点击下方按钮添加 QQ、163、Gmail、Outlook 等任意主流邮箱即可开始管理'
                  : '可以点击右上角同步按钮拉取最新邮件，或切换筛选条件',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (mail.accounts.isEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: widget.onAddAccount,
                icon: const Icon(Icons.add),
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
  final VoidCallback onTap;
  final VoidCallback onToggleCheck;
  final VoidCallback onToggleStar;

  const _MessageTile({
    required this.message,
    required this.isSelected,
    required this.isChecked,
    required this.onTap,
    required this.onToggleCheck,
    required this.onToggleStar,
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
    final scheme = Theme.of(context).colorScheme;
    final acctColor = parseHexColor(message.accountColor);

    return InkWell(
      onTap: onTap,
      onLongPress: onToggleCheck,
      child: Container(
        color: isSelected
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : (!message.isRead ? scheme.primary.withValues(alpha: 0.04) : null),
        padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: isChecked,
              onChanged: (_) => onToggleCheck(),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!message.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                        ),
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(color: acctColor, shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Text(
                          message.isDraft ? '[草稿] ${message.toAddrs.isEmpty ? "无收件人" : message.toAddrs}' : message.senderDisplay,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: message.isRead ? FontWeight.w500 : FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (message.hasAttachments)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.attach_file_rounded, size: 15, color: scheme.onSurfaceVariant),
                        ),
                      Text(
                        _formatDate(message.receivedAt),
                        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
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
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: onToggleStar,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(
                            message.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                            size: 19,
                            color: message.isStarred ? Colors.amber.shade600 : scheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (message.snippet.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      message.snippet,
                      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (message.tags.isNotEmpty || message.accountLabel.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (message.accountLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: acctColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              message.accountLabel,
                              style: TextStyle(fontSize: 10.5, color: acctColor, fontWeight: FontWeight.w600),
                            ),
                          ),
                        for (final tag in message.tags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: parseHexColor(tag.color).withValues(alpha: 0.15),
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
      ),
    );
  }
}
