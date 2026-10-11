package com.knzscent.admin

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.provider.Settings
import android.net.Uri
import android.os.Build
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.knzscent.admin/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "timeZone" -> result.success(TimeZone.getDefault().id)
                    "openSettings" -> {
                        try {
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            } else {
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", packageName, null))
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("settings_unavailable", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
