package com.easyplay.easyplay

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/** Every native engine and driver runs in a child process, never in Flutter's VM. */
internal class AndroidKataGoGtp(
    private val filesDir: File,
    private val nativeLibraryDir: File,
) {
    private val commands = Executors.newSingleThreadExecutor()
    private val controls = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private val epoch = AtomicLong()
    private val processLock = Any()
    private val logLock = Any()
    private val logLines = ArrayDeque<String>()
    @Volatile private var session: Session? = null
    @Volatile private var closed = false
    @Volatile private var analyzeStopAt = Long.MAX_VALUE
    private val root = File(filesDir, "katago").apply { mkdirs() }

    private data class Session(val process: Process, val input: BufferedWriter, val output: BufferedReader, val backend: String)
    fun execute(method: String, arguments: Any?, result: MethodChannel.Result) {
        if (closed) { result.error("KATAGO_CLOSED", "KataGo 主机已关闭", null); return }
        val args = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        // A stop invalidates work already queued before it, including a pending startup.
        val ticket = if (method == "stop") epoch.incrementAndGet() else epoch.get()
        val stopTarget = if (method == "stop") detachSession() else null
        val executor = if (method in setOf("start", "command", "analyze", "storeModel", "loadModel", "validateModel", "deleteModel")) commands else controls
        executor.execute {
            try {
                // An already-detached stop target still needs reaping after Activity disposal.
                if (closed && method != "stop") throw IllegalStateException("KataGo 主机已关闭")
                val value: Any? = when (method) {
                    "start" -> { requireCurrent(ticket); start(args, ticket); "ready" }
                    "command" -> { requireCurrent(ticket); command(args["line"] as String) }
                    "analyze" -> { requireCurrent(ticket); analyze(args) }
                    // Runs off the command queue so it can interrupt a running analysis.
                    "analyzeCancel" -> { analyzeStopAt = System.currentTimeMillis(); "cancelled" }
                    "stop" -> { stopTarget?.process?.let(::terminate); "stopped" }
                    "backendPreflight" -> preflight(args)
                    "diagnostics" -> synchronized(logLock) {
                        mapOf("backend" to session?.backend, "running" to (session?.process?.isAlive == true),
                            "logs" to logLines.toList())
                    }
                    "storeModel" -> { storeModel(args["id"] as String, args["model"] as ByteArray); "stored" }
                    "validateModel" -> {
                        storedModel(mapOf("modelId" to (args["id"] as String)), "model")
                        "verified"
                    }
                    "loadModel" -> modelFile(args["id"] as String).takeIf { it.isFile }?.let {
                        check(it.length() <= 8L * 1024 * 1024) { "大模型请通过模型 ID 读取，禁止整份传输" }
                        it.readBytes()
                    }
                    "deleteModel" -> { val file = modelFile(args["id"] as String); check(!file.exists() || file.delete()); "deleted" }
                    else -> throw IllegalArgumentException("Unknown KataGo method: $method")
                }
                main.post { result.success(value) }
            } catch (error: Exception) {
                log("$method: ${error.message}")
                val code = when (error) {
                    is UnsupportedOperationException -> "KATAGO_UNSUPPORTED"
                    else -> "KATAGO"
                }
                main.post { result.error(code, error.message ?: error.toString(), null) }
            }
        }
    }

    private fun requireCurrent(ticket: Long) {
        check(!closed && ticket == epoch.get()) { "KataGo 请求已取消" }
    }

    private fun backend(args: Map<*, *>): String {
        require(args["backend"] == null || args["backend"] == "cpu") { "仅支持 CPU 后端" }
        return "cpu"
    }

    private fun executable(): File = File(nativeLibraryDir, "libkatago.so").also {
        check(it.isFile && it.canExecute()) { "APK 缺少 CPU 引擎（需要 arm64-v8a）" }
    }

    private fun builder(command: List<String>, dir: File): ProcessBuilder =
        ProcessBuilder(command).directory(dir).also {
            it.environment()["LD_LIBRARY_PATH"] = nativeLibraryDir.absolutePath
        }

    private fun preflight(args: Map<*, *>): Map<String, Any?> = try {
        backend(args)
        mapOf("backend" to "cpu", "available" to true, "runnable" to true,
            "library" to executable().absolutePath)
    } catch (error: Exception) {
        mapOf("backend" to "cpu", "available" to false, "runnable" to false, "reason" to error.message)
    }

    private fun safeConfig(args: Map<*, *>, dir: File): String {
        val reserved = setOf("homeDataDir", "nnMaxBoardSize", "defaultBoardSize", "defaultBoardXSize",
            "defaultBoardYSize", "logDir", "logFile", "logDirDated")
        val source = (args["config"] as? String ?: "").lineSequence().filter {
            it.trim().substringBefore('=').trim() !in reserved
        }.joinToString("\n")
        return "$source\nhomeDataDir = ${dir.absolutePath}\ndefaultBoardSize = ${boardSize(args)}\n"
    }

    private fun boardSize(args: Map<*, *>): Int = (args["boardSize"] as? Number)?.toInt()?.also {
        require(it in setOf(9, 13, 19)) { "棋盘大小无效" }
    } ?: 19

    private fun sha(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it) }

    private fun fileSha(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun storedModel(args: Map<*, *>, prefix: String): File? {
        val id = args["${prefix}Id"] as? String ?: return null
        val file = modelFile(id)
        check(file.isFile && file.length() >= 1024 && fileSha(file) == id) {
            "模型文件缺失或校验失败：$id"
        }
        return file
    }

    private fun prepareModel(dir: File, args: Map<*, *>, prefix: String): File? {
        val name = args["${prefix}FileName"]
        storedModel(args, prefix)?.let { source ->
            val suffix = if ((name as? String)?.lowercase()?.endsWith(".txt.gz") == true) ".txt.gz" else ".bin.gz"
            val target = File(dir, "$prefix$suffix")
            source.inputStream().use { input -> target.outputStream().use { input.copyTo(it) } }
            return target
        }
        return (args[prefix] as? ByteArray)?.let { writeModel(dir, it, prefix, name) }
    }

    private fun writeModel(dir: File, bytes: ByteArray, prefix: String, name: Any?): File {
        require(bytes.size >= 1024) { "模型文件太小" }
        val suffix = if ((name as? String)?.lowercase()?.endsWith(".txt.gz") == true) ".txt.gz" else ".bin.gz"
        return File(dir, "$prefix$suffix").apply { writeBytes(bytes) }
    }

    private fun start(args: Map<*, *>, ticket: Long) = startSession(args, ticket)

    private fun startSession(args: Map<*, *>, ticket: Long) {
        stopSession()
        val backend = backend(args)
        val binary = executable()
        val dir = File(root, "cpu").apply { mkdirs() }
        val model = prepareModel(dir, args, "model") ?: throw IllegalArgumentException("缺少主模型")
        val human = prepareModel(dir, args, "humanModel")
        val config = File(dir, "gtp.cfg").apply { writeText(safeConfig(args, dir)) }
        val argv = mutableListOf(binary.absolutePath, "gtp", "-model", model.absolutePath, "-config", config.absolutePath)
        if (human != null) argv += listOf("-human-model", human.absolutePath)
        val profile = args["humanSLProfile"] as? String
        if (!profile.isNullOrBlank()) {
            require(profile.matches(Regex("[a-zA-Z0-9_-]+"))) { "人类棋风 profile 无效" }
            argv += listOf("-override-config", "humanSLProfile=$profile")
        }
        requireCurrent(ticket)
        val child = builder(argv, dir).start()
        val value = Session(child, child.outputStream.bufferedWriter(), child.inputStream.bufferedReader(), backend)
        synchronized(processLock) {
            if (closed || ticket != epoch.get()) { terminate(child); throw IOException("KataGo 启动已取消") }
            session = value
        }
        Thread { try { child.errorStream.bufferedReader().useLines { lines -> lines.forEach(::log) } }
            catch (_: IOException) {} }.apply { isDaemon = true; name = "katago-stderr"; start() }
        try {
            check(command("protocol_version") == "2") { "KataGo GTP 初始化失败" }
            log("$backend 引擎已启动")
        } catch (error: Exception) { stopSession(); throw error }
    }

    private fun command(line: String): String {
        require(!line.contains('\n') && !line.contains('\r')) { "GTP 命令必须为单行" }
        val value = session ?: throw IllegalStateException("KataGo 尚未启动")
        value.input.apply { write(line); newLine(); flush() }
        val response = StringBuilder()
        while (true) {
            val next = value.output.readLine() ?: throw IOException("KataGo 引擎已退出，请查看引擎日志")
            if (next.isEmpty()) break
            if (response.isNotEmpty()) response.append('\n')
            response.append(next)
        }
        val text = response.toString()
        if (text.startsWith("?")) throw IOException(text.removePrefix("?").trim())
        return text.removePrefix("=").trim()
    }

    /**
     * Runs `kata-analyze` for a bounded slice of time and returns the reports it
     * produced. Unlike every other GTP command, an analysis response has no
     * natural end: KataGo prints `=` and then one report line per interval until
     * the controller sends any further input. We therefore park a reader on the
     * pipe, wait out the budget, and only then terminate the stream with a blank
     * line — the engine answers that with the blank line that closes the GTP
     * response, which keeps the next command's reply from being misread.
     */
    private fun analyze(args: Map<*, *>): Map<String, Any?> {
        val line = args["line"] as? String ?: throw IllegalArgumentException("缺少分析命令")
        require(!line.contains('\n') && !line.contains('\r')) { "GTP 命令必须为单行" }
        val value = session ?: throw IllegalStateException("KataGo 尚未启动")
        val targetVisits = (args["targetVisits"] as? Number)?.toLong() ?: 0L
        val minMillis = ((args["minMillis"] as? Number)?.toLong() ?: 300L).coerceIn(0L, 60_000L)
        val maxMillis = ((args["maxMillis"] as? Number)?.toLong() ?: 5_000L).coerceIn(minMillis, 120_000L)

        val reports = Collections.synchronizedList(mutableListOf<String>())
        val finished = CountDownLatch(1)
        val failure = AtomicReference<Exception?>(null)
        val headerSeen = AtomicBoolean(false)
        val reader = Thread {
            try {
                while (true) {
                    val next = value.output.readLine()
                        ?: throw IOException("KataGo 引擎已退出，请查看引擎日志")
                    if (!headerSeen.get()) {
                        if (next.startsWith("?")) throw IOException(next.removePrefix("?").trim())
                        if (next.startsWith("=")) { headerSeen.set(true); continue }
                        if (next.isEmpty()) { headerSeen.set(true); continue }
                    }
                    if (next.isEmpty()) break
                    reports.add(next)
                }
            } catch (error: Exception) {
                failure.set(error)
            } finally {
                finished.countDown()
            }
        }.apply { isDaemon = true; name = "katago-analyze"; start() }

        value.input.apply { write(line); newLine(); flush() }

        val startedAt = System.currentTimeMillis()
        analyzeStopAt = Long.MAX_VALUE
        var reason = "budget"
        while (true) {
            val now = System.currentTimeMillis()
            if (finished.count == 0L) { reason = "engine"; break }
            if (now - startedAt >= minMillis && targetVisits > 0 &&
                reportedVisits(reports.lastOrNull()) >= targetVisits) { reason = "visits"; break }
            if (now >= analyzeStopAt) { reason = "cancelled"; break }
            if (now - startedAt >= maxMillis) break
            Thread.sleep(20)
        }

        // Any controller input stops the search and completes the response. A
        // `stop` that killed the process first leaves nothing to write to.
        try {
            value.input.apply { newLine(); flush() }
        } catch (_: IOException) {
            // The reader already reported the dead pipe.
        }
        if (!finished.await(maxMillis + 15_000, TimeUnit.MILLISECONDS)) {
            // The pipe is unusable once a reader is stuck on it, so drop the session.
            stopSession()
            throw IOException("KataGo 分析未在预期时间内结束")
        }
        reader.interrupt()
        failure.get()?.let { throw it }
        return mapOf("reports" to reports.toList(), "reason" to reason)
    }

    /** Highest visit count mentioned by a report; `rootInfo` alone carries the root total. */
    private fun reportedVisits(report: String?): Long {
        if (report == null) return 0L
        var best = 0L
        for (match in Regex("\\bvisits (\\d+)").findAll(report)) {
            val value = match.groupValues[1].toLongOrNull() ?: 0L
            if (value > best) best = value
        }
        return best
    }

    private fun log(line: String) {
        synchronized(logLock) { logLines.addLast(line.take(2048)); while (logLines.size > 200) logLines.removeFirst() }
        android.util.Log.i("EasyPlayKataGo", line)
    }

    private fun stopSession() {
        val value = detachSession()
        // Destroy first: this unblocks an outstanding GTP pipe read without waiting for a monitor.
        value?.process?.let(::terminate)
    }

    private fun detachSession(): Session? = synchronized(processLock) {
        val value = session
        session = null
        value
    }

    private fun terminate(child: Process) {
        child.destroy()
        if (!child.waitFor(300, TimeUnit.MILLISECONDS)) {
            child.destroyForcibly()
            child.waitFor(1, TimeUnit.SECONDS)
        }
    }

    private fun modelFile(id: String): File {
        require(id.matches(Regex("[0-9a-f]{64}"))) { "Invalid model id" }
        return File(File(root, "models").apply { mkdirs() }, "$id.bin.gz")
    }

    private fun storeModel(id: String, bytes: ByteArray) {
        require(bytes.size >= 1024) { "KataGo model file is too small" }
        val target = modelFile(id)
        val temporary = File(target.parentFile, "${target.name}.tmp").apply { writeBytes(bytes) }
        check(temporary.renameTo(target)) { "Unable to save model file" }
    }

    fun close() {
        closed = true
        epoch.incrementAndGet()
        controls.execute { stopSession() }
        commands.shutdown()
        controls.shutdown()
    }

}
