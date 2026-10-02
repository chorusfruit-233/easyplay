package com.easyplay.easyplay

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.view.WindowManager
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val colorExecutor = Executors.newSingleThreadExecutor()
    private lateinit var kataGo: AndroidKataGoGtp
    private lateinit var stockfish: AndroidStockfish

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "easyplay/material_colors")
            .setMethodCallHandler { call, result ->
                if (call.method != "generate") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val seeds = call.argument<List<Number>>("seeds") ?: emptyList()
                    require(seeds.size in 1..32)
                    val style = call.argument<String>("style") ?: "tonalSpot"
                    val spec = call.argument<String>("spec") ?: "spec2025"
                    val dark = call.argument<Boolean>("dark") == true
                    colorExecutor.execute {
                        try {
                            val colors = com.easyplay.easyplay.materialcolor.MaterialColors.generate(seeds, style, spec, dark)
                            runOnUiThread { result.success(colors) }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("color_scheme", error.message, null) }
                        }
                    }
                } catch (error: Exception) {
                    result.error("color_scheme", error.message, null)
                }
            }
        stockfish = AndroidStockfish(File(applicationInfo.nativeLibraryDir))
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "easyplay/stockfish/output")
            .setStreamHandler(stockfish)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "easyplay/stockfish")
            .setMethodCallHandler { call, result -> stockfish.execute(call, result) }
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
        colorExecutor.shutdownNow()
        if (::stockfish.isInitialized) stockfish.close()
        if (::kataGo.isInitialized) kataGo.close()
        super.onDestroy()
    }
}
