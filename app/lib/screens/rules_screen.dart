import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../providers/mail_provider.dart';

class RulesScreen extends ConsumerWidget {
  final bool isDialog;
  const RulesScreen({super.key, this.isDialog = false});

  Future<void> _openEditor(BuildContext context, WidgetRef ref, [MailRule? existing]) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => _RuleEditorDialog(existing: existing),
    );
    if (res == true) {
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
              const Text('邮件自动分类规则', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openEditor(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建规则'),
              ),
              if (isDialog)
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: mail.rules.isEmpty
              ? const Center(child: Text('暂无自动规则，点击右上角创建'))
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: mail.rules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final r = mail.rules[idx];
                    return Card(
                      child: ListTile(
                        title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${r.conditions.length} 个条件 (${r.matchMode == "any" ? "满足任一" : "全部满足"}) → ${r.actions.length} 个动作',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () async {
                                final matched = await api.runRule(r.id);
                                await Future.wait([
                                  ref.read(mailProvider.notifier).loadMessages(silent: true),
                                  ref.read(mailProvider.notifier).refreshMetadata(),
                                ]);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('规则「${r.name}」已处理 $matched 封邮件')),
                                  );
                                }
                              },
                              child: const Text('立即运行'),
                            ),
                            Switch(
                              value: r.enabled,
                              onChanged: (v) async {
                                await api.updateRule(r.id, {
                                  'account_id': r.accountId,
                                  'name': r.name,
                                  'enabled': v,
                                  'priority': r.priority,
                                  'match_mode': r.matchMode,
                                  'conditions': r.conditions.map((e) => e.toJson()).toList(),
                                  'actions': r.actions.map((e) => e.toJson()).toList(),
                                });
                                await ref.read(mailProvider.notifier).refreshMetadata();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 19),
                              onPressed: () => _openEditor(context, ref, r),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 19),
                              onPressed: () async {
                                await api.deleteRule(r.id);
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
    return Scaffold(appBar: AppBar(title: const Text('自动规则')), body: SafeArea(child: body));
  }
}

class _RuleEditorDialog extends ConsumerStatefulWidget {
  final MailRule? existing;
  const _RuleEditorDialog({this.existing});

  @override
  ConsumerState<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends ConsumerState<_RuleEditorDialog> {
  final _nameCtrl = TextEditingController();
  final _condValueCtrl = TextEditingController();
  String _matchMode = 'all';
  String _condField = 'from';
  String _condOp = 'contains';
  String _actionType = 'mark_read';
  String _actionValue = '';
  int? _accountId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _matchMode = e.matchMode;
      _accountId = e.accountId;
      if (e.conditions.isNotEmpty) {
        _condField = e.conditions.first.field;
        _condOp = e.conditions.first.operatorName;
        _condValueCtrl.text = e.conditions.first.value;
      }
      if (e.actions.isNotEmpty) {
        _actionType = e.actions.first.type;
        _actionValue = e.actions.first.value;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _condValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _condValueCtrl.text.trim().isEmpty) return;
    final payload = {
      'account_id': _accountId,
      'name': _nameCtrl.text.trim(),
      'enabled': widget.existing?.enabled ?? true,
      'match_mode': _matchMode,
      'conditions': [
        {'field': _condField, 'operator': _condOp, 'value': _condValueCtrl.text.trim()},
      ],
      'actions': [
        {
          'type': _actionType,
          if (_actionValue.isNotEmpty) 'value': _actionValue,
        },
      ],
    };
    final api = ref.read(apiClientProvider);
    if (widget.existing != null) {
      await api.updateRule(widget.existing!.id, payload);
    } else {
      await api.createRule(payload);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final mail = ref.watch(mailProvider);
    return AlertDialog(
      title: Text(widget.existing != null ? '编辑规则' : '新建自动分类规则'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: '规则名称', hintText: '如：GitHub 通知自动归档'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: _accountId,
                decoration: const InputDecoration(labelText: '适用邮箱', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部已绑定邮箱')),
                  for (final a in mail.accounts) DropdownMenuItem(value: a.id, child: Text(a.label)),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _condField,
                      decoration: const InputDecoration(labelText: '字段', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'from', child: Text('发件人')),
                        DropdownMenuItem(value: 'to', child: Text('收件人')),
                        DropdownMenuItem(value: 'subject', child: Text('主题')),
                        DropdownMenuItem(value: 'body', child: Text('正文')),
                      ],
                      onChanged: (v) => setState(() => _condField = v ?? 'from'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _condOp,
                      decoration: const InputDecoration(labelText: '条件', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'contains', child: Text('包含')),
                        DropdownMenuItem(value: 'not_contains', child: Text('不包含')),
                        DropdownMenuItem(value: 'equals', child: Text('等于')),
                        DropdownMenuItem(value: 'starts_with', child: Text('开头是')),
                        DropdownMenuItem(value: 'ends_with', child: Text('结尾是')),
                      ],
                      onChanged: (v) => setState(() => _condOp = v ?? 'contains'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _condValueCtrl,
                decoration: const InputDecoration(labelText: '匹配关键词 / 邮箱', isDense: true),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _actionType,
                decoration: const InputDecoration(labelText: '执行动作', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'mark_read', child: Text('自动标为已读')),
                  DropdownMenuItem(value: 'star', child: Text('自动加星标')),
                  DropdownMenuItem(value: 'add_tag', child: Text('自动打标签')),
                  DropdownMenuItem(value: 'move_folder', child: Text('移动到归档/回收站')),
                ],
                onChanged: (v) => setState(() {
                  _actionType = v ?? 'mark_read';
                  _actionValue = _actionType == 'move_folder'
                      ? 'archive'
                      : (_actionType == 'add_tag' && mail.tags.isNotEmpty ? mail.tags.first.id.toString() : '');
                }),
              ),
              if (_actionType == 'add_tag' && mail.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: mail.tags.any((t) => t.id.toString() == _actionValue)
                      ? _actionValue
                      : mail.tags.first.id.toString(),
                  decoration: const InputDecoration(labelText: '选择标签', isDense: true),
                  items: [
                    for (final t in mail.tags)
                      DropdownMenuItem(value: t.id.toString(), child: Text(t.name)),
                  ],
                  onChanged: (v) => setState(() => _actionValue = v ?? ''),
                ),
              ],
              if (_actionType == 'move_folder') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: (_actionValue == 'trash' || _actionValue == 'spam') ? _actionValue : 'archive',
                  decoration: const InputDecoration(labelText: '目标文件夹', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'archive', child: Text('归档')),
                    DropdownMenuItem(value: 'trash', child: Text('回收站')),
                    DropdownMenuItem(value: 'spam', child: Text('垃圾邮件')),
                  ],
                  onChanged: (v) => setState(() => _actionValue = v ?? 'archive'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('保存规则')),
      ],
    );
  }
}
