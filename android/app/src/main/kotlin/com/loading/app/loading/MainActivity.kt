package com.loading.app.loading

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "loading/keep_alive")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        requestNotificationPermission()
                        try {
                            DownloadKeepAliveService.start(this)
                        } catch (error: Exception) {
                            result.error("keep_alive", error.message, null)
                            return@setMethodCallHandler
                        }
                        result.success(null)
                    }
                    "release" -> {
                        DownloadKeepAliveService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "loading/mux")
            .setMethodCallHandler { call, result ->
                if (call.method != "combine") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val video = call.argument<String>("video")
                val audio = call.argument<String>("audio")
                val output = call.argument<String>("output")
                if (video == null || audio == null || output == null) {
                    result.error("mux", "ไฟล์ไม่ครบ", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        TrackMux.combine(video, audio, output)
                        runOnUiThread { result.success(null) }
                    } catch (error: Exception) {
                        val message = error.message ?: "รวมภาพกับเสียงไม่ได้"
                        runOnUiThread { result.error("mux", message, null) }
                    }
                }.start()
            }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < 33) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
    }
}
