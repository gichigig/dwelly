package com.ishinadwelly.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.linusu.flutter_web_auth_2.FlutterWebAuth2Plugin

class DwellyCallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = intent?.data
        val scheme = url?.scheme

        if (scheme != null) {
            FlutterWebAuth2Plugin.callbacks.remove(scheme)?.success(url.toString())
        }

        // Bring MainActivity directly back to the foreground over Chrome Custom Tabs
        val mainIntent = Intent(this, MainActivity::class.java)
        mainIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        startActivity(mainIntent)

        finish()
    }
}
