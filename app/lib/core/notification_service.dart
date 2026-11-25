import 'dart:io';

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
    final title = label.isNotEmpty ? '${m.senderDisplay}（$label）' : m.senderDisplay;
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
    final subj = first.subject.trim().isNotEmpty ? first.subject.trim() : first.snippet.trim();
    final body = subj.isNotEmpty ? '最新：${first.senderDisplay} - $subj' : '最新来自：${first.senderDisplay}';
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

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  void Function(String? payload)? _onTap;

  Future<void> init({void Function(String? payload)? onTap}) async {
    if (onTap != null) {
      _onTap = onTap;
    }
    if (_initialized) return;

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const windowsInit = WindowsInitializationSettings(
        appName: 'MailControl',
        appUserModelId: 'com.mailcontrol.mailcontrol_app',
        guid: '9f3a6d14-2c7b-4f8e-a1d5-7b3c9e041f22',
      );
      const settings = InitializationSettings(
        android: androidInit,
        windows: windowsInit,
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (resp) => _onTap?.call(resp.payload),
      );
      _initialized = true;
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
      const androidDetails = AndroidNotificationDetails(
        'mailcontrol_new_mail',
        '新邮件提醒',
        channelDescription: '收到新邮件时弹出系统通知',
        importance: Importance.max,
        priority: Priority.high,
      );
      const windowsDetails = WindowsNotificationDetails();
      const details = NotificationDetails(
        android: androidDetails,
        windows: windowsDetails,
      );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (_) {}
  }
}
