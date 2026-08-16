package com.ishinadwelly.native_notification_plugin

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import androidx.core.content.ContextCompat

/**
 * Native Kotlin helper responsible for managing chat notification channels,
 * rendering WhatsApp-style inline RemoteInput replies, and updating notification status.
 */
object NotificationHelper {

    const val CHANNEL_ID_MESSAGES = "messages"
    const val CHANNEL_NAME_MESSAGES = "Messages"
    const val KEY_TEXT_REPLY = "key_text_reply"

    const val EXTRA_CHAT_ID = "extra_chat_id"
    const val EXTRA_RECEIVER_ID = "extra_receiver_id"
    const val EXTRA_MESSAGE_ID = "extra_message_id"
    const val EXTRA_SENDER_NAME = "extra_sender_name"
    const val EXTRA_NOTIFICATION_ID = "extra_notification_id"

    /**
     * Creates the Android 8.0+ notification channel.
     */
    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID_MESSAGES,
                CHANNEL_NAME_MESSAGES,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Chat messages and direct inline replies"
                enableLights(true)
                enableVibration(true)
                setShowBadge(true)
            }

            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    /**
     * Checks if the app has Android 13+ (API 33) POST_NOTIFICATIONS permission.
     */
    fun hasNotificationPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private fun cleanName(rawName: String): String {
        var name = rawName.trim()
        if (name.startsWith("New message from ", ignoreCase = true)) {
            name = name.removePrefix("New message from ").trim()
        }
        if (name.startsWith("New message from", ignoreCase = true)) {
            name = name.removePrefix("New message from").trim()
        }
        return if (name.isNotEmpty()) name else "User"
    }

    /**
     * Displays a chat message notification with an inline WhatsApp-style Direct Reply action.
     */
    fun showChatNotification(
        context: Context,
        chatId: String,
        receiverId: String,
        messageId: String,
        senderName: String,
        messageText: String,
        notificationId: Int = (chatId.hashCode() + messageId.hashCode()).and(0x7FFFFFFF)
    ) {
        createNotificationChannel(context)
        if (!hasNotificationPermission(context)) {
            return
        }

        val cleanSenderName = cleanName(senderName)

        // 1. Build RemoteInput for typing inline reply
        val remoteInput = RemoteInput.Builder(KEY_TEXT_REPLY)
            .setLabel("Reply to $cleanSenderName...")
            .build()

        // 2. Build Intent directed to our native ReplyReceiver
        val replyIntent = Intent(context, ReplyReceiver::class.java).apply {
            action = ReplyReceiver.ACTION_REPLY
            putExtra(EXTRA_CHAT_ID, chatId)
            putExtra(EXTRA_RECEIVER_ID, receiverId)
            putExtra(EXTRA_MESSAGE_ID, messageId)
            putExtra(EXTRA_SENDER_NAME, cleanSenderName)
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }

        // 3. Create PendingIntent with FLAG_MUTABLE required for RemoteInput on Android 12+ (API 31)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val replyPendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId,
            replyIntent,
            pendingIntentFlags
        )

        // 4. Create Notification Action containing the RemoteInput
        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_send,
            "Reply",
            replyPendingIntent
        ).addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(true)
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
            .build()

        // 5. Create tap PendingIntent to open application if user taps the notification body
        val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CHAT_ID, chatId)
            putExtra("from_notification", true)
        } ?: Intent().apply {
            setClassName(context.packageName, "${context.packageName}.MainActivity")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CHAT_ID, chatId)
            putExtra("from_notification", true)
        }

        val openAppPendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            openAppIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        // 6. Build and show the notification
        val notification = NotificationCompat.Builder(context, CHANNEL_ID_MESSAGES)
            .setSmallIcon(context.resources.getIdentifier("ic_notification", "drawable", context.packageName).let { if (it != 0) it else android.R.drawable.ic_dialog_info })
            .setContentTitle(cleanSenderName)
            .setContentText(messageText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(messageText))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(openAppPendingIntent)
            .addAction(replyAction)
            .setColor(0xFF0F172A.toInt())
            .build()

        try {
            NotificationManagerCompat.from(context).notify(notificationId, notification)
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }

    /**
     * Updates the notification with a spinning progress indicator while sending the reply.
     */
    fun showSendingSpinner(context: Context, notificationId: Int, senderName: String, replyText: String) {
        if (!hasNotificationPermission(context)) return

        val clean = cleanName(senderName)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID_MESSAGES)
            .setSmallIcon(context.resources.getIdentifier("ic_notification", "drawable", context.packageName).let { if (it != 0) it else android.R.drawable.ic_dialog_info })
            .setContentTitle("Sending to $clean...")
            .setContentText(replyText)
            .setProgress(0, 0, true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setColor(0xFF0F172A.toInt())
            .build()

        try {
            NotificationManagerCompat.from(context).notify(notificationId, notification)
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }

    /**
     * Shows success confirmation inside the notification tray or clears it.
     */
    fun showReplySuccess(context: Context, notificationId: Int, senderName: String, replyText: String) {
        if (!hasNotificationPermission(context)) return

        val clean = cleanName(senderName)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID_MESSAGES)
            .setSmallIcon(context.resources.getIdentifier("ic_notification", "drawable", context.packageName).let { if (it != 0) it else android.R.drawable.ic_dialog_info })
            .setContentTitle(clean)
            .setContentText("You: $replyText")
            .setStyle(NotificationCompat.BigTextStyle().bigText("You: $replyText"))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setTimeoutAfter(3500) // Automatically dismiss after 3.5 seconds
            .setColor(0xFF0F172A.toInt())
            .build()

        try {
            NotificationManagerCompat.from(context).notify(notificationId, notification)
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }

    /**
     * Shows failure notification with a retry hint if sending fails.
     */
    fun showReplyFailure(
        context: Context,
        notificationId: Int,
        senderName: String,
        errorReason: String,
        chatId: String,
        receiverId: String,
        messageId: String
    ) {
        if (!hasNotificationPermission(context)) return

        val retryIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CHAT_ID, chatId)
            putExtra("from_notification", true)
        } ?: Intent().apply {
            setClassName(context.packageName, "${context.packageName}.MainActivity")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CHAT_ID, chatId)
            putExtra("from_notification", true)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            retryIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        val clean = cleanName(senderName)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID_MESSAGES)
            .setSmallIcon(context.resources.getIdentifier("ic_notification", "drawable", context.packageName).let { if (it != 0) it else android.R.drawable.ic_dialog_info })
            .setContentTitle("Failed to reply to $clean")
            .setContentText(errorReason)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$errorReason. Tap to open chat and retry."))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setColor(0xFFDC2626.toInt())
            .build()

        try {
            NotificationManagerCompat.from(context).notify(notificationId, notification)
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }

    const val CHANNEL_ID_CALLS = "incoming_calls_v2"
    const val CHANNEL_NAME_CALLS = "Incoming Calls"

    fun createCallNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val soundUri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE)
            val audioAttributes = android.media.AudioAttributes.Builder()
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .build()

            val channel = NotificationChannel(
                CHANNEL_ID_CALLS,
                CHANNEL_NAME_CALLS,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming voice and video call notifications"
                enableLights(true)
                enableVibration(true)
                setSound(soundUri, audioAttributes)
                setShowBadge(true)
            }

            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    fun showCallNotification(
        context: Context,
        roomName: String,
        callerName: String,
        isVideo: Boolean,
        callerAvatar: String = ""
    ) {
        createCallNotificationChannel(context)
        if (!hasNotificationPermission(context)) return

        val cleanCallerName = cleanName(callerName)
        val notificationId = (roomName.hashCode() and 0x7FFFFFFF)

        val acceptIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("action", "accept_call")
            putExtra("roomName", roomName)
            putExtra("callerName", cleanCallerName)
            putExtra("isVideo", isVideo)
            putExtra("callerAvatar", callerAvatar)
            putExtra("from_notification", true)
        } ?: Intent().apply {
            setClassName(context.packageName, "${context.packageName}.MainActivity")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("action", "accept_call")
            putExtra("roomName", roomName)
            putExtra("callerName", cleanCallerName)
            putExtra("isVideo", isVideo)
            putExtra("callerAvatar", callerAvatar)
            putExtra("from_notification", true)
        }

        val acceptPendingIntent = PendingIntent.getActivity(
            context,
            notificationId + 1,
            acceptIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        val declineIntent = Intent(context, CallReceiver::class.java).apply {
            action = CallReceiver.ACTION_DECLINE_CALL
            putExtra("notification_id", notificationId)
            putExtra("roomName", roomName)
        }

        val declinePendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId + 2,
            declineIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        val callTypeStr = if (isVideo) "Incoming Video Call" else "Incoming Voice Call"

        val notificationBuilder = NotificationCompat.Builder(context, CHANNEL_ID_CALLS)
            .setSmallIcon(context.resources.getIdentifier("ic_notification", "drawable", context.packageName).let { if (it != 0) it else android.R.drawable.ic_menu_call })
            .setContentTitle(cleanCallerName)
            .setContentText(callTypeStr)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(acceptPendingIntent, true)
            .setContentIntent(acceptPendingIntent)
            .setOngoing(true)
            .setAutoCancel(true)
            .setColor(0xFF0F172A.toInt())
            .addAction(
                android.R.drawable.ic_menu_call,
                "ACCEPT",
                acceptPendingIntent
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "DECLINE",
                declinePendingIntent
            )

        try {
            NotificationManagerCompat.from(context).notify(notificationId, notificationBuilder.build())
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }
}
