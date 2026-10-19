package com.alienssyndicate.iplex_control

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "iplex/app_sharing")
            .setMethodCallHandler { call, result ->
                if (call.method != "share") { result.notImplemented(); return@setMethodCallHandler }
                val text = call.argument<String>("text")
                if (text.isNullOrBlank()) { result.error("invalid-argument", null, null); return@setMethodCallHandler }
                try {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    startActivity(Intent.createChooser(intent, null))
                    result.success(null)
                } catch (error: Exception) { result.error("share-unavailable", null, null) }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            window.navigationBarColor = Color.TRANSPARENT
            window.statusBarColor = Color.TRANSPARENT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
    }
}
