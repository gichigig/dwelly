package com.ishinadwelly.native_notification_plugin

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Flutter plugin that automatically attaches to all foreground and background FlutterEngine instances,
 * handling token synchronization and rendering WhatsApp-style inline RemoteInput notifications.
 */
class NativeNotificationPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var methodChannel: MethodChannel? = null
    private var applicationContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        val channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler(this@NativeNotificationPlugin)
        }
        methodChannel = channel
        activeChannels.add(channel)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.let {
            it.setMethodCallHandler(null)
            activeChannels.remove(it)
        }
        methodChannel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = applicationContext ?: return
        when (call.method) {
            "saveAuthToken" -> {
                val token = call.argument<String>("token")
                val refreshToken = call.argument<String>("refreshToken")
                val apiBaseUrl = call.argument<String>("apiBaseUrl")

                if (!token.isNullOrEmpty()) {
                    val tokenManager = SecureTokenManager(context)
                    tokenManager.saveToken(token, refreshToken)
                    if (!apiBaseUrl.isNullOrEmpty()) {
                        tokenManager.saveApiBaseUrl(apiBaseUrl)
                    }
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Token cannot be empty", null)
                }
            }
            "clearAuthToken" -> {
                SecureTokenManager(context).clearTokens()
                result.success(true)
            }
            "showNativeChatNotification" -> {
                val chatId = call.argument<String>("chatId") ?: ""
                val receiverId = call.argument<String>("receiverId") ?: ""
                val messageId = call.argument<String>("messageId") ?: ""
                val senderName = call.argument<String>("senderName") ?: "New Message"
                val messageText = call.argument<String>("messageText") ?: ""

                if (chatId.isNotEmpty() && messageText.isNotEmpty()) {
                    NotificationHelper.showChatNotification(
                        context = context,
                        chatId = chatId,
                        receiverId = receiverId,
                        messageId = messageId,
                        senderName = senderName,
                        messageText = messageText
                    )
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "ChatId and MessageText required", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL_NAME = "com.ishinadwelly.app/native_notification"
        private val activeChannels = CopyOnWriteArrayList<MethodChannel>()

        fun sendNotificationTapped(chatId: String) {
            for (channel in activeChannels) {
                try {
                    channel.invokeMethod("onNotificationTapped", mapOf("chatId" to chatId))
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }
}
