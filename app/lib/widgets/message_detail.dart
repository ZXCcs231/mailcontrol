import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers/mail_provider.dart';

class MessageDetailView extends ConsumerStatefulWidget {
  final MailMessage? message;
  final bool isStandalone;
  final void Function(MailMessage msg, String mode) onReplyOrForward;
  final VoidCallback? onDeleted;

  const MessageDetailView({
    super.key,
    required this.message,
    this.isStandalone = false,
    required this.onReplyOrForward,
    this.onDeleted,
  });

  @override
  ConsumerState<MessageDetailView> createState() => _MessageDetailViewState();
}

class _MessageDetailViewState extends ConsumerState<MessageDetailView> {
  bool _preferPlain = false;
  int? _downloadingAttId;
  bool _translating = false;
  bool _onlyTranslation = false;
  int? _lastMsgId;
  MessageTranslation? _translation;

  Future<void> _translate(MailMessage msg, String targetLang, {bool force = false}) async {
    setState(() => _translating = true);
    try {
      final res = await ref.read(apiClientProvider).translateMessage(msg.id, targetLang, force: force);
      if (mounted) {
        setState(() {
          _translation = res;
          _translating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _translating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(apiClientProvider).extractError(e))),
        );
      }
    }
  }

  String _langName(String code) {
    return kTranslateLanguages.where((l) => l.code == code).firstOrNull?.name ?? code;
  }

  Future<void> _downloadAndOpen(MailAttachment att) async {
    setState(() => _downloadingAttId = att.id);
    try {
      final dir = await getTemporaryDirectory();
      final attDir = Directory(p.join(dir.path, 'mailcontrol_attachments'));
      if (!attDir.existsSync()) attDir.createSync(recursive: true);
      final savePath = p.join(attDir.path, '${att.id}_${att.filename}');
      await ref.read(apiClientProvider).downloadAttachment(att.id, savePath);
      await OpenFilex.open(savePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('附件已保存到：$savePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingAttId = null);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final mail = ref.watch(mailProvider);
    final notifier = ref.read(mailProvider.notifier);
    final msg = widget.message ?? mail.selectedMessage;
    final scheme = Theme.of(context).colorScheme;

    if (mail.loadingDetail && msg == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (msg == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline_rounded, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text('选择一封邮件开始阅读', style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final acctColor = parseHexColor(msg.accountColor);
    final visibleAttachments = msg.attachments.where((a) => !a.isInline).toList();
    if (_lastMsgId != msg.id) {
      _lastMsgId = msg.id;
      _translation = null;
      _onlyTranslation = false;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              if (widget.isStandalone)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              if (msg.isDraft)
                FilledButton.tonalIcon(
                  onPressed: () => widget.onReplyOrForward(msg, 'draft'),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('继续编辑草稿'),
                )
              else ...[
                IconButton(
                  tooltip: '回复',
                  onPressed: () => widget.onReplyOrForward(msg, 'reply'),
                  icon: const Icon(Icons.reply_rounded),
                ),
                IconButton(
                  tooltip: '回复全部',
                  onPressed: () => widget.onReplyOrForward(msg, 'reply_all'),
                  icon: const Icon(Icons.reply_all_rounded),
                ),
                IconButton(
                  tooltip: '转发',
                  onPressed: () => widget.onReplyOrForward(msg, 'forward'),
                  icon: const Icon(Icons.forward_rounded),
                ),
              ],
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: '翻译邮件',
                enabled: !_translating,
                icon: _translating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.translate_rounded),
                onSelected: (lang) => _translate(msg, lang),
                itemBuilder: (_) => [
                  for (final lang in kTranslateLanguages)
                    PopupMenuItem<String>(
                      value: lang.code,
                      child: Row(
                        children: [
                          if (_translation?.targetLang == lang.code)
                            Icon(Icons.check_rounded, size: 16, color: scheme.primary)
                          else
                            const SizedBox(width: 16),
                          const SizedBox(width: 8),
                          Text('翻译为 ${lang.name}'),
                        ],
                      ),
                    ),
                ],
              ),
              IconButton(
                tooltip: msg.isStarred ? '取消星标' : '加星标',
                onPressed: () => notifier.toggleStar(msg),
                icon: Icon(
                  msg.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: msg.isStarred ? Colors.amber.shade600 : null,
                ),
              ),
              IconButton(
                tooltip: msg.isRead ? '标为未读' : '标为已读',
                onPressed: () => notifier.toggleRead(msg),
                icon: Icon(msg.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined),
              ),
              if (mail.tags.isNotEmpty)
                PopupMenuButton<int>(
                  tooltip: '打标签',
                  icon: const Icon(Icons.label_outline_rounded),
                  onSelected: (tagId) {
                    final has = msg.tags.any((t) => t.id == tagId);
                    notifier.toggleMessageTag(msg.id, tagId, has);
                  },
                  itemBuilder: (_) => [
                    for (final tag in mail.tags)
                      CheckedPopupMenuItem<int>(
                        value: tag.id,
                        checked: msg.tags.any((t) => t.id == tag.id),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: parseHexColor(tag.color), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Text(tag.name),
                          ],
                        ),
                      ),
                  ],
                ),
              IconButton(
                tooltip: '归档',
                onPressed: () async {
                  await notifier.moveMessage(msg.id, 'archive');
                  widget.onDeleted?.call();
                },
                icon: const Icon(Icons.archive_outlined),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: () async {
                  await notifier.deleteMessage(msg.id);
                  widget.onDeleted?.call();
                },
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        msg.subject,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (msg.bodyHtml.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _preferPlain = !_preferPlain),
                        child: Text(_preferPlain ? '切换 HTML' : '纯文本'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: acctColor.withValues(alpha: 0.16),
                      child: Text(
                        msg.senderDisplay.isNotEmpty ? msg.senderDisplay.substring(0, 1).toUpperCase() : '?',
                        style: TextStyle(color: acctColor, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  msg.fromName.isNotEmpty ? '${msg.fromName} <${msg.fromAddr}>' : msg.fromAddr,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ),
                              Text(
                                DateFormat('yyyy-MM-dd HH:mm').format(msg.receivedAt),
                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '收件人：${msg.toAddrs}',
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                          ),
                          if (msg.ccAddrs.isNotEmpty)
                            Text(
                              '抄送：${msg.ccAddrs}',
                              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                            ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: acctColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${msg.accountLabel} (${msg.accountEmail})',
                                  style: TextStyle(fontSize: 11.5, color: acctColor, fontWeight: FontWeight.w600),
                                ),
                              ),
                              for (final tag in msg.tags)
                                Chip(
                                  label: Text(tag.name, style: const TextStyle(fontSize: 11)),
                                  backgroundColor: parseHexColor(tag.color).withValues(alpha: 0.14),
                                  side: BorderSide.none,
                                  visualDensity: VisualDensity.compact,
                                  onDeleted: () => notifier.toggleMessageTag(msg.id, tag.id, true),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(),
                ),
                if (visibleAttachments.isNotEmpty) ...[
                  Text('附件 (${visibleAttachments.length})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final att in visibleAttachments)
                        ActionChip(
                          avatar: _downloadingAttId == att.id
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download_rounded, size: 16),
                          label: Text('${att.filename} (${_formatSize(att.size)})'),
                          onPressed: _downloadingAttId == att.id ? null : () => _downloadAndOpen(att),
                        ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(),
                  ),
                ],
                if (_translation != null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.translate_rounded, size: 17, color: scheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '译文（${_langName(_translation!.targetLang)} · ${_translation!.provider}${_translation!.cached ? " · 已缓存" : ""}）',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: scheme.primary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _onlyTranslation = !_onlyTranslation),
                              child: Text(_onlyTranslation ? '显示原文' : '仅看译文', style: const TextStyle(fontSize: 12)),
                            ),
                            IconButton(
                              tooltip: '重新翻译',
                              icon: const Icon(Icons.refresh_rounded, size: 17),
                              visualDensity: VisualDensity.compact,
                              onPressed: _translating ? null : () => _translate(msg, _translation!.targetLang, force: true),
                            ),
                            IconButton(
                              tooltip: '关闭译文',
                              icon: const Icon(Icons.close_rounded, size: 17),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() {
                                _translation = null;
                                _onlyTranslation = false;
                              }),
                            ),
                          ],
                        ),
                        if (_translation!.translatedSubject.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          SelectableText(
                            '主题：${_translation!.translatedSubject}',
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                        if (_translation!.translatedText.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SelectableText(
                            _translation!.translatedText,
                            style: const TextStyle(fontSize: 14.5, height: 1.6),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (!_onlyTranslation) ...[
                  if (!_preferPlain && msg.bodyHtml.isNotEmpty)
                    SelectionArea(
                      child: HtmlWidget(
                        msg.bodyHtml,
                        onTapUrl: (url) async {
                          final uri = Uri.tryParse(url);
                          if (uri != null) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                          return true;
                        },
                      ),
                    )
                  else
                    SelectableText(
                      msg.bodyText.isNotEmpty ? msg.bodyText : '（邮件正文为空）',
                      style: const TextStyle(fontSize: 14.5, height: 1.6),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
