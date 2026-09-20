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
import android.app.KeyguardManager
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
            showIncomingMessage(message)
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
        if (PeerlinkAccessControl.isBlocked(this, callerUserId)) {
            Log.i(TAG, "blocked incoming call notification from peer=$callerUserId callId=$callId")
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

        val callerName = PeerlinkCallerNames.resolve(this, callerUserId)
            ?: data["callerDisplayName"]?.trim()?.takeIf { it.isNotEmpty() }
            ?: callerUserId
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
            .setContentText(callerName)
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

        // Android renders a full-screen intent as a heads-up alert while the
        // display is unlocked. For an incoming call PeerLink must show the
        // same answer/decline UI in both cases, so explicitly bring its call
        // deep link forward. On a locked display the full-screen intent above
        // remains the OS-managed path.
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!keyguard.isKeyguardLocked) {
            try {
                startActivity(intent)
            } catch (error: Throwable) {
                Log.w(TAG, "incoming call activity launch deferred to notification", error)
            }
        }
    }

    private fun showIncomingMessage(message: RemoteMessage) {
        if (PeerlinkAppVisibility.isForeground) {
            return
        }
        val data = message.data
        val type = data["type"].orEmpty().lowercase()
        if (type != "message" && type != "direct_update" && type != "group_update") {
            return
        }
        val senderUserId = data["senderUserId"]
            ?: data["fromPeerId"]
            ?: data["peerId"]
            ?: ""
        if (senderUserId.isNotBlank() && PeerlinkAccessControl.isBlocked(this, senderUserId)) {
            Log.i(TAG, "blocked incoming message notification from peer=$senderUserId")
            return
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        ensureMessageChannel()
        val contentIntent = PendingIntent.getActivity(
            this,
            message.messageId?.hashCode() ?: data.hashCode(),
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val remoteNotification = message.notification
        val title = remoteNotification?.title?.takeIf { it.isNotBlank() } ?: "PeerLink X"
        val body = remoteNotification?.body?.takeIf { it.isNotBlank() }
            ?: data["message"]?.takeIf { it.isNotBlank() }
            ?: data["text"]?.takeIf { it.isNotBlank() }
            ?: "Новое сообщение"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, MESSAGE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setPriority(Notification.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notificationId = message.messageId?.hashCode() ?: data.hashCode()
        val chatId = data["groupId"]?.takeIf { it.isNotBlank() } ?: senderUserId
        PeerlinkMessageNotifications.remember(this, chatId, notificationId)
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
            description = "Входящие звонки PeerLink X"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun ensureMessageChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(MESSAGE_CHANNEL_ID) != null) {
            return
        }
        val channel = NotificationChannel(
            MESSAGE_CHANNEL_ID,
            "Сообщения",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Новые сообщения PeerLink X"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        manager.createNotificationChannel(channel)
    }

    private companion object {
        const val TAG = "PeerlinkFcmService"
        const val CALL_CHANNEL_ID = "peerlink_calls"
        const val MESSAGE_CHANNEL_ID = "peerlink_messages"
    }
}
