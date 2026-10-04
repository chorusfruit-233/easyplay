package com.easyplay.easyplay

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Native UCI process, with command IO and reader threads off the UI thread. */
class AndroidPikafish(private val context: android.content.Context) : EventChannel.StreamHandler {
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
                        val command = call.argument<String>("command") ?: error("Missing UCI command")
                        require(!command.contains('\n') && !command.contains('\r'))
                        val child = process ?: error("Pikafish is not running")
                        child.outputStream.write((command + "\n").toByteArray(Charsets.UTF_8))
                        child.outputStream.flush()
                    }
                    "close" -> stopProcess()
                    else -> { main.post { result.notImplemented() }; return@execute }
                }
                main.post { result.success(null) }
            } catch (error: Exception) {
                main.post { result.error("PIKAFISH", error.message, null) }
            }
        }
    }

    private fun start() {
        if (process?.isAlive == true) return
        val binary = File(context.applicationInfo.nativeLibraryDir, "libpikafish.so")
        check(binary.canExecute()) { "Pikafish ARM64 binary is missing from this build" }
        val directory = File(context.filesDir, "pikafish").apply { mkdirs() }
        val model = File(directory, "pikafish.nnue")
        val expected = "7d13d73569a9b571ba0eb20cf1596247bc2a42738967e61afef6482b231e900e"
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
        if (!model.exists() || checksum(model) != expected) {
            val temporary = File(directory, "pikafish.nnue.download")
            context.assets.open("flutter_assets/assets/pikafish/pikafish.nnue").use { input ->
                temporary.outputStream().use { output -> input.copyTo(output) }
            }
            check(checksum(temporary) == expected) { "Pikafish NNUE checksum mismatch" }
            check(temporary.renameTo(model)) { "Unable to install Pikafish NNUE" }
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
                        sink?.error("PIKAFISH_EXIT", "Pikafish exited ($code)", null)
                    }
                }
            } catch (error: Exception) {
                main.post { if (process === child) sink?.error("PIKAFISH_IO", error.message, null) }
            }
        }, "pikafish-output").apply { isDaemon = true; start() }
    }

    private fun stopProcess() {
        val child = process ?: return
        process = null
        try {
            child.outputStream.write("quit\n".toByteArray())
            child.outputStream.flush()
            if (!child.waitFor(500, TimeUnit.MILLISECONDS)) child.destroyForcibly()
        } catch (_: Exception) { child.destroyForcibly() }
        child.waitFor()
    }

    fun close() {
        sink = null
        commands.execute { stopProcess() }
        commands.shutdown()
    }
}
