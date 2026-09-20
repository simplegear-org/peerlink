// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

package org.simplegear.peerlinkapp

import android.app.NotificationManager
import android.content.Context

/** Tracks only message alerts, so reading a chat never dismisses a call alert. */
object PeerlinkMessageNotifications {
    private const val prefsName = "peerlink_message_notifications"

    fun remember(context: Context, chatId: String, notificationId: Int) {
        val normalizedChatId = chatId.trim()
        if (normalizedChatId.isEmpty()) {
            return
        }
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val key = idsKey(normalizedChatId)
        val ids = prefs.getStringSet(key, emptySet()).orEmpty().toMutableSet()
        ids.add(notificationId.toString())
        prefs.edit().putStringSet(key, ids).apply()
    }

    fun cancelForChat(context: Context, chatId: String) {
        val normalizedChatId = chatId.trim()
        if (normalizedChatId.isEmpty()) {
            return
        }
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val key = idsKey(normalizedChatId)
        val ids = prefs.getStringSet(key, emptySet()).orEmpty()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (rawId in ids) {
            rawId.toIntOrNull()?.let { manager.cancel(it) }
        }
        prefs.edit().remove(key).apply()
    }

    private fun idsKey(chatId: String) = "ids:$chatId"
}
