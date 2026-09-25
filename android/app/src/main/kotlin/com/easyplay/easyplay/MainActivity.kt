package com.easyplay.easyplay

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.util.concurrent.Executors

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

/** Runs upstream KataGo's regular GTP executable and serializes commands off the UI thread. */
private class AndroidKataGoGtp(
    private val filesDir: File,
    private val nativeLibraryDir: File,
) {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var process: Process? = null
    private var input: BufferedWriter? = null
    private var output: BufferedReader? = null

    fun execute(method: String, arguments: Any?, result: MethodChannel.Result) {
        executor.execute {
            try {
                val value = when (method) {
                    "start" -> {
                        val args = arguments as Map<*, *>
                        start(args["model"] as ByteArray, args["config"] as String)
                        "ready"
                    }
                    "command" -> command((arguments as Map<*, *>)["line"] as String)
                    "stop" -> {
                        stop()
                        "stopped"
                    }
                    else -> throw IllegalArgumentException("Unknown KataGo method: $method")
                }
                mainHandler.post { result.success(value) }
            } catch (error: Throwable) {
                mainHandler.post { result.error("KATAGO", error.message ?: error.toString(), null) }
            }
        }
    }

    private fun start(model: ByteArray, config: String) {
        stop()
        val dir = File(filesDir, "katago").apply { mkdirs() }
        // Do not execute a copied asset from filesDir: Android devices may
        // mount writable app data with noexec. APK native libraries are
        // extracted to nativeLibraryDir with executable permissions.
        val executable = File(nativeLibraryDir, "libkatago.so")
        if (!executable.isFile || !executable.canExecute()) {
            throw IllegalStateException(
                "APK 未包含可执行的 KataGo（${executable.absolutePath}）。请重新构建并安装包含 arm64-v8a KataGo 的版本。",
            )
        }
        val modelFile = File(dir, "b6.bin.gz").apply { writeBytes(model) }
        val configFile = File(dir, "gtp.cfg").apply { writeText(config) }
        val builder = ProcessBuilder(
            executable.absolutePath,
            "gtp",
            "-model", modelFile.absolutePath,
            "-config", configFile.absolutePath,
        ).directory(dir).redirectErrorStream(false)
        builder.environment()["LD_LIBRARY_PATH"] = nativeLibraryDir.absolutePath
        val child = builder.start()
        process = child
        input = BufferedWriter(OutputStreamWriter(child.outputStream, Charsets.UTF_8))
        output = BufferedReader(InputStreamReader(child.inputStream, Charsets.UTF_8))
        // Drain diagnostics so a verbose engine cannot block on a full stderr pipe.
        Thread({ child.errorStream.bufferedReader().useLines { lines -> lines.forEach { android.util.Log.i("EasyPlayKataGo", it) } } }, "katago-stderr").apply { isDaemon = true; start() }
        val ready = command("protocol_version")
        if (!ready.contains("2")) {
            stop()
            throw IllegalStateException("KataGo GTP 启动失败：$ready")
        }
    }

    @Synchronized
    private fun command(line: String): String {
        val writer = input ?: throw IllegalStateException("KataGo 尚未启动")
        val reader = output ?: throw IllegalStateException("KataGo 尚未启动")
        writer.write(line)
        writer.newLine()
        writer.flush()
        val response = StringBuilder()
        while (true) {
            val next = reader.readLine() ?: throw IllegalStateException("KataGo 引擎已退出")
            if (next.isEmpty()) break
            if (response.isNotEmpty()) response.append('\n')
            response.append(next)
        }
        val value = response.toString()
        if (value.startsWith("?")) throw IllegalStateException(value.removePrefix("?").trim())
        return value.removePrefix("=").trim()
    }

    @Synchronized
    private fun stop() {
        val child = process ?: return
        try {
            input?.apply { write("quit\n"); flush() }
        } catch (_: Throwable) {
        }
        child.destroy()
        if (!child.waitFor(500, java.util.concurrent.TimeUnit.MILLISECONDS)) child.destroyForcibly()
        process = null
        input = null
        output = null
    }

    fun close() {
        executor.execute { stop() }
        executor.shutdown()
    }
}
