import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../providers/mail_provider.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  final MailMessage? refMessage;
  final String mode; // new | reply | reply_all | forward | draft
  final bool isDialog;

  const ComposeScreen({
    super.key,
    this.refMessage,
    this.mode = 'new',
    this.isDialog = false,
  });

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _toCtrl = TextEditingController();
  final _ccCtrl = TextEditingController();
  final _bccCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  int? _accountId;
  int? _draftId;
  bool _showCcBcc = false;
  bool _sending = false;
  bool _savingDraft = false;
  bool _translating = false;
  final List<({String name, String path, int size})> _attachments = [];

  Future<void> _translateCompose(String targetLang) async {
    if (_bodyCtrl.text.trim().isEmpty && _subjectCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先输入邮件主题或正文')));
      return;
    }
    setState(() => _translating = true);
    try {
      final res = await ref.read(apiClientProvider).translateText(
            subject: _subjectCtrl.text.trim(),
            text: _bodyCtrl.text,
            targetLang: targetLang,
          );
      if (!mounted) return;
      setState(() => _translating = false);

      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('译文预览（${res.provider}）'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (res.translatedSubject.isNotEmpty) ...[
                    Text('主题：${res.translatedSubject}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                  ],
                  SelectableText(res.translatedText.isEmpty ? '（无正文译文）' : res.translatedText),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            OutlinedButton(onPressed: () => Navigator.pop(ctx, 'append'), child: const Text('追加到原文下方')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('替换原文')),
          ],
        ),
      );
      if (action == 'replace') {
        setState(() {
          if (res.translatedSubject.isNotEmpty) _subjectCtrl.text = res.translatedSubject;
          if (res.translatedText.isNotEmpty) _bodyCtrl.text = res.translatedText;
        });
      } else if (action == 'append') {
        setState(() {
          if (res.translatedText.isNotEmpty) {
            _bodyCtrl.text = '${_bodyCtrl.text}\n\n---\n${res.translatedText}';
          }
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

  @override
  void initState() {
    super.initState();
    final mail = ref.read(mailProvider);
    final accounts = mail.accounts;
    if (accounts.isNotEmpty) {
      _accountId = widget.refMessage?.accountId ??
          accounts.where((a) => a.isDefault).firstOrNull?.id ??
          accounts.first.id;
    }

    final m = widget.refMessage;
    if (m != null) {
      switch (widget.mode) {
        case 'draft':
          _draftId = m.id;
          _toCtrl.text = m.toAddrs;
          _ccCtrl.text = m.ccAddrs;
          _bccCtrl.text = m.bccAddrs;
          _showCcBcc = m.ccAddrs.isNotEmpty || m.bccAddrs.isNotEmpty;
          _subjectCtrl.text = m.subject == '（无主题）' ? '' : m.subject;
          _bodyCtrl.text = m.bodyText;
          break;
        case 'reply':
          _toCtrl.text = m.fromAddr;
          _subjectCtrl.text = m.subject.startsWith('Re:') ? m.subject : 'Re: ${m.subject}';
          _bodyCtrl.text = '\n\n------------------ 原始邮件 ------------------\n发件人: ${m.fromAddr}\n主题: ${m.subject}\n\n${m.bodyText}';
          break;
        case 'reply_all':
          _toCtrl.text = m.fromAddr;
          _ccCtrl.text = m.toAddrs;
          _showCcBcc = m.toAddrs.isNotEmpty;
          _subjectCtrl.text = m.subject.startsWith('Re:') ? m.subject : 'Re: ${m.subject}';
          _bodyCtrl.text = '\n\n------------------ 原始邮件 ------------------\n发件人: ${m.fromAddr}\n主题: ${m.subject}\n\n${m.bodyText}';
          break;
        case 'forward':
          _subjectCtrl.text = m.subject.startsWith('Fwd:') ? m.subject : 'Fwd: ${m.subject}';
          _bodyCtrl.text = '\n\n------------------ 转发邮件 ------------------\n发件人: ${m.fromAddr}\n主题: ${m.subject}\n\n${m.bodyText}';
          break;
      }
    } else if (_accountId != null) {
      _applyDefaultSignature(_accountId!);
    }
  }

  void _applyDefaultSignature(int accountId) {
    final sigs = ref.read(mailProvider).signatures;
    final match = sigs.where((s) => s.accountId == accountId && s.isDefault).firstOrNull ??
        sigs.where((s) => s.accountId == null && s.isDefault).firstOrNull;
    if (match != null && match.contentHtml.isNotEmpty && _bodyCtrl.text.trim().isEmpty) {
      final plain = _stripHtml(match.contentHtml);
      _bodyCtrl.text = '\n\n--\n$plain';
    }
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _ccCtrl.dispose();
    _bccCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    setState(() {
      for (final f in files) {
        if (f.path != null) {
          _attachments.add((name: f.name, path: f.path!, size: f.lengthSync() ?? 0));
        }
      }
    });
  }

  String _toHtml(String text) {
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br/>');
    return '<div style="font-family:sans-serif;line-height:1.6;">$escaped</div>';
  }

  Future<void> _saveDraft() async {
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先绑定邮箱账号')));
      return;
    }
    setState(() => _savingDraft = true);
    try {
      final id = await ref.read(apiClientProvider).saveDraft(
            draftId: _draftId,
            accountId: _accountId!,
            to: _toCtrl.text.trim(),
            cc: _ccCtrl.text.trim(),
            bcc: _bccCtrl.text.trim(),
            subject: _subjectCtrl.text.trim(),
            bodyText: _bodyCtrl.text,
            bodyHtml: _toHtml(_bodyCtrl.text),
          );
      _draftId = id;
      await Future.wait([
        ref.read(mailProvider.notifier).loadMessages(silent: true),
        ref.read(mailProvider.notifier).refreshMetadata(),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('草稿已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(apiClientProvider).extractError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  Future<void> _send() async {
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择发件邮箱')));
      return;
    }
    if (_toCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写收件人邮箱')));
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).sendMessage(
            accountId: _accountId!,
            to: _toCtrl.text.trim(),
            cc: _ccCtrl.text.trim(),
            bcc: _bccCtrl.text.trim(),
            subject: _subjectCtrl.text.trim().isEmpty ? '（无主题）' : _subjectCtrl.text.trim(),
            bodyText: _bodyCtrl.text,
            bodyHtml: _toHtml(_bodyCtrl.text),
            inReplyTo: (widget.mode == 'reply' || widget.mode == 'reply_all')
                ? (widget.refMessage?.messageIdHeader ?? '')
                : '',
            draftId: _draftId,
            attachments: _attachments.map((e) => (name: e.name, path: e.path)).toList(),
          );
      await Future.wait([
        ref.read(mailProvider.notifier).loadMessages(silent: true),
        ref.read(mailProvider.notifier).refreshMetadata(),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('邮件发送成功')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(apiClientProvider).extractError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mail = ref.watch(mailProvider);
    final accounts = mail.accounts;
    final sigs = mail.signatures;

    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Text('撰写邮件', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: _savingDraft ? null : _saveDraft,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('存草稿'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('发送'),
              ),
              if (widget.isDialog)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _accountId,
            decoration: const InputDecoration(labelText: '发件邮箱', isDense: true),
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a.id, child: Text('${a.label} <${a.emailAddress}>')),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _toCtrl,
                  decoration: const InputDecoration(
                    labelText: '收件人（多个用逗号分隔）',
                    isDense: true,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _showCcBcc = !_showCcBcc),
                child: Text(_showCcBcc ? '隐藏抄送' : '抄送/密送'),
              ),
            ],
          ),
          if (_showCcBcc) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ccCtrl,
                    decoration: const InputDecoration(labelText: '抄送 (Cc)', isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _bccCtrl,
                    decoration: const InputDecoration(labelText: '密送 (Bcc)', isDense: true),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _subjectCtrl,
            decoration: const InputDecoration(labelText: '邮件主题', isDense: true),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.attach_file_rounded, size: 17),
                  label: const Text('添加附件'),
                ),
                if (sigs.isNotEmpty)
                  PopupMenuButton<MailSignature>(
                    onSelected: (s) {
                      setState(() {
                        _bodyCtrl.text = '${_bodyCtrl.text}\n\n--\n${_stripHtml(s.contentHtml)}';
                      });
                    },
                    itemBuilder: (_) => [
                      for (final s in sigs) PopupMenuItem(value: s, child: Text('插入签名：${s.name}')),
                    ],
                    child: const Chip(
                      avatar: Icon(Icons.draw_outlined, size: 16),
                      label: Text('插入签名'),
                    ),
                  ),
                PopupMenuButton<String>(
                  enabled: !_translating,
                  onSelected: _translateCompose,
                  itemBuilder: (_) => [
                    for (final lang in kTranslateLanguages)
                      PopupMenuItem<String>(value: lang.code, child: Text('翻译为 ${lang.name}')),
                  ],
                  child: Chip(
                    avatar: _translating
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.translate_rounded, size: 16),
                    label: Text(_translating ? '翻译中...' : '翻译正文'),
                  ),
                ),
              ],
            ),
          ),
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (int i = 0; i < _attachments.length; i++)
                    Chip(
                      label: Text(_attachments[i].name),
                      onDeleted: () => setState(() => _attachments.removeAt(i)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              controller: _bodyCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '输入邮件正文内容...',
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.isDialog) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('写邮件')),
      body: SafeArea(child: body),
    );
  }
}
