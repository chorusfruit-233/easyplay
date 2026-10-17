package com.easyplay.easyplay

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Native Gomocup process, with command IO and reader threads off the UI thread. */
class AndroidRapfi(private val context: android.content.Context) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val commands = Executors.newSingleThreadExecutor()
    @Volatile private var process: Process? = null
    @Volatile private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    fun execute(call: MethodCall, result: MethodChannel.Result) {
        commands.execute {
            try {
                when (call.method) {
                    "start" -> start()
                    "send" -> {
                        val command = call.argument<String>("command") ?: error("Missing Gomocup command")
                        require(command.length <= 32768 && !command.contains('\r'))
                        val child = process ?: error("Rapfi is not running")
                        child.outputStream.write((command + "\n").toByteArray(Charsets.UTF_8))
                        child.outputStream.flush()
                    }
                    "close" -> stopProcess()
                    else -> { main.post { result.notImplemented() }; return@execute }
                }
                main.post { result.success(null) }
            } catch (error: Exception) {
                main.post { result.error("RAPFI", error.message, null) }
            }
        }
    }

    private fun start() {
        if (process?.isAlive == true) return
        val binary = File(context.applicationInfo.nativeLibraryDir, "librapfi.so")
        check(binary.canExecute()) { "Rapfi ARM64 binary is missing from this build" }
        val directory = File(context.filesDir, "rapfi").apply { mkdirs() }
        val resources = mapOf(
            "config.toml" to "f2f913c36dcff38fcb65ea5db61b1a990680a086129db951640c4ba8b351e72a",
            "model210901.bin" to "2fa08cb15cf240d9533548c3e011b03d46809f6858362e97ee873d0632aa2015",
            "mix9svqrenju_bs15_black.bin.lz4" to "7ab8c974c30da07717ce6a504616a62ac8c981500503f0ced0fadefd3f46c5ec",
            "mix9svqrenju_bs15_white.bin.lz4" to "a31f318518d3b5630489054d9eb013fd5353c553999640c2bcfd8d95e6fe4e4e",
        )
        fun checksum(file: File): String {
            val digest = java.security.MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }
        for ((name, expected) in resources) {
            val resource = File(directory, name)
            if (!resource.exists() || checksum(resource) != expected) {
                val temporary = File(directory, "$name.download")
                context.assets.open("flutter_assets/assets/rapfi/$name").use { input ->
                    temporary.outputStream().use { output -> input.copyTo(output) }
                }
                check(checksum(temporary) == expected) { "Rapfi resource checksum mismatch: $name" }
                check(temporary.renameTo(resource)) { "Unable to install Rapfi resource: $name" }
            }
        }
        val child = ProcessBuilder(binary.absolutePath).directory(directory).redirectErrorStream(true).start()
        process = child
        Thread({
            try {
                child.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { line -> main.post { if (process === child) sink?.success(line) } }
                }
                val code = child.waitFor()
                main.post {
                    if (process === child) {
                        process = null
                        sink?.error("RAPFI_EXIT", "Rapfi exited ($code)", null)
                    }
                }
            } catch (error: Exception) {
                main.post { if (process === child) sink?.error("RAPFI_IO", error.message, null) }
            }
        }, "rapfi-output").apply { isDaemon = true; start() }
    }

    private fun stopProcess() {
        val child = process ?: return
        process = null
        // Single-threaded search cannot read a queued END while thinking.
        child.destroyForcibly()
        child.waitFor()
    }

    fun close() {
        sink = null
        commands.execute { stopProcess() }
        commands.shutdown()
    }
}
