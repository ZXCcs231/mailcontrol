package com.mailcontrol.mailcontrol_app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val PUSH_CHANNEL = "mailcontrol/android_push"
    }

    private var pushChannel: MethodChannel? = null
    private var pendingOpenMsgId: Long? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractOpenMsgId(intent)?.let { pendingOpenMsgId = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val msgId = extractOpenMsgId(intent) ?: return
        val ch = pushChannel
        if (ch != null) {
            ch.invokeMethod("onNotificationTap", "msg:$msgId")
        } else {
            pendingOpenMsgId = msgId
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PUSH_CHANNEL)
        pushChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startPushService" -> {
                    val args = call.arguments as? Map<*, *>
                    val baseUrl = (args?.get("baseUrl") as? String)?.trim() ?: ""
                    val token = (args?.get("token") as? String)?.trim() ?: ""
                    if (baseUrl.isNotEmpty() && token.isNotEmpty()) {
                        try {
                            MailPushService.start(this, baseUrl, token)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "stopPushService" -> {
                    try {
                        MailPushService.stop(this)
                    } catch (_: Exception) {
                    }
                    result.success(null)
                }
                "consumePendingMessageId" -> {
                    val id = pendingOpenMsgId
                    pendingOpenMsgId = null
                    result.success(id)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun extractOpenMsgId(intent: Intent?): Long? {
        if (intent == null) return null
        val id = intent.getLongExtra(MailPushService.EXTRA_OPEN_MSG_ID, 0L)
        if (id > 0L) {
            intent.removeExtra(MailPushService.EXTRA_OPEN_MSG_ID)
            return id
        }
        return null
    }
}
