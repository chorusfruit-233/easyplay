package com.easyplay.easyplay

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    private lateinit var kataGo: AndroidKataGoGtp

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        kataGo = AndroidKataGoGtp(filesDir, File(applicationInfo.nativeLibraryDir))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "easyplay/katago")
            .setMethodCallHandler { call, result ->
                kataGo.execute(call.method, call.arguments, result)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "easyplay/lan")
            .setMethodCallHandler { call, result ->
                if (call.method != "setKeepScreenOn") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (call.argument<Boolean>("enabled") == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
    }

    override fun onDestroy() {
        if (::kataGo.isInitialized) kataGo.close()
        super.onDestroy()
    }
}
