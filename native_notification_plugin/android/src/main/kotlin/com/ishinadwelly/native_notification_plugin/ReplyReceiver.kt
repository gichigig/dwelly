package com.ishinadwelly.native_notification_plugin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.RemoteInput
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap

/**
 * Native Kotlin BroadcastReceiver that captures the user's typed inline reply from RemoteInput,
 * extracts chat metadata, and posts the message directly to the Spring Boot backend via Retrofit/OkHttp
 * WITHOUT launching or waking up the Flutter application UI.
 */
class ReplyReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_REPLY) return

        val pendingResult = goAsync()
        val appContext = context.applicationContext

        // 1. Extract RemoteInput results
        val remoteInput = RemoteInput.getResultsFromIntent(intent)
        val replyText = remoteInput?.getCharSequence(NotificationHelper.KEY_TEXT_REPLY)?.toString()?.trim()

        // 2. Extract metadata from Intent extras
        val chatId = intent.getStringExtra(NotificationHelper.EXTRA_CHAT_ID) ?: ""
        val receiverId = intent.getStringExtra(NotificationHelper.EXTRA_RECEIVER_ID) ?: ""
        val messageId = intent.getStringExtra(NotificationHelper.EXTRA_MESSAGE_ID) ?: ""
        val senderName = intent.getStringExtra(NotificationHelper.EXTRA_SENDER_NAME) ?: "User"
        val notificationId = intent.getIntExtra(
            NotificationHelper.EXTRA_NOTIFICATION_ID,
            (chatId.hashCode() + messageId.hashCode()).and(0x7FFFFFFF)
        )

        // Validate basic inputs
        if (replyText.isNullOrEmpty() || chatId.isEmpty()) {
            pendingResult.finish()
            return
        }

        // 3. Duplicate Prevention: ensure we don't process exact same reply text for same notification within 3 seconds
        val dedupeKey = "${notificationId}_$replyText"
        val now = System.currentTimeMillis()
        val lastSentTime = recentReplies[dedupeKey] ?: 0L
        if (now - lastSentTime < 3000L) {
            pendingResult.finish()
            return
        }
        recentReplies[dedupeKey] = now
        cleanupOldDedupeKeys(now)

        // 4. Check Internet Availability immediately
        if (!ApiClient.isNetworkAvailable(appContext)) {
            NotificationHelper.showReplyFailure(
                appContext,
                notificationId,
                senderName,
                "No internet connection available",
                chatId,
                receiverId,
                messageId
            )
            pendingResult.finish()
            return
        }

        // 5. Show immediate feedback in notification tray (e.g. "Sending to John...")
        NotificationHelper.showSendingSpinner(appContext, notificationId, senderName, replyText)

        // 6. Execute background network request via Coroutine Scope on IO dispatcher
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val apiService = ApiClient.getService(appContext)
                val tokenManager = SecureTokenManager(appContext)
                val token = tokenManager.getToken() ?: ""

                val clientMessageId = "native_${System.currentTimeMillis()}"
                val queueRequest = QueueReplyRequest(
                    content = replyText,
                    messageType = "TEXT",
                    clientMessageId = clientMessageId
                )

                // 1. Try Dwelly conversation queue ("POST /api/conversations/{id}/messages/queue")
                var response = apiService.sendConversationQueuedReply(
                    conversationId = chatId,
                    authorization = "Bearer $token",
                    request = queueRequest
                ).execute()

                // 2. If queue endpoint fails/not available, try synchronous ("POST /api/conversations/{id}/messages")
                if (!response.isSuccessful) {
                    response = apiService.sendConversationSyncReply(
                        conversationId = chatId,
                        authorization = "Bearer $token",
                        request = queueRequest
                    ).execute()
                }

                // 3. If that also fails, fallback to standard ("POST /api/messages/reply")
                if (!response.isSuccessful) {
                    val replyRequest = ReplyRequest(
                        chatId = chatId,
                        receiverId = receiverId,
                        message = replyText,
                        clientMessageId = clientMessageId
                    )
                    response = apiService.sendReply("Bearer $token", replyRequest).execute()
                }

                withContext(Dispatchers.Main) {
                    if (response.isSuccessful && (response.code() == 200 || response.code() == 201)) {
                        // Success! Show confirmation right in notification tray
                        NotificationHelper.showReplySuccess(
                            appContext,
                            notificationId,
                            senderName,
                            replyText
                        )
                    } else {
                        val errorMsg = if (response.code() == 401 || response.code() == 403) {
                            "Authentication expired. Please open app to log in."
                        } else {
                            "Server error (${response.code()})"
                        }
                        NotificationHelper.showReplyFailure(
                            appContext,
                            notificationId,
                            senderName,
                            errorMsg,
                            chatId,
                            receiverId,
                            messageId
                        )
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    NotificationHelper.showReplyFailure(
                        appContext,
                        notificationId,
                        senderName,
                        "Network request failed: ${e.localizedMessage ?: "Unknown error"}",
                        chatId,
                        receiverId,
                        messageId
                    )
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        const val ACTION_REPLY = "com.ishinadwelly.app.ACTION_INLINE_REPLY"
        private val recentReplies = ConcurrentHashMap<String, Long>()

        private fun cleanupOldDedupeKeys(currentTime: Long) {
            val iterator = recentReplies.entries.iterator()
            while (iterator.hasNext()) {
                val entry = iterator.next()
                if (currentTime - entry.value > 15000L) {
                    iterator.remove()
                }
            }
        }
    }
}
