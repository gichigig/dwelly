package com.ishinadwelly.native_notification_plugin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

class CallReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_DECLINE_CALL = "com.ishinadwelly.action.DECLINE_CALL"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_DECLINE_CALL) {
            val notificationId = intent.getIntExtra("notification_id", -1)
            if (notificationId != -1) {
                try {
                    NotificationManagerCompat.from(context).cancel(notificationId)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }
}
