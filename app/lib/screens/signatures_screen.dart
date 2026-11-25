import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../providers/mail_provider.dart';

class SignaturesScreen extends ConsumerWidget {
  final bool isDialog;
  const SignaturesScreen({super.key, this.isDialog = false});

  Future<void> _openEditor(BuildContext context, WidgetRef ref, [MailSignature? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final contentCtrl = TextEditingController(
      text: (existing?.contentHtml ?? '').replaceAll('<br/>', '\n').replaceAll(RegExp(r'<[^>]+>'), ''),
    );
    int? accountId = existing?.accountId;
    bool isDefault = existing?.isDefault ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final accounts = ref.read(mailProvider).accounts;
          return AlertDialog(
            title: Text(existing != null ? '编辑签名模板' : '新建签名模板'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '签名名称', hintText: '如：商务签名'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: accountId,
                    decoration: const InputDecoration(labelText: '绑定邮箱', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('通用签名（所有邮箱）')),
                      for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.label)),
                    ],
                    onChanged: (v) => setState(() => accountId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: contentCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '签名内容', hintText: '祝好，\n张三'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('设为默认签名'),
                    value: isDefault,
                    onChanged: (v) => setState(() => isDefault = v ?? false),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final html = contentCtrl.text.replaceAll('\n', '<br/>');
                  final payload = {
                    'account_id': accountId,
                    'name': nameCtrl.text.trim(),
                    'content_html': html,
                    'is_default': isDefault,
                  };
                  final api = ref.read(apiClientProvider);
                  if (existing != null) {
                    await api.updateSignature(existing.id, payload);
                  } else {
                    await api.createSignature(payload);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true) {
      await ref.read(mailProvider.notifier).refreshMetadata();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mail = ref.watch(mailProvider);
    final api = ref.read(apiClientProvider);

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              const Text('多签名模板管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openEditor(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建签名'),
              ),
              if (isDialog)
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: mail.signatures.isEmpty
              ? const Center(child: Text('暂无签名模板，点击右上角新建'))
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: mail.signatures.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final s = mail.signatures[idx];
                    final acct = mail.accounts.where((a) => a.id == s.accountId).firstOrNull;
                    return Card(
                      child: ListTile(
                        title: Row(
                          children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (s.isDefault) ...[
                              const SizedBox(width: 8),
                              const Chip(label: Text('默认', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '${acct != null ? acct.label : "通用"} · ${s.contentHtml.replaceAll('<br/>', ' ').replaceAll(RegExp(r'<[^>]+>'), '')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 19),
                              onPressed: () => _openEditor(context, ref, s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 19),
                              onPressed: () async {
                                await api.deleteSignature(s.id);
                                await ref.read(mailProvider.notifier).refreshMetadata();
                              },
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

    if (isDialog) return body;
    return Scaffold(appBar: AppBar(title: const Text('签名模板')), body: SafeArea(child: body));
  }
}
