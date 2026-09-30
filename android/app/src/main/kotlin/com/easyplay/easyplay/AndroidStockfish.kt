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
class AndroidStockfish(private val nativeDir: File) : EventChannel.StreamHandler {
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
                        val child = process ?: error("Stockfish is not running")
                        child.outputStream.write((command + "\n").toByteArray(Charsets.UTF_8))
                        child.outputStream.flush()
                    }
                    "close" -> stopProcess()
                    else -> { main.post { result.notImplemented() }; return@execute }
                }
                main.post { result.success(null) }
            } catch (error: Exception) {
                main.post { result.error("STOCKFISH", error.message, null) }
            }
        }
    }

    private fun start() {
        if (process?.isAlive == true) return
        val binary = File(nativeDir, "libstockfish.so")
        check(binary.canExecute()) { "Stockfish 19 ARM64 binary is missing from this build" }
        val child = ProcessBuilder(binary.absolutePath).redirectErrorStream(true).start()
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
                        sink?.error("STOCKFISH_EXIT", "Stockfish exited ($code)", null)
                    }
                }
            } catch (error: Exception) {
                main.post { if (process === child) sink?.error("STOCKFISH_IO", error.message, null) }
            }
        }, "stockfish-output").apply { isDaemon = true; start() }
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
