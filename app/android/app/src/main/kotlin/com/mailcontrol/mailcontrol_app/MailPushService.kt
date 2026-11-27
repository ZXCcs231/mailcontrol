package com.mailcontrol.mailcontrol_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.IBinder
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.atomic.AtomicInteger

/**
 * 运行在独立 `:push` 进程中的纯原生低内存后台推送服务：
 * - 零第三方网络/JSON依赖，使用系统 HttpURLConnection + 2KB 流式缓冲 + org.json；
 * - 监听网络切换，无网时彻底挂起不轮询，联网即秒连；
 * - 退出登录或服务端返回 401 时立即清理凭据并自毁，内存归零。
 */
class MailPushService : Service() {
    companion object {
        const val ACTION_START = "com.mailcontrol.mailcontrol_app.action.START_PUSH"
        const val ACTION_STOP = "com.mailcontrol.mailcontrol_app.action.STOP_PUSH"
        const val EXTRA_BASE_URL = "base_url"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_OPEN_MSG_ID = "mailcontrol_open_msg_id"

        private const val CHANNEL_STATUS = "mailcontrol_push_status"
        private const val CHANNEL_NEW_MAIL = "mailcontrol_new_mail"
        private const val STATUS_NOTIFICATION_ID = 9001

        fun start(context: Context, baseUrl: String, token: String) {
            val cleanUrl = baseUrl.trim().trimEnd('/')
            val cleanToken = token.trim()
            if (cleanUrl.isEmpty() || cleanToken.isEmpty()) return

            val intent = Intent(context, MailPushService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_BASE_URL, cleanUrl)
                putExtra(EXTRA_TOKEN, cleanToken)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, MailPushService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.startService(intent)
            } catch (_: Exception) {
                context.stopService(Intent(context, MailPushService::class.java))
            }
        }
    }

    private val workerGen = AtomicInteger(0)
    private val wakeLockObj = Object()

    @Volatile
    private var workerThread: Thread? = null

    @Volatile
    private var activeConn: HttpURLConnection? = null

    @Volatile
    private var currentBaseUrl: String = ""

    @Volatile
    private var currentToken: String = ""

    @Volatile
    private var networkAvailable: Boolean = true

    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannels()
        startForegroundCompat()

        val action = intent?.action
        if (action == ACTION_STOP) {
            stopWorker()
            PushStateStore.clear(this)
            currentBaseUrl = ""
            currentToken = ""
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        val extraUrl = intent?.getStringExtra(EXTRA_BASE_URL)?.trim()?.trimEnd('/')
        val extraToken = intent?.getStringExtra(EXTRA_TOKEN)?.trim()
        val state = if (!extraUrl.isNullOrEmpty() && !extraToken.isNullOrEmpty()) {
            PushStateStore.saveCredentials(this, extraUrl, extraToken)
        } else {
            PushStateStore.load(this)
        }

        if (state.baseUrl.isEmpty() || state.token.isEmpty()) {
            stopWorker()
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        registerNetworkObserver()

        val credChanged = state.baseUrl != currentBaseUrl || state.token != currentToken
        val alive = workerThread?.isAlive == true
        if (credChanged || !alive) {
            currentBaseUrl = state.baseUrl
            currentToken = state.token
            startWorker(state.baseUrl, state.token)
        }

        return START_STICKY
    }

    override fun onDestroy() {
        unregisterNetworkObserver()
        stopWorker()
        super.onDestroy()
    }

    private fun startForegroundCompat() {
        val notification = buildStatusNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                STATUS_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else {
            startForeground(STATUS_NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return

        if (nm.getNotificationChannel(CHANNEL_STATUS) == null) {
            val statusChannel = NotificationChannel(
                CHANNEL_STATUS,
                "后台实时推送状态",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "保持轻量实时连接，用于在关闭应用后接收新邮件提醒"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            nm.createNotificationChannel(statusChannel)
        }

        if (nm.getNotificationChannel(CHANNEL_NEW_MAIL) == null) {
            val mailChannel = NotificationChannel(
                CHANNEL_NEW_MAIL,
                "新邮件提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "收到新邮件时弹出系统通知"
            }
            nm.createNotificationChannel(mailChannel)
        }
    }

    private fun buildStatusNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, piFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_STATUS)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_MIN)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MailControl 后台收信中")
            .setContentText("保持轻量连接，有新邮件将即时提醒")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun registerNetworkObserver() {
        if (networkCallback != null) return
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        connectivityManager = cm
        networkAvailable = queryNetworkAvailable(cm)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    networkAvailable = true
                    synchronized(wakeLockObj) { wakeLockObj.notifyAll() }
                }

                override fun onLost(network: Network) {
                    networkAvailable = queryNetworkAvailable(cm)
                    if (!networkAvailable) {
                        try {
                            activeConn?.disconnect()
                        } catch (_: Exception) {
                        }
                    }
                }
            }
            try {
                cm.registerDefaultNetworkCallback(cb)
                networkCallback = cb
            } catch (_: Exception) {
            }
        }
    }

    private fun unregisterNetworkObserver() {
        val cm = connectivityManager
        val cb = networkCallback
        networkCallback = null
        if (cm != null && cb != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                cm.unregisterNetworkCallback(cb)
            } catch (_: Exception) {
            }
        }
    }

    private fun queryNetworkAvailable(cm: ConnectivityManager): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val net = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(net) ?: return false
            return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        }
        @Suppress("DEPRECATION")
        return cm.activeNetworkInfo?.isConnected == true
    }

    private fun startWorker(baseUrl: String, token: String) {
        stopWorker()
        val gen = workerGen.incrementAndGet()
        val t = Thread({ runSseLoop(baseUrl, token, gen) }, "mc-push-$gen").apply {
            isDaemon = true
        }
        workerThread = t
        t.start()
    }

    private fun stopWorker() {
        workerGen.incrementAndGet()
        try {
            activeConn?.disconnect()
        } catch (_: Exception) {
        }
        activeConn = null
        synchronized(wakeLockObj) { wakeLockObj.notifyAll() }
        workerThread?.interrupt()
        workerThread = null
    }

    private fun runSseLoop(baseUrl: String, token: String, gen: Int) {
        var backoffSec = 3L
        var hadConnectedOnce = false

        while (gen == workerGen.get() && !Thread.currentThread().isInterrupted) {
            if (!networkAvailable) {
                waitWhileOffline(gen)
                continue
            }

            if (PushStateStore.load(this).lastSeenId == 0L) {
                initBaseline(baseUrl, token)
            }

            var conn: HttpURLConnection? = null
            try {
                val encodedToken = URLEncoder.encode(token, "UTF-8")
                val url = URL("$baseUrl/api/events?token=$encodedToken")
                conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    setRequestProperty("Accept", "text/event-stream")
                    setRequestProperty("Cache-Control", "no-cache")
                    connectTimeout = 15_000
                    readTimeout = 90_000
                    useCaches = false
                }
                activeConn = conn

                val code = conn.responseCode
                if (code == 401 || code == 403) {
                    PushStateStore.clear(this)
                    stopForegroundCompat()
                    stopSelf()
                    return
                }
                if (code == 200) {
                    backoffSec = 3L
                    if (hadConnectedOnce) {
                        fetchAndNotify(baseUrl, token, 0L, "", 0)
                    }
                    hadConnectedOnce = true

                    BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8), 2048).use { reader ->
                        while (gen == workerGen.get() && !Thread.currentThread().isInterrupted) {
                            val line = reader.readLine() ?: break
                            if (line.startsWith("data:")) {
                                val raw = line.substring(5).trim()
                                if (raw.isNotEmpty()) {
                                    handleSsePayload(baseUrl, token, raw)
                                }
                            }
                        }
                    }
                }
            } catch (_: Exception) {
                // 断网或超时后自动退避重连
            } finally {
                activeConn = null
                try {
                    conn?.disconnect()
                } catch (_: Exception) {
                }
            }

            if (gen != workerGen.get() || Thread.currentThread().isInterrupted) break
            waitSeconds(backoffSec, gen)
            backoffSec = (backoffSec * 2).coerceAtMost(60L)
        }
    }

    private fun waitWhileOffline(gen: Int) {
        synchronized(wakeLockObj) {
            if (gen == workerGen.get() && !networkAvailable) {
                try {
                    wakeLockObj.wait(60_000L)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
        }
    }

    private fun waitSeconds(seconds: Long, gen: Int) {
        synchronized(wakeLockObj) {
            if (gen == workerGen.get()) {
                try {
                    wakeLockObj.wait(seconds * 1000L)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
        }
    }

    private fun handleSsePayload(baseUrl: String, token: String, rawJson: String) {
        try {
            val obj = JSONObject(rawJson)
            if (obj.optString("type") != "new_messages") return
            val accountId = obj.optLong("account_id", 0L)
            val label = obj.optString("label", "")
            val count = obj.optInt("count", 0)
            fetchAndNotify(baseUrl, token, accountId, label, count)
        } catch (_: Exception) {
        }
    }

    private fun initBaseline(baseUrl: String, token: String) {
        val body = httpGetJson(baseUrl, token, "/api/messages?view=inbox&page=1&page_size=20") ?: return
        try {
            val items = body.optJSONArray("items") ?: return
            var maxId = 0L
            for (i in 0 until items.length()) {
                val id = items.optJSONObject(i)?.optLong("id", 0L) ?: 0L
                if (id > maxId) maxId = id
            }
            if (maxId > 0L) {
                PushStateStore.updateLastSeenId(this, maxId)
            }
        } catch (_: Exception) {
        }
    }

    private fun fetchAndNotify(
        baseUrl: String,
        token: String,
        accountId: Long,
        fallbackLabel: String,
        fallbackCount: Int,
    ) {
        val query = StringBuilder("/api/messages?view=inbox&page=1&page_size=5")
        if (accountId > 0L) {
            query.append("&account_id=").append(accountId)
        }
        val body = httpGetJson(baseUrl, token, query.toString())
        val lastSeenId = PushStateStore.load(this).lastSeenId

        val fresh = ArrayList<JSONObject>(5)
        var nextMaxId = lastSeenId

        val items = body?.optJSONArray("items")
        if (items != null) {
            for (i in 0 until items.length()) {
                val m = items.optJSONObject(i) ?: continue
                val id = m.optLong("id", 0L)
                if (id > nextMaxId) nextMaxId = id
                val isRead = m.optBoolean("is_read", false)
                if (!isRead && id > lastSeenId) {
                    fresh.add(m)
                }
            }
        }

        if (nextMaxId > lastSeenId) {
            PushStateStore.updateLastSeenId(this, nextMaxId)
        }

        if (fresh.isEmpty() && fallbackCount <= 0) return

        val (title, text, openMsgId) = buildNotificationContent(fallbackLabel, fresh, fallbackCount)
        val notifId = if (openMsgId > 0L) {
            (openMsgId and 0x7fffffffL).toInt()
        } else {
            (System.currentTimeMillis() and 0x7fffffffL).toInt()
        }
        showNewMailNotification(notifId, title, text, openMsgId)
    }

    private fun buildNotificationContent(
        accountLabel: String,
        fresh: List<JSONObject>,
        fallbackCount: Int,
    ): Triple<String, String, Long> {
        val trimmedAcct = accountLabel.trim()
        if (fresh.size == 1) {
            val m = fresh[0]
            val id = m.optLong("id", 0L)
            val label = trimmedAcct.ifEmpty { m.optString("account_label", "").trim() }
            val sender = senderDisplay(m)
            val tagPrefix = extractTagPrefix(m.optJSONArray("tags"), maxTags = 2)
            val baseTitle = if (label.isNotEmpty()) "$sender（$label）" else sender
            val subj = m.optString("subject", "").trim()
            val snip = m.optString("snippet", "").trim()
            val body = subj.ifEmpty { snip.ifEmpty { "收到一封新邮件" } }
            return Triple("$tagPrefix$baseTitle", body, id)
        }

        if (fresh.size > 1) {
            val first = fresh[0]
            val id = first.optLong("id", 0L)
            val label = trimmedAcct.ifEmpty { first.optString("account_label", "").trim() }
            val title = if (label.isNotEmpty()) {
                "$label 收到 ${fresh.size} 封新邮件"
            } else {
                "收到 ${fresh.size} 封新邮件"
            }
            val sender = senderDisplay(first)
            val tagPrefix = extractTagPrefix(first.optJSONArray("tags"), maxTags = 1)
            val subj = first.optString("subject", "").trim().ifEmpty {
                first.optString("snippet", "").trim()
            }
            val body = if (subj.isNotEmpty()) {
                "最新：$tagPrefix$sender - $subj"
            } else {
                "最新来自：$tagPrefix$sender"
            }
            return Triple(title, body, id)
        }

        val label = trimmedAcct.ifEmpty { "邮箱" }
        val count = if (fallbackCount > 0) fallbackCount else 1
        return Triple("MailControl · 新邮件提醒", "$label 收到 $count 封新邮件", 0L)
    }

    private fun senderDisplay(m: JSONObject): String {
        val name = m.optString("from_name", "").trim()
        return name.ifEmpty { m.optString("from_addr", "").trim().ifEmpty { "未知发件人" } }
    }

    private fun extractTagPrefix(tags: JSONArray?, maxTags: Int): String {
        if (tags == null || tags.length() == 0) return ""
        val names = ArrayList<String>(maxTags)
        val limit = tags.length().coerceAtMost(maxTags)
        for (i in 0 until limit) {
            val name = tags.optJSONObject(i)?.optString("name", "")?.trim() ?: ""
            if (name.isNotEmpty()) names.add(name)
        }
        return if (names.isEmpty()) "" else "[${names.joinToString(" / ")}] "
    }

    private fun showNewMailNotification(notifId: Int, title: String, text: String, openMsgId: Long) {
        ensureChannels()
        val nm = getSystemService(NotificationManager::class.java) ?: return

        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (openMsgId > 0L) {
                putExtra(EXTRA_OPEN_MSG_ID, openMsgId)
            }
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pendingIntent = PendingIntent.getActivity(this, notifId, tapIntent, piFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_NEW_MAIL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        nm.notify(notifId, notification)
    }

    private fun httpGetJson(baseUrl: String, token: String, pathAndQuery: String): JSONObject? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL("$baseUrl$pathAndQuery").openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Accept", "application/json")
                connectTimeout = 10_000
                readTimeout = 12_000
                useCaches = false
            }
            val code = conn.responseCode
            if (code == 401 || code == 403) {
                PushStateStore.clear(this)
                return null
            }
            if (code !in 200..299) return null

            val sb = StringBuilder(4096)
            BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8), 2048).use { reader ->
                val buf = CharArray(2048)
                while (true) {
                    val read = reader.read(buf)
                    if (read <= 0) break
                    sb.append(buf, 0, read)
                }
            }
            JSONObject(sb.toString())
        } catch (_: Exception) {
            null
        } finally {
            try {
                conn?.disconnect()
            } catch (_: Exception) {
            }
        }
    }
}
