import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers/mail_provider.dart';

class TagsScreen extends ConsumerWidget {
  final bool isDialog;
  const TagsScreen({super.key, this.isDialog = false});

  static const _colors = ['#3b82f6', '#ef4444', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899', '#06b6d4'];

  Future<void> _openEditor(BuildContext context, WidgetRef ref, [MailTag? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String color = existing?.color ?? '#3b82f6';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing != null ? '编辑标签' : '新建标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '标签名称', hintText: '如：重要 / 账单 / 工作'),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in _colors)
                    GestureDetector(
                      onTap: () => setState(() => color = c),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: parseHexColor(c),
                          shape: BoxShape.circle,
                          border: color == c ? Border.all(color: Colors.black, width: 2.5) : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final api = ref.read(apiClientProvider);
                if (existing != null) {
                  await api.updateTag(existing.id, nameCtrl.text.trim(), color);
                } else {
                  await api.createTag(nameCtrl.text.trim(), color);
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
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
              const Text('标签体系管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openEditor(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建标签'),
              ),
              if (isDialog)
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
        Expanded(
          child: mail.tags.isEmpty
              ? const Center(child: Text('暂无标签，点击右上角创建'))
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: mail.tags.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final t = mail.tags[idx];
                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(color: parseHexColor(t.color), shape: BoxShape.circle),
                        ),
                        title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 19),
                              onPressed: () => _openEditor(context, ref, t),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 19),
                              onPressed: () async {
                                await api.deleteTag(t.id);
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
    return Scaffold(appBar: AppBar(title: const Text('标签管理')), body: SafeArea(child: body));
  }
}
