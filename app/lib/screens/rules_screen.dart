import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
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

  Future<void> _openPresetsDialog(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiClientProvider);
    List<Map<String, dynamic>> presets = [];
    try {
      presets = await api.getRulePresets();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(api.extractError(e))));
      }
      return;
    }
    if (!context.mounted) return;

    final existingNames = ref.read(mailProvider).rules.map((r) => r.name).toSet();
    final selectedIds = <String>{
      for (final p in presets)
        if (!existingNames.contains(p['name']?.toString() ?? '')) p['id'].toString(),
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('导入常用自动分类预设'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in presets)
                    Builder(
                      builder: (_) {
                        final id = p['id'].toString();
                        final name = p['name'].toString();
                        final desc = p['description']?.toString() ?? '';
                        final exists = existingNames.contains(name);
                        return CheckboxListTile(
                          value: exists ? true : selectedIds.contains(id),
                          onChanged: exists
                              ? null
                              : (v) => setState(() {
                                    if (v == true) {
                                      selectedIds.add(id);
                                    } else {
                                      selectedIds.remove(id);
                                    }
                                  }),
                          title: Row(
                            children: [
                              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                              if (exists)
                                const Text('已导入', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                            ],
                          ),
                          subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: selectedIds.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: Text('导入选中 (${selectedIds.length})'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final added = await api.applyRulePresets(presetIds: selectedIds.toList());
    await ref.read(mailProvider.notifier).refreshMetadata();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(added > 0 ? '成功导入 $added 条预设规则及对应标签' : '所选预设规则均已存在')),
      );
    }
  }

  String _summarizeRule(MailRule r) {
    final kws = r.conditions.map((c) => c.value).where((v) => v.isNotEmpty).take(3).join(' / ');
    final actNames = r.actions.map((a) => switch (a.type) {
          'mark_read' => '标为已读',
          'star' => '加星标',
          'add_tag' => '打标签',
          'move_folder' => a.value == 'trash' ? '移至回收站' : '归档',
          'delete' => '删除',
          _ => a.type,
        }).join(' + ');
    return '关键词：$kws${r.conditions.length > 3 ? " 等" : ""} → $actNames';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mail = ref.watch(mailProvider);
    final api = ref.read(apiClientProvider);
    final pal = context.palette;

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text('邮件自动分类规则', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              OutlinedButton.icon(
                onPressed: () => _openPresetsDialog(context, ref),
                icon: const Icon(Icons.auto_awesome_outlined, size: 17),
                label: const Text('导入常用预设'),
              ),
              const SizedBox(width: 8),
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
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('暂无自动规则，可点击一键导入内置常用预设'),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => _openPresetsDialog(context, ref),
                        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                        label: const Text('导入常用预设规则'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: mail.rules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final r = mail.rules[idx];
                    return Card(
                      child: ListTile(
                        title: Text(r.name, style: TextStyle(fontWeight: FontWeight.w600, color: pal.textPrimary)),
                        subtitle: Text(
                          _summarizeRule(r),
                          style: TextStyle(fontSize: 12.5, color: pal.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
