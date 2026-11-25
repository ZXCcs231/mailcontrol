import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/email_html_normalizer.dart';
import '../core/email_html_translator.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/mail_provider.dart';
import 'brand_widgets.dart';

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
  bool _forceLightPaper = false;
  int? _downloadingAttId;
  bool _translating = false;
  bool _showTranslated = true;
  int? _lastMsgId;
  MessageTranslation? _translation;
  String? _lastRawHtml;
  bool? _lastDarkMode;
  String _cachedNormalizedHtml = '';

  String _getNormalizedHtml(String rawHtml, {required bool darkMode}) {
    if (_lastRawHtml == rawHtml && _lastDarkMode == darkMode) {
      return _cachedNormalizedHtml;
    }
    _lastRawHtml = rawHtml;
    _lastDarkMode = darkMode;
    _cachedNormalizedHtml = normalizeEmailHtml(rawHtml, darkMode: darkMode);
    return _cachedNormalizedHtml;
  }

  Future<void> _translate(MailMessage msg, String targetLang, {bool force = false}) async {
    setState(() => _translating = true);
    try {
      final api = ref.read(apiClientProvider);
      var res = await api.translateMessage(msg.id, targetLang, force: force);
      if (msg.bodyHtml.isNotEmpty && res.translatedHtml.trim().isEmpty) {
        final inPlaceHtml = await translateHtmlInPlace(
          rawHtml: msg.bodyHtml,
          translateBatch: (batch) async {
            final t = await api.translateText(text: batch, targetLang: targetLang);
            return t.translatedText;
          },
        );
        res = MessageTranslation(
          messageId: res.messageId,
          targetLang: res.targetLang,
          provider: res.provider,
          translatedSubject: res.translatedSubject,
          translatedText: res.translatedText,
          translatedHtml: inPlaceHtml,
          cached: res.cached,
        );
      }
      if (mounted) {
        setState(() {
          _translation = res;
          _showTranslated = true;
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
    final pal = context.palette;
    final scheme = Theme.of(context).colorScheme;

    if (mail.loadingDetail && msg == null) {
      return Container(color: pal.readingBg, child: const Center(child: CircularProgressIndicator()));
    }
    if (msg == null) {
      return Container(
        color: pal.readingBg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(color: pal.accentSoft, shape: BoxShape.circle),
                child: Icon(Icons.mail_outline_rounded, size: 34, color: pal.accent),
              ),
              const SizedBox(height: 14),
              Text('选择一封邮件开始阅读', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.textPrimary)),
              const SizedBox(height: 4),
              Text('支持 HTML 富文本预览、附件下载及一键多语种翻译', style: TextStyle(fontSize: 12.5, color: pal.textMuted)),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final acctColor = parseHexColor(msg.accountColor);
    final visibleAttachments = msg.attachments.where((a) => !a.isInline).toList();
    if (_lastMsgId != msg.id) {
      _lastMsgId = msg.id;
      _translation = null;
      _showTranslated = true;
      _forceLightPaper = false;
    }

    return Container(
      color: pal.readingBg,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: pal.readingBg,
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
                  _ToolbarButton(
                    tooltip: '回复',
                    icon: Icons.reply_rounded,
                    label: widget.isStandalone ? null : '回复',
                    onTap: () => widget.onReplyOrForward(msg, 'reply'),
                  ),
                  const SizedBox(width: 4),
                  _ToolbarButton(
                    tooltip: '回复全部',
                    icon: Icons.reply_all_rounded,
                    onTap: () => widget.onReplyOrForward(msg, 'reply_all'),
                  ),
                  const SizedBox(width: 4),
                  _ToolbarButton(
                    tooltip: '转发',
                    icon: Icons.forward_rounded,
                    label: widget.isStandalone ? null : '转发',
                    onTap: () => widget.onReplyOrForward(msg, 'forward'),
                  ),
                ],
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: '翻译邮件',
                  enabled: !_translating,
                  icon: _translating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.translate_rounded, color: _translation != null ? pal.accent : pal.textSecondary),
                  onSelected: (lang) => _translate(msg, lang),
                  itemBuilder: (_) => [
                    for (final lang in kTranslateLanguages)
                      PopupMenuItem<String>(
                        value: lang.code,
                        child: Row(
                          children: [
                            if (_translation?.targetLang == lang.code)
                              Icon(Icons.check_rounded, size: 16, color: pal.accent)
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
                    color: msg.isStarred ? Colors.amber.shade600 : pal.textSecondary,
                  ),
                ),
                IconButton(
                  tooltip: msg.isRead ? '标为未读' : '标为已读',
                  onPressed: () => notifier.toggleRead(msg),
                  icon: Icon(
                    msg.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined,
                    color: pal.textSecondary,
                  ),
                ),
                if (mail.tags.isNotEmpty)
                  PopupMenuButton<int>(
                    tooltip: '打标签',
                    icon: Icon(Icons.label_outline_rounded, color: pal.textSecondary),
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
                  icon: Icon(Icons.archive_outlined, color: pal.textSecondary),
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
              padding: EdgeInsets.all(widget.isStandalone ? 14 : 22),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(widget.isStandalone ? 18 : 26),
                    decoration: BoxDecoration(
                      color: pal.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: pal.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SelectableText(
                                (_translation != null && _showTranslated && _translation!.translatedSubject.isNotEmpty)
                                    ? _translation!.translatedSubject
                                    : msg.subject,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20, height: 1.35),
                              ),
                            ),
                            if (msg.bodyHtml.isNotEmpty && isDark)
                              TextButton(
                                onPressed: () => setState(() => _forceLightPaper = !_forceLightPaper),
                                child: Text(
                                  _forceLightPaper ? '深色正文' : '浅色信纸',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SenderAvatar(name: msg.senderDisplay, size: 42),
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
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: pal.textPrimary),
                                        ),
                                      ),
                                      Text(
                                        DateFormat('yyyy-MM-dd HH:mm').format(msg.receivedAt),
                                        style: TextStyle(fontSize: 12, color: pal.textMuted),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '收件人：${msg.toAddrs}',
                                    style: TextStyle(fontSize: 12.5, color: pal.textSecondary),
                                  ),
                                  if (msg.ccAddrs.isNotEmpty)
                                    Text(
                                      '抄送：${msg.ccAddrs}',
                                      style: TextStyle(fontSize: 12.5, color: pal.textSecondary),
                                    ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: acctColor.withValues(alpha: 0.11),
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
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Divider(color: pal.borderSubtle),
                        ),
                        if (visibleAttachments.isNotEmpty) ...[
                          Text(
                            '附件 (${visibleAttachments.length})',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: pal.textSecondary),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final att in visibleAttachments)
                                ActionChip(
                                  avatar: _downloadingAttId == att.id
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Icon(Icons.download_rounded, size: 16, color: pal.accent),
                                  label: Text('${att.filename} (${_formatSize(att.size)})'),
                                  onPressed: _downloadingAttId == att.id ? null : () => _downloadAndOpen(att),
                                ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Divider(color: pal.borderSubtle),
                          ),
                        ],
                        if (_translation != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: pal.accentSoft,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: pal.accent.withValues(alpha: 0.22)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.translate_rounded, size: 15, color: pal.accent),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _showTranslated
                                        ? '已译为${_langName(_translation!.targetLang)} · ${_translation!.provider}${_translation!.cached ? " · 已缓存" : ""}'
                                        : '当前显示原文（已有${_langName(_translation!.targetLang)}译文）',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.accent),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  onPressed: () => setState(() => _showTranslated = !_showTranslated),
                                  child: Text(_showTranslated ? '查看原文' : '查看译文', style: const TextStyle(fontSize: 12)),
                                ),
                                IconButton(
                                  tooltip: '重新翻译',
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _translating ? null : () => _translate(msg, _translation!.targetLang, force: true),
                                ),
                                IconButton(
                                  tooltip: '关闭译文',
                                  icon: const Icon(Icons.close_rounded, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() {
                                    _translation = null;
                                    _showTranslated = true;
                                  }),
                                ),
                              ],
                            ),
                          ),
                        if (msg.bodyHtml.isNotEmpty)
                          Builder(
                            builder: (context) {
                              final useLightPaper = isDark && _forceLightPaper;
                              final useDarkHtml = isDark && !_forceLightPaper;
                              final activeHtml = (_translation != null &&
                                      _showTranslated &&
                                      _translation!.translatedHtml.isNotEmpty)
                                  ? _translation!.translatedHtml
                                  : msg.bodyHtml;
                              final bodyWidget = SelectionArea(
                                child: SizedBox(
                                  width: double.infinity,
                                  child: HtmlWidget(
                                    _getNormalizedHtml(activeHtml, darkMode: useDarkHtml),
                                    textStyle: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.68,
                                      color: useLightPaper ? const Color(0xFF0F172A) : pal.textPrimary,
                                      fontFamily: AppTheme.fontFamily,
                                      fontFamilyFallback: AppTheme.fontFallback,
                                    ),
                                    customStylesBuilder: (element) {
                                      if (element.localName == 'img') {
                                        return const {'max-width': '100%'};
                                      }
                                      return null;
                                    },
                                    onTapUrl: (url) async {
                                      final uri = Uri.tryParse(url);
                                      if (uri != null) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                      return true;
                                    },
                                  ),
                                ),
                              );
                              if (!useLightPaper) return bodyWidget;
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFFFF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: bodyWidget,
                              );
                            },
                          )
                        else
                          Builder(
                            builder: (context) {
                              final activePlain = (_translation != null &&
                                      _showTranslated &&
                                      _translation!.translatedText.isNotEmpty)
                                  ? _translation!.translatedText
                                  : (msg.bodyText.isNotEmpty ? msg.bodyText : '（邮件正文为空）');
                              return SelectableText(
                                activePlain,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  height: 1.68,
                                  color: pal.textPrimary,
                                  fontFamily: AppTheme.fontFamily,
                                  fontFamilyFallback: AppTheme.fontFallback,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    if (label == null) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 19, color: pal.textSecondary),
        visualDensity: VisualDensity.compact,
      );
    }
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17, color: pal.textSecondary),
      label: Text(label!, style: TextStyle(fontSize: 13, color: pal.textPrimary)),
    );
  }
}
