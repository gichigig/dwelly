package com.ishinadwelly.app

import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Bundle
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ishinadwelly.native_notification_plugin.NotificationHelper
import com.ishinadwelly.native_notification_plugin.NativeNotificationPlugin
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

/**
 * MainActivity acts as the bridge for deep linking when the user taps on a notification body.
 * All MethodChannel registration and background token handling are now automatically managed across
 * all foreground and background engines by NativeNotificationPlugin.
 */
class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.ishinadwelly.app/image_picker_apps"
    private val PICK_IMAGE_REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NotificationHelper.createNotificationChannel(applicationContext)
        handleNotificationIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNotificationIntent(intent)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        if (intent == null) return
        val fromNotification = intent.getBooleanExtra("from_notification", false)
        val chatId = intent.getStringExtra(NotificationHelper.EXTRA_CHAT_ID)
        if (fromNotification && !chatId.isNullOrEmpty()) {
            NativeNotificationPlugin.sendNotificationTapped(chatId)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApps" -> {
                    val apps = getImagePickerApps()
                    result.success(apps)
                }
                "pickFromApp" -> {
                    val packageName = call.argument<String>("packageName")
                    val className = call.argument<String>("className")
                    if (packageName != null && className != null) {
                        pendingResult = result
                        launchPickerFromPackage(packageName, className)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package or class name is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getImagePickerApps(): List<Map<String, String>> {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
        }
        val resolveInfos: List<ResolveInfo> = packageManager.queryIntentActivities(intent, 0)
        val appsList = mutableListOf<Map<String, String>>()

        for (resolveInfo in resolveInfos) {
            val packageName = resolveInfo.activityInfo.packageName
            if (packageName == context.packageName) continue

            val appName = resolveInfo.loadLabel(packageManager).toString()
            val iconDrawable = resolveInfo.loadIcon(packageManager)
            val iconBase64 = encodeDrawableToBase64(iconDrawable)

            val appData = mapOf(
                "packageName" to packageName,
                "className" to resolveInfo.activityInfo.name,
                "name" to appName,
                "icon" to iconBase64
            )
            appsList.add(appData)
        }
        return appsList.distinctBy { it["packageName"] }
    }

    private fun encodeDrawableToBase64(drawable: Drawable): String {
        val bitmap: Bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val bmp = Bitmap.createBitmap(
                if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 100,
                if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 100,
                Bitmap.Config.ARGB_8888
            )
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bmp
        }

        val byteArrayOutputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
        val byteArray = byteArrayOutputStream.toByteArray()
        return Base64.encodeToString(byteArray, Base64.DEFAULT)
    }

    private fun launchPickerFromPackage(packageName: String, className: String) {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            setClassName(packageName, className)
        }
        try {
            startActivityForResult(intent, PICK_IMAGE_REQUEST_CODE)
        } catch (e: Exception) {
            pendingResult?.error("LAUNCH_FAILED", "Could not launch package: $packageName", e.message)
            pendingResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_IMAGE_REQUEST_CODE) {
            if (resultCode == RESULT_OK && data != null) {
                val uris = mutableListOf<android.net.Uri>()
                if (data.clipData != null) {
                    val count = data.clipData!!.itemCount
                    for (i in 0 until count) {
                        uris.add(data.clipData!!.getItemAt(i).uri)
                    }
                } else if (data.data != null) {
                    uris.add(data.data!!)
                }

                if (uris.isNotEmpty()) {
                    val paths = mutableListOf<String>()
                    try {
                        for (uri in uris) {
                            val inputStream: InputStream? = contentResolver.openInputStream(uri)
                            val tempFile = File.createTempFile("picked_image_", ".jpg", cacheDir)
                            val outputStream = FileOutputStream(tempFile)
                            inputStream?.copyTo(outputStream)
                            inputStream?.close()
                            outputStream.close()
                            paths.add(tempFile.absolutePath)
                        }
                        pendingResult?.success(paths)
                    } catch (e: Exception) {
                        pendingResult?.error("COPY_FAILED", "Failed to copy image", e.message)
                    }
                } else {
                    pendingResult?.success(emptyList<String>())
                }
            } else {
                pendingResult?.success(emptyList<String>())
            }
            pendingResult = null
        }
    }
}
