// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

package org.simplegear.peerlinkapp

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import org.json.JSONObject
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class PeerlinkFirebaseMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (data.isNotEmpty()) {
            try {
                PeerlinkPushPayloadBridge.pushPayload(
                    JSONObject(data).toString(),
                    notifyFlutter = PeerlinkAppVisibility.isForeground,
                )
            } catch (error: Throwable) {
                Log.e(TAG, "push payload bridge failed", error)
            }
        }
        if (data["type"] != "call_invite") {
            return
        }
        if (data["callAction"] == "end" || data["mediaType"] == "end") {
            return
        }
        showIncomingCall(data)
    }

    private fun showIncomingCall(data: Map<String, String>) {
        val callId = data["callId"].orEmpty()
        val callerUserId = data["callerUserId"]
            ?: data["senderUserId"]
            ?: data["fromPeerId"]
            ?: data["peerId"]
            ?: ""
        if (callId.isBlank() || callerUserId.isBlank()) {
            return
        }
        if (PeerlinkAppVisibility.isForeground) {
            return
        }

        ensureCallChannel()

        val mediaType = data["mediaType"].orEmpty().ifBlank { "audio" }
        val callUri = Uri.Builder()
            .scheme("peerlink")
            .authority("call")
            .appendQueryParameter("type", "call_invite")
            .appendQueryParameter("callId", callId)
            .appendQueryParameter("callerUserId", callerUserId)
            .appendQueryParameter("mediaType", mediaType)
            .build()
        val intent = Intent(Intent.ACTION_VIEW, callUri, this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            callId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = if (mediaType == "video") "Видеозвонок" else "Аудиовызов"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CALL_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(callerUserId)
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .build()

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            startActivity(intent)
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notificationId = callId.hashCode()
        PeerlinkCallNotifications.remember(this, notificationId)
        manager.notify(notificationId, notification)
    }

    private fun ensureCallChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CALL_CHANNEL_ID) != null) {
            return
        }
        val channel = NotificationChannel(
            CALL_CHANNEL_ID,
            "Звонки",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Входящие звонки PeerLink"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private companion object {
        const val TAG = "PeerlinkFcmService"
        const val CALL_CHANNEL_ID = "peerlink_calls"
    }
}
