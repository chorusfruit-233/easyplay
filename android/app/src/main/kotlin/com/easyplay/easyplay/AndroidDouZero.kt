package com.easyplay.easyplay

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

class AndroidDouZero(private val context: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var closed = false
    private var inference: DouZeroInference? = null

    private fun bytes(name: String): ByteArray {
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/douzero/$name")
        return context.assets.open(key).use { it.readBytes() }
    }

    private fun engine(): DouZeroInference = inference ?: run {
        val models = JSONObject(String(bytes("manifest.json"), Charsets.UTF_8)).getJSONObject("models")
        val hashes = listOf("landlord", "landlord_up", "landlord_down")
            .associateWith { models.getJSONObject(it).getString("sha256") }
        DouZeroInference({ role -> bytes("$role.onnx") }, hashes).also { inference = it }
    }

    fun execute(call: MethodCall, result: MethodChannel.Result) {
        if (closed) { result.error("douzero_closed", "DouZero closed", null); return }
        if (call.method !in setOf("score", "reset")) { result.notImplemented(); return }
        val role = call.argument<String>("role")
        val x = call.argument<FloatArray>("x")
        val z = call.argument<FloatArray>("z")
        executor.execute {
            try {
                check(!closed)
                val values = if (call.method == "reset") {
                    inference?.close(); inference = null; null
                } else {
                    require(role != null && x != null && z != null)
                    engine().score(role, x, z)
                }
                main.post { result.success(values) }
            } catch (_: Exception) {
                main.post { result.error("douzero_inference", "DouZero model inference failed", null) }
            } catch (_: LinkageError) {
                main.post { result.error("douzero_runtime", "DouZero native runtime unavailable", null) }
            }
        }
    }

    fun close() {
        closed = true
        executor.execute { inference?.close(); inference = null }
        executor.shutdown()
    }
}
