import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../providers/mail_provider.dart';
import '../widgets/message_detail.dart';
import '../widgets/message_list.dart';
import '../widgets/sidebar.dart';
import 'account_modal.dart';
import 'compose_screen.dart';
import 'rules_screen.dart';
import 'signatures_screen.dart';
import 'tags_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _detailRouteOpen = false;

  void _openMobileDetailPage() {
    if (_detailRouteOpen || !mounted) return;
    _detailRouteOpen = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              body: SafeArea(
                child: MessageDetailView(
                  message: null,
                  isStandalone: true,
                  onReplyOrForward: (m, mode) => _openCompose(refMessage: m, mode: mode),
                  onDeleted: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        )
        .whenComplete(() => _detailRouteOpen = false);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(mailProvider.notifier).bootstrap());
  }

  void _openCompose({MailMessage? refMessage, String mode = 'new'}) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(
            width: 720,
            height: 640,
            child: ComposeScreen(refMessage: refMessage, mode: mode, isDialog: true),
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ComposeScreen(refMessage: refMessage, mode: mode)),
      );
    }
  }

  void _openAccountModal([MailAccount? existing]) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(
            width: 680,
            height: 660,
            child: AccountModal(existing: existing, isDialog: true),
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AccountModal(existing: existing)),
      );
    }
  }

  void _openPage(Widget page) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(width: 720, height: 620, child: page),
        ),
      );
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(mailProvider.select((s) => s.toastMessage), (prev, next) {
      if (next != null && next.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next)));
        ref.read(mailProvider.notifier).clearToast();
      }
    });

    ref.listen<int?>(mailProvider.select((s) => s.pendingOpenMessageId), (prev, next) {
      if (next == null) return;
      ref.read(mailProvider.notifier).clearPendingOpenMessageId();
      if (MediaQuery.of(context).size.width < 900) {
        _openMobileDetailPage();
      }
    });

    final mail = ref.watch(mailProvider);
    final notifier = ref.read(mailProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                Sidebar(
                  inDrawer: false,
                  onCompose: () => _openCompose(),
                  onOpenAccountModal: _openAccountModal,
                  onOpenRules: () => _openPage(const RulesScreen(isDialog: true)),
                  onOpenSignatures: () => _openPage(const SignaturesScreen(isDialog: true)),
                  onOpenTags: () => _openPage(const TagsScreen(isDialog: true)),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 390,
                  child: MessageList(
                    onAddAccount: () => _openAccountModal(),
                    onEditAccount: (acct) => _openAccountModal(acct),
                    onOpenMessage: (msg) => notifier.openMessage(msg.id),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: MessageDetailView(
                    message: mail.selectedMessage,
                    onReplyOrForward: (m, mode) => _openCompose(refMessage: m, mode: mode),
                  ),
                ),
              ],
            ),
          );
        }

        // 手机端 / 窄屏布局
        return Scaffold(
          key: _scaffoldKey,
          drawer: Drawer(
            child: Sidebar(
              inDrawer: true,
              onCompose: () => _openCompose(),
              onOpenAccountModal: _openAccountModal,
              onOpenRules: () => _openPage(const RulesScreen()),
              onOpenSignatures: () => _openPage(const SignaturesScreen()),
              onOpenTags: () => _openPage(const TagsScreen()),
            ),
          ),
          body: SafeArea(
            child: MessageList(
              onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
              onAddAccount: () => _openAccountModal(),
              onEditAccount: (acct) => _openAccountModal(acct),
              onOpenMessage: (msg) {
                if (_detailRouteOpen || ref.read(mailProvider).loadingDetail) return;
                unawaited(notifier.openMessage(msg.id));
                _openMobileDetailPage();
              },
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openCompose(),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('写邮件'),
          ),
        );
      },
    );
  }
}
