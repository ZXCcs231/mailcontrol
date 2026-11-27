package com.mailcontrol.mailcontrol_app

import android.content.Context
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.Properties

data class PushState(
    val baseUrl: String,
    val token: String,
    val lastSeenId: Long,
)

/**
 * 轻量状态文件存储：仅由 `:push` 独立进程读写，避免跨进程 SharedPreferences 缓存不一致。
 */
object PushStateStore {
    private const val FILE_NAME = "mailcontrol_push_state.properties"
    private const val KEY_BASE_URL = "base_url"
    private const val KEY_TOKEN = "token"
    private const val KEY_LAST_SEEN_ID = "last_seen_id"

    private val lock = Any()

    @JvmStatic
    fun load(context: Context): PushState {
        synchronized(lock) {
            val file = File(context.filesDir, FILE_NAME)
            if (!file.exists()) {
                return PushState("", "", 0L)
            }
            val props = Properties()
            try {
                FileInputStream(file).use { props.load(it) }
            } catch (_: Exception) {
                return PushState("", "", 0L)
            }
            val baseUrl = props.getProperty(KEY_BASE_URL, "").trim()
            val token = props.getProperty(KEY_TOKEN, "").trim()
            val lastSeenId = props.getProperty(KEY_LAST_SEEN_ID, "0").toLongOrNull() ?: 0L
            return PushState(baseUrl, token, lastSeenId)
        }
    }

    @JvmStatic
    fun saveCredentials(context: Context, baseUrl: String, token: String): PushState {
        synchronized(lock) {
            val cleanUrl = baseUrl.trim().trimEnd('/')
            val cleanToken = token.trim()
            val prev = load(context)
            val nextLastSeenId = if (prev.baseUrl == cleanUrl && prev.lastSeenId > 0L) {
                prev.lastSeenId
            } else {
                0L
            }
            writeLocked(context, cleanUrl, cleanToken, nextLastSeenId)
            return PushState(cleanUrl, cleanToken, nextLastSeenId)
        }
    }

    @JvmStatic
    fun updateLastSeenId(context: Context, lastSeenId: Long) {
        synchronized(lock) {
            val prev = load(context)
            if (prev.baseUrl.isEmpty() || prev.token.isEmpty()) return
            if (lastSeenId <= prev.lastSeenId) return
            writeLocked(context, prev.baseUrl, prev.token, lastSeenId)
        }
    }

    @JvmStatic
    fun clear(context: Context) {
        synchronized(lock) {
            val file = File(context.filesDir, FILE_NAME)
            if (file.exists()) {
                file.delete()
            }
        }
    }

    private fun writeLocked(context: Context, baseUrl: String, token: String, lastSeenId: Long) {
        val file = File(context.filesDir, FILE_NAME)
        val props = Properties().apply {
            setProperty(KEY_BASE_URL, baseUrl)
            setProperty(KEY_TOKEN, token)
            setProperty(KEY_LAST_SEEN_ID, lastSeenId.toString())
        }
        try {
            FileOutputStream(file).use { props.store(it, null) }
        } catch (_: Exception) {
        }
    }
}
