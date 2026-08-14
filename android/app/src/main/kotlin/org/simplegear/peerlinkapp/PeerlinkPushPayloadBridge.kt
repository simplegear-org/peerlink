package org.simplegear.peerlinkapp

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel

object PeerlinkPushPayloadBridge {
    private const val TAG = "PeerlinkPushPayload"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var methodChannel: MethodChannel? = null

    @Volatile
    private var latestPayloadJson: String? = null

    fun configure(channel: MethodChannel) {
        Log.d(TAG, "configure")
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeLatestPushPayload" -> {
                    val payload = latestPayloadJson
                    latestPayloadJson = null
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun pushPayload(json: String, notifyFlutter: Boolean = false) {
        Log.d(TAG, "store payload length=${json.length} notifyFlutter=$notifyFlutter")
        latestPayloadJson = json
        if (notifyFlutter) {
            mainHandler.post {
                val channel = methodChannel
                if (channel == null) {
                    Log.w(TAG, "skip notify reason=channel_missing")
                    return@post
                }
                try {
                    channel.invokeMethod("pushPayloadAvailable", null)
                } catch (error: Throwable) {
                    Log.e(TAG, "notify failed", error)
                }
            }
        }
    }
}
