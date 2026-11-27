package com.mailcontrol.mailcontrol_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 在独立 `:push` 进程中监听开机与应用更新广播，若已保存登录态则自动恢复推送服务。
 */
class PushBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }
        val state = PushStateStore.load(context)
        if (state.baseUrl.isEmpty() || state.token.isEmpty()) {
            return
        }
        try {
            MailPushService.start(context, state.baseUrl, state.token)
        } catch (_: Exception) {
        }
    }
}
