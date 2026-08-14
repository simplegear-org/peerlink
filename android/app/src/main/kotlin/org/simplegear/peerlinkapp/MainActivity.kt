package org.simplegear.peerlinkapp

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.provider.CallLog
import java.io.File
import java.io.FileOutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "peerlink/deep_links/methods"
    private val eventChannelName = "peerlink/deep_links/events"
    private val callLogMethodChannelName = "peerlink/android_call_log/methods"
    private val callNotificationsMethodChannelName = "peerlink/android_call_notifications/methods"
    private val mediaThumbnailMethodChannelName = "peerlink/media_thumbnail/methods"
    private val pushPayloadMethodChannelName = "peerlink/push_payload/methods"
    private val writeCallLogRequestCode = 7301
    private var initialLink: String? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingLink: String? = null
    private var pendingCallLogWrite: PendingCallLogWrite? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> result.success(initialLink)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callLogMethodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recordCall" -> recordCallLog(call.arguments, result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callNotificationsMethodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cancelAllCallNotifications" -> {
                        PeerlinkCallNotifications.cancelAll(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaThumbnailMethodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "generateImageThumbnail" -> Thread {
                        val generated = generateImageThumbnail(call.arguments)
                        runOnUiThread {
                            result.success(generated)
                        }
                    }.start()
                    else -> result.notImplemented()
                }
            }

        PeerlinkPushPayloadBridge.configure(
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pushPayloadMethodChannelName)
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    pendingLink?.let {
                        events?.success(it)
                        pendingLink = null
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        captureInitialLink(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != writeCallLogRequestCode) {
            return
        }
        val pending = pendingCallLogWrite ?: return
        pendingCallLogWrite = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            pending.result.success(false)
            return
        }
        pending.result.success(insertCallLog(pending.payload))
    }

    override fun onResume() {
        super.onResume()
        PeerlinkAppVisibility.markForeground()
    }

    override fun onPause() {
        PeerlinkAppVisibility.markBackground()
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = extractDeepLink(intent) ?: return
        eventSink?.success(link) ?: run {
            pendingLink = link
        }
    }

    private fun captureInitialLink(intent: Intent?) {
        if (initialLink != null) {
            return
        }
        initialLink = extractDeepLink(intent)
    }

    private fun extractDeepLink(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) {
            return null
        }
        val uri = intent.data ?: return null
        if (isSupportedPeerlinkUri(uri) || isSupportedWebDeepLink(uri)) {
            return uri.toString()
        }
        return null
    }

    private fun isSupportedPeerlinkUri(uri: Uri): Boolean {
        if (uri.scheme != "peerlink") {
            return false
        }
        return when (uri.host) {
            "invite", "pair", "config", "call" -> true
            else -> false
        }
    }

    private fun isSupportedWebDeepLink(uri: Uri): Boolean {
        if (uri.scheme != "https" && uri.scheme != "http") {
            return false
        }
        val host = uri.host ?: return false
        if (host != "simplegear.org" && host != "simplegear-org.github.io") {
            return false
        }
        if (hasSupportedDeepLinkPath(uri.pathSegments)) {
            return true
        }
        val fragmentUri = fragmentUri(uri) ?: return false
        return hasSupportedDeepLinkPath(fragmentUri.pathSegments)
    }

    private fun hasSupportedDeepLinkPath(pathSegments: List<String>): Boolean {
        return pathSegments.any {
            it == "invite" || it == "pair" || it == "config"
        }
    }

    private fun fragmentUri(uri: Uri): Uri? {
        val fragment = uri.fragment?.trim().orEmpty()
        if (fragment.isEmpty()) {
            return null
        }
        if (!fragment.startsWith("/") &&
            !fragment.contains("://") &&
            fragment.contains("=")
        ) {
            return Uri.parse("https://peerlink.local/?$fragment")
        }
        val normalized = if (fragment.startsWith("/")) {
            "https://peerlink.local$fragment"
        } else {
            fragment
        }
        return Uri.parse(normalized)
    }

    private fun recordCallLog(arguments: Any?, result: MethodChannel.Result) {
        val payload = arguments as? Map<*, *> ?: run {
            result.success(false)
            return
        }
        if (!hasWriteCallLogPermission()) {
            pendingCallLogWrite?.result?.success(false)
            pendingCallLogWrite = PendingCallLogWrite(payload, result)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                requestPermissions(
                    arrayOf(Manifest.permission.WRITE_CALL_LOG),
                    writeCallLogRequestCode
                )
            } else {
                result.success(false)
            }
            return
        }
        result.success(insertCallLog(payload))
    }

    private fun hasWriteCallLogPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.WRITE_CALL_LOG) ==
                PackageManager.PERMISSION_GRANTED
    }

    private fun insertCallLog(payload: Map<*, *>): Boolean {
        return try {
            val peerId = payload["peerId"] as? String ?: ""
            val contactName = payload["contactName"] as? String ?: peerId
            val direction = payload["direction"] as? String ?: ""
            val status = payload["status"] as? String ?: ""
            val startedAtMs = (payload["startedAtMs"] as? Number)?.toLong()
                ?: System.currentTimeMillis()
            val durationSeconds = (payload["durationSeconds"] as? Number)?.toLong() ?: 0L
            val values = ContentValues().apply {
                put(CallLog.Calls.NUMBER, peerId.ifBlank { contactName })
                put(CallLog.Calls.CACHED_NAME, contactName.ifBlank { peerId })
                put(CallLog.Calls.DATE, startedAtMs)
                put(CallLog.Calls.DURATION, durationSeconds)
                put(CallLog.Calls.TYPE, callLogType(direction, status))
                put(CallLog.Calls.NEW, if (status == "missed") 1 else 0)
            }
            contentResolver.insert(CallLog.Calls.CONTENT_URI, values) != null
        } catch (_: SecurityException) {
            false
        } catch (_: Throwable) {
            false
        }
    }

    private fun generateImageThumbnail(arguments: Any?): Boolean {
        val payload = arguments as? Map<*, *> ?: return false
        val sourcePath = payload["sourcePath"] as? String ?: return false
        val destinationPath = payload["destinationPath"] as? String ?: return false
        val maxWidth = (payload["maxWidth"] as? Number)?.toInt() ?: 640
        val maxHeight = (payload["maxHeight"] as? Number)?.toInt() ?: 440
        return try {
            val bounds = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(sourcePath, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                return false
            }
            val options = BitmapFactory.Options().apply {
                inSampleSize = imageSampleSize(bounds.outWidth, bounds.outHeight, maxWidth, maxHeight)
            }
            val decoded = BitmapFactory.decodeFile(sourcePath, options) ?: return false
            val oriented = orientBitmap(decoded, sourcePath)
            val scaled = scaleBitmap(oriented, maxWidth, maxHeight)
            File(destinationPath).parentFile?.mkdirs()
            FileOutputStream(destinationPath).use { output ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 76, output)
            }
            if (scaled != oriented) {
                scaled.recycle()
            }
            if (oriented != decoded) {
                oriented.recycle()
            }
            decoded.recycle()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun orientBitmap(bitmap: Bitmap, sourcePath: String): Bitmap {
        val orientation = try {
            ExifInterface(sourcePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            else -> return bitmap
        }
        return try {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (_: Exception) {
            bitmap
        }
    }

    private fun imageSampleSize(width: Int, height: Int, maxWidth: Int, maxHeight: Int): Int {
        var sample = 1
        var nextWidth = width / 2
        var nextHeight = height / 2
        while (nextWidth / sample >= maxWidth && nextHeight / sample >= maxHeight) {
            sample *= 2
        }
        return sample.coerceAtLeast(1)
    }

    private fun scaleBitmap(bitmap: Bitmap, maxWidth: Int, maxHeight: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        if (width <= 0 || height <= 0) {
            return bitmap
        }
        val scale = minOf(maxWidth.toFloat() / width.toFloat(), maxHeight.toFloat() / height.toFloat(), 1f)
        if (scale >= 1f) {
            return bitmap
        }
        return Bitmap.createScaledBitmap(
            bitmap,
            (width * scale).toInt().coerceAtLeast(1),
            (height * scale).toInt().coerceAtLeast(1),
            true
        )
    }

    private fun callLogType(direction: String, status: String): Int {
        if (status == "missed") {
            return CallLog.Calls.MISSED_TYPE
        }
        if (direction == "outgoing") {
            return CallLog.Calls.OUTGOING_TYPE
        }
        return CallLog.Calls.INCOMING_TYPE
    }

    private data class PendingCallLogWrite(
        val payload: Map<*, *>,
        val result: MethodChannel.Result
    )
}
