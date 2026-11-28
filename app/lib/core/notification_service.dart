import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

/// 根据新增邮件列表生成系统通知的标题、正文与点击载荷。
({String title, String body, String? payload}) buildNewMailNotificationContent({
  required String accountLabel,
  required List<MailMessage> freshMessages,
  int fallbackCount = 0,
}) {
  final trimmedAcct = accountLabel.trim();
  if (freshMessages.length == 1) {
    final m = freshMessages.first;
    final label = trimmedAcct.isNotEmpty ? trimmedAcct : m.accountLabel.trim();
    final tagPrefix = m.tags.isNotEmpty
        ? '[${m.tags.map((t) => t.name).take(2).join(' / ')}] '
        : '';
    final baseTitle = label.isNotEmpty ? '${m.senderDisplay}（$label）' : m.senderDisplay;
    final title = '$tagPrefix$baseTitle';
    final subj = m.subject.trim();
    final snip = m.snippet.trim();
    final body = subj.isNotEmpty ? subj : (snip.isNotEmpty ? snip : '收到一封新邮件');
    return (title: title, body: body, payload: 'msg:${m.id}');
  }

  if (freshMessages.length > 1) {
    final first = freshMessages.first;
    final label = trimmedAcct.isNotEmpty ? trimmedAcct : first.accountLabel.trim();
    final title = label.isNotEmpty
        ? '$label 收到 ${freshMessages.length} 封新邮件'
        : '收到 ${freshMessages.length} 封新邮件';
    final tagPrefix = first.tags.isNotEmpty ? '[${first.tags.first.name}] ' : '';
    final subj = first.subject.trim().isNotEmpty ? first.subject.trim() : first.snippet.trim();
    final body = subj.isNotEmpty
        ? '最新：$tagPrefix${first.senderDisplay} - $subj'
        : '最新来自：$tagPrefix${first.senderDisplay}';
    return (title: title, body: body, payload: 'msg:${first.id}');
  }

  final label = trimmedAcct.isNotEmpty ? trimmedAcct : '邮箱';
  final count = fallbackCount > 0 ? fallbackCount : 1;
  return (
    title: 'MailControl · 新邮件提醒',
    body: '$label 收到 $count 封新邮件',
    payload: null,
  );
}

class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _winChannel = MethodChannel('mailcontrol/windows_notifications');

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  void Function(String? payload)? _onTap;

  Future<void> init({void Function(String? payload)? onTap}) async {
    if (onTap != null) {
      _onTap = onTap;
    }
    if (_initialized) return;

    try {
      if (Platform.isWindows) {
        _winChannel.setMethodCallHandler((call) async {
          if (call.method == 'onTap') {
            _onTap?.call(call.arguments as String?);
          }
        });
        _initialized = true;
        return;
      }

      if (Platform.isAndroid) {
        const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
        const settings = InitializationSettings(android: androidInit);
        await _plugin.initialize(
          settings,
          onDidReceiveNotificationResponse: (resp) => _onTap?.call(resp.payload),
        );
        _initialized = true;
      }
    } catch (_) {}
  }

  Future<void> requestPermissionIfNeeded() async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> showNewMailNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) {
      await init(onTap: _onTap);
    }
    try {
      if (Platform.isWindows) {
        await _winChannel.invokeMethod<void>('show', {
          'title': title,
          'body': body,
          'payload': payload ?? '',
        });
        return;
      }

      if (Platform.isAndroid) {
        const androidDetails = AndroidNotificationDetails(
          'mailcontrol_new_mail',
          '新邮件提醒',
          channelDescription: '收到新邮件时弹出系统通知',
          importance: Importance.max,
          priority: Priority.high,
        );
        const details = NotificationDetails(android: androidDetails);
        await _plugin.show(
          id,
          title,
          body,
          details,
          payload: payload,
        );
      }
    } catch (_) {}
  }
}
