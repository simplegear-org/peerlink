package org.simplegear.peerlinkapp

import android.app.NotificationManager
import android.content.Context

object PeerlinkCallNotifications {
    private const val prefsName = "peerlink_call_notifications"
    private const val idsKey = "ids"

    fun remember(context: Context, notificationId: Int) {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val ids = prefs.getStringSet(idsKey, emptySet()).orEmpty().toMutableSet()
        ids.add(notificationId.toString())
        prefs.edit().putStringSet(idsKey, ids).apply()
    }

    fun cancelAll(context: Context) {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val ids = prefs.getStringSet(idsKey, emptySet()).orEmpty()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (rawId in ids) {
            rawId.toIntOrNull()?.let { manager.cancel(it) }
        }
        prefs.edit().remove(idsKey).apply()
    }
}
