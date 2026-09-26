package com.easyplay.easyplay

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private lateinit var kataGo: AndroidKataGoGtp

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        kataGo = AndroidKataGoGtp(filesDir, File(applicationInfo.nativeLibraryDir))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "easyplay/katago")
            .setMethodCallHandler { call, result ->
                kataGo.execute(call.method, call.arguments, result)
            }
    }

    override fun onDestroy() {
        if (::kataGo.isInitialized) kataGo.close()
        super.onDestroy()
    }
}
