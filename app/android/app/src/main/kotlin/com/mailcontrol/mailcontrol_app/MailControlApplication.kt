package com.mailcontrol.mailcontrol_app

import android.app.Application

/**
 * 自定义 Application：替代默认 FlutterApplication，确保独立 `:push` 进程启动时
 * 不会初始化 Flutter 引擎或加载 Flutter 插件，把后台常驻内存压到最低。
 */
class MailControlApplication : Application()
