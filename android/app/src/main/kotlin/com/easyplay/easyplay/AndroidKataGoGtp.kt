package com.easyplay.easyplay

import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Every native engine and driver runs in a child process, never in Flutter's VM. */
internal class AndroidKataGoGtp(
    private val filesDir: File,
    private val nativeLibraryDir: File,
) {
    private val commands = Executors.newSingleThreadExecutor()
    private val controls = Executors.newCachedThreadPool()
    private val tuner = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val epoch = AtomicLong()
    private val processLock = Any()
    private val tuningLock = Any()
    private val logLock = Any()
    private val logLines = ArrayDeque<String>()
    private val tuningJobs = ConcurrentHashMap<String, TuningJob>()
    @Volatile private var session: Session? = null
    @Volatile private var closed = false
    @Volatile private var activeTuning: TuningJob? = null
    @Volatile private var startingBackend: String? = null
    private val root = File(filesDir, "katago").apply { mkdirs() }

    private data class Session(val process: Process, val input: BufferedWriter, val output: BufferedReader, val backend: String)
    private class TuningJob(val id: String, val key: String) {
        @Volatile var status = "queued"
        @Volatile var process: Process? = null
        @Volatile var error: String? = null
        @Volatile var stage = "准备模型"
        val logs = ArrayDeque<String>()
        fun snapshot(): Map<String, Any?> = synchronized(this) {
            mapOf("id" to id, "tuningId" to key, "status" to status, "stage" to stage,
                "error" to error, "logs" to logs.toList())
        }
    }

    fun execute(method: String, arguments: Any?, result: MethodChannel.Result) {
        if (closed) { result.error("KATAGO_CLOSED", "KataGo 主机已关闭", null); return }
        val args = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        // A stop invalidates work already queued before it, including a pending startup.
        val ticket = if (method == "stop") epoch.incrementAndGet() else epoch.get()
        val stopTarget = if (method == "stop") detachSession() else null
        val executor = if (method in setOf("start", "command", "storeModel", "loadModel", "deleteModel")) commands else controls
        executor.execute {
            try {
                // An already-detached stop target still needs reaping after Activity disposal.
                if (closed && method != "stop") throw IllegalStateException("KataGo 主机已关闭")
                val value: Any? = when (method) {
                    "start" -> { requireCurrent(ticket); start(args, ticket); "ready" }
                    "command" -> { requireCurrent(ticket); command(args["line"] as String) }
                    "stop" -> { stopTarget?.process?.let(::terminate); "stopped" }
                    "backendPreflight" -> preflight(args)
                    "openclTuningStart" -> startTuning(args)
                    "openclTuningRead" -> tuningJob(args).snapshot()
                    "openclTuningCancel" -> { val job = tuningJob(args); cancelTuning(job); job.snapshot() }
                    "openclTuningReset" -> resetTuning(args)
                    "diagnostics" -> synchronized(logLock) {
                        mapOf("backend" to session?.backend, "running" to (session?.process?.isAlive == true),
                            "logs" to logLines.toList(), "tuning" to activeTuning?.snapshot())
                    }
                    "storeModel" -> { storeModel(args["id"] as String, args["model"] as ByteArray); "stored" }
                    "loadModel" -> modelFile(args["id"] as String).takeIf { it.isFile }?.readBytes()
                    "deleteModel" -> { val file = modelFile(args["id"] as String); check(!file.exists() || file.delete()); "deleted" }
                    else -> throw IllegalArgumentException("Unknown KataGo method: $method")
                }
                main.post { result.success(value) }
            } catch (error: Exception) {
                log("$method: ${error.message}")
                val code = when (error) {
                    is UnsupportedOperationException -> "KATAGO_UNSUPPORTED"
                    is TuningRequired -> "KATAGO_TUNING_REQUIRED"
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
        val value = args["backend"] as? String ?: "cpu"
        require(value in setOf("cpu", "opencl", "tflite")) { "未知 KataGo 后端：$value" }
        return value
    }

    private fun executable(backend: String): File {
        if (backend == "tflite") throw UnsupportedOperationException(
            "TFLite 需要参考应用私有的 LiteRT KataGo 后端；上游 KataGo 未提供此后端，当前构建不可运行 .tflite 模型。")
        val name = if (backend == "opencl") "libkatago-opencl.so" else "libkatago.so"
        return File(nativeLibraryDir, name).also {
            check(it.isFile && it.canExecute()) { "APK 未包含可执行的 $name（需要 arm64-v8a）" }
        }
    }

    private fun builder(command: List<String>, dir: File, args: Map<*, *>): ProcessBuilder {
        val builder = ProcessBuilder(command).directory(dir)
        builder.environment()["LD_LIBRARY_PATH"] = nativeLibraryDir.absolutePath
        (args["openclLibraryName"] as? String)?.trim()?.takeIf { it.isNotEmpty() }?.let {
            require(!it.contains('\n') && !it.contains('\u0000')) { "OpenCL 动态库路径无效" }
            builder.environment()["EASYPLAY_OPENCL_LIBRARY"] = it
        }
        return builder
    }

    private fun preflight(args: Map<*, *>): Map<String, Any?> {
        val backend = backend(args)
        try {
            val binary = executable(backend)
            if (backend == "cpu") return mapOf("backend" to backend, "available" to true,
                "runnable" to true, "library" to binary.absolutePath, "devices" to emptyList<Any>())
            val probe = File(nativeLibraryDir, "libkatago-opencl-probe.so")
            check(probe.isFile && probe.canExecute()) { "APK 缺少 OpenCL 检测程序" }
            val child = builder(listOf(probe.absolutePath), root, args).redirectErrorStream(true).start()
            val output = StringBuilder()
            val reader = Thread {
                try { child.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { synchronized(output) { if (output.length < 32768) output.append(it).append('\n') } }
                } } catch (_: IOException) { /* A timed-out probe closes its pipe. */ }
            }.apply { isDaemon = true; start() }
            if (!child.waitFor(8, TimeUnit.SECONDS)) { terminate(child); throw IOException("OpenCL 设备检测超时") }
            reader.join(500)
            val text = synchronized(output) { output.toString() }
            text.lineSequence().filter { !it.startsWith("{") }.forEach(::log)
            val json = JSONObject(text.lineSequence().firstOrNull { it.startsWith("{") }
                ?: throw IOException("OpenCL 检测失败：$text"))
            val devices = json.optJSONArray("devices")
            val list = (0 until (devices?.length() ?: 0)).map { i ->
                val device = devices!!.getJSONObject(i)
                mapOf("index" to device.getInt("index"), "name" to device.getString("name"),
                    "vendor" to device.getString("vendor"), "version" to device.getString("version"))
            }
            val gpu = gpuIndex(args)
            val available = json.optBoolean("available") && (gpu < 0 || list.any { it["index"] == gpu })
            val key = if (args["model"] is ByteArray) tuningKey(args) else null
            return mapOf("backend" to backend, "available" to available, "runnable" to available,
                "library" to binary.absolutePath, "devices" to list,
                "reason" to if (available) null else "未找到可访问的 OpenCL GPU，请检查 GPU 编号和厂商驱动",
                "tuningId" to key, "tuned" to (key?.let { isTuned(it) } ?: false))
        } catch (error: Exception) {
            return mapOf("backend" to backend, "available" to false, "runnable" to false,
                "devices" to emptyList<Any>(), "reason" to error.message)
        }
    }

    private fun gpuIndex(args: Map<*, *>): Int = (args["openclGpuIdx"] as? Number)?.toInt()?.also {
        require(it >= -1 && it < 1024) { "OpenCL GPU 编号无效" }
    } ?: -1

    private fun boardSize(args: Map<*, *>): Int = ((args["boardSize"] as? Number)?.toInt() ?: 19).also {
        require(it in setOf(9, 13, 19)) { "棋盘路数无效" }
    }

    private fun sha(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it) }

    private fun tuningConfig(args: Map<*, *>): String =
        (args["config"] as? String ?: "").lineSequence().map { it.substringBefore('#').trim() }
            .filter {
                val key = it.substringBefore('=').trim()
                key.startsWith("opencl") || key.startsWith("nn") || key == "numSearchThreads"
            }.sorted().joinToString("\n")

    private fun tuningKey(args: Map<*, *>): String {
        val model = args["model"] as? ByteArray ?: throw IllegalArgumentException("缺少主模型")
        val human = args["humanModel"] as? ByteArray
        val identity = listOf("katago-v1.16.5-loader1", sha(model), human?.let(::sha) ?: "",
            boardSize(args).toString(), gpuIndex(args).toString(), args["openclLibraryName"] ?: "auto",
            tuningConfig(args), Build.FINGERPRINT).joinToString("\n")
        return sha(identity.toByteArray(Charsets.UTF_8))
    }

    private fun tuningDir(key: String): File {
        require(key.matches(Regex("[0-9a-f]{64}"))) { "无效的调优标识" }
        return File(root, "tuning/$key")
    }

    private fun isTuned(key: String): Boolean {
        val dir = tuningDir(key)
        val marker = File(dir, "complete.json")
        if (!marker.isFile) return false
        return try {
            val files = JSONObject(marker.readText()).getJSONObject("files")
            files.length() > 0 && files.keys().asSequence().all { name ->
                val file = File(File(dir, "opencltuning"), name)
                file.isFile && sha(file.readBytes()) == files.getString(name)
            }
        } catch (_: Exception) { false }
    }

    private fun safeConfig(args: Map<*, *>, dir: File, opencl: Boolean): String {
        // These paths belong to the host. All user search settings remain intact.
        val reserved = setOf("homeDataDir", "openclTunerFile", "openclReTunePerBoardSize", "openclDeviceToUse",
            "nnMaxBoardSize", "defaultBoardSize", "defaultBoardXSize", "defaultBoardYSize", "logDir", "logFile", "logDirDated")
        val source = (args["config"] as? String ?: "").lineSequence().filter {
            val key = it.trim().substringBefore('=').trim()
            key !in reserved
        }.joinToString("\n")
        val size = boardSize(args)
        return "$source\nhomeDataDir = ${dir.absolutePath}\ndefaultBoardSize = $size\n" +
            if (opencl) "openclReTunePerBoardSize = true\n" +
                if (gpuIndex(args) >= 0) "openclDeviceToUse = ${gpuIndex(args)}\n" else "" else ""
    }

    private fun writeModel(dir: File, bytes: ByteArray, prefix: String, name: Any?): File {
        require(bytes.size >= 1024) { "模型文件太小" }
        val suffix = if ((name as? String)?.lowercase()?.endsWith(".txt.gz") == true) ".txt.gz" else ".bin.gz"
        return File(dir, "$prefix$suffix").apply { writeBytes(bytes) }
    }

    private fun start(args: Map<*, *>, ticket: Long) {
        synchronized(tuningLock) {
            check(activeTuning?.status !in setOf("queued", "running")) { "OpenCL 调优正在运行，请完成或取消后再开始对局" }
            startingBackend = backend(args)
        }
        try { startSession(args, ticket) }
        finally { synchronized(tuningLock) { startingBackend = null } }
    }

    private fun startSession(args: Map<*, *>, ticket: Long) {
        stopSession()
        val backend = backend(args)
        val binary = executable(backend)
        val dir = if (backend == "opencl") {
            val key = tuningKey(args)
            if (!isTuned(key)) throw TuningRequired("请先针对当前模型、棋盘、GPU 和配置完成 OpenCL 调优")
            tuningDir(key)
        } else File(root, "cpu").apply { mkdirs() }
        val model = writeModel(dir, args["model"] as ByteArray, "model", args["modelFileName"])
        val human = (args["humanModel"] as? ByteArray)?.let { writeModel(dir, it, "human", args["humanModelFileName"]) }
        val config = File(dir, "gtp.cfg").apply { writeText(safeConfig(args, dir, backend == "opencl")) }
        val argv = mutableListOf(binary.absolutePath, "gtp", "-model", model.absolutePath, "-config", config.absolutePath)
        if (human != null) argv += listOf("-human-model", human.absolutePath)
        val profile = args["humanSLProfile"] as? String
        if (!profile.isNullOrBlank()) {
            require(profile.matches(Regex("[a-zA-Z0-9_-]+"))) { "人类棋风 profile 无效" }
            argv += listOf("-override-config", "humanSLProfile=$profile")
        }
        requireCurrent(ticket)
        val child = builder(argv, dir, args).start()
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

    private fun startTuning(args: Map<*, *>): Map<String, Any?> = synchronized(tuningLock) {
        executable("opencl")
        check(activeTuning?.status !in setOf("queued", "running")) { "已有 OpenCL 调优正在运行" }
        check(session == null && startingBackend == null) { "请先结束当前 AI 对局，再进行 OpenCL 调优" }
        val key = tuningKey(args)
        val job = TuningJob(UUID.randomUUID().toString(), key)
        if (isTuned(key) && args["force"] != true) { job.status = "completed"; job.stage = "已使用缓存" }
        tuningJobs[job.id] = job
        activeTuning = job
        if (job.status != "completed") tuner.execute { runTuning(job, args) }
        job.snapshot()
    }

    private fun runTuning(job: TuningJob, args: Map<*, *>) {
        val dir = tuningDir(job.key).apply { mkdirs() }
        val marker = File(dir, "complete.json")
        try {
            synchronized(job) {
                if (job.status == "cancelled" || closed) return
                job.status = "running"
            }
            marker.delete()
            val config = File(dir, "tune.cfg").apply { writeText(safeConfig(args, dir, true)) }
            val models = mutableListOf(writeModel(dir, args["model"] as ByteArray, "model", args["modelFileName"]))
            (args["humanModel"] as? ByteArray)?.let { models += writeModel(dir, it, "human", args["humanModelFileName"]) }
            for ((index, model) in models.withIndex()) {
                if (job.status == "cancelled" || closed) return
                job.stage = if (index == 0) "调优主模型" else "调优人类棋风模型"
                val size = boardSize(args).toString()
                val argv = mutableListOf(executable("opencl").absolutePath, "tuner", "-model", model.absolutePath,
                    "-config", config.absolutePath, "-xsize", size, "-ysize", size)
                if (gpuIndex(args) >= 0) argv += listOf("-gpus", gpuIndex(args).toString())
                val child = builder(argv, dir, args).redirectErrorStream(true).start()
                synchronized(job) {
                    job.process = child
                    if (job.status == "cancelled" || closed) terminate(child)
                }
                child.inputStream.bufferedReader().useLines { lines -> lines.forEach { line ->
                    log(line)
                    synchronized(job) { job.logs.addLast(line.take(2048)); while (job.logs.size > 160) job.logs.removeFirst() }
                } }
                val exitCode = child.waitFor()
                job.process = null
                if (job.status == "cancelled") return
                check(exitCode == 0) { "OpenCL 调优进程退出：$exitCode；${job.logs.lastOrNull().orEmpty()}" }
            }
            val files = File(dir, "opencltuning").listFiles()?.filter { it.isFile && it.length() > 0 }.orEmpty()
            check(files.isNotEmpty()) { "调优未生成有效缓存" }
            val hashes = JSONObject()
            files.forEach { hashes.put(it.name, sha(it.readBytes())) }
            synchronized(job) {
                if (job.status != "cancelled" && !closed) {
                    marker.writeText(JSONObject().put("files", hashes).toString())
                    job.status = "completed"
                    job.stage = "调优完成"
                }
            }
        } catch (error: Exception) {
            synchronized(job) { if (job.status != "cancelled") {
                job.status = "failed"; job.error = error.message; job.stage = "调优失败"
            } }
        } finally { job.process?.let(::terminate); job.process = null }
    }

    private fun tuningJob(args: Map<*, *>): TuningJob {
        val id = args["id"] as? String
        // A stale page must not accidentally cancel the latest unrelated task.
        return (if (id == null) activeTuning else tuningJobs[id])
            ?: throw IllegalArgumentException("没有调优任务：${id.orEmpty()}")
    }

    private fun cancelTuning(job: TuningJob) {
        val child = synchronized(job) {
            if (job.status in setOf("completed", "failed", "cancelled")) return
            job.status = "cancelled"; job.stage = "调优已取消"; job.process
        }
        child?.let(::terminate)
    }

    private fun resetTuning(args: Map<*, *>): Map<String, Any> = synchronized(tuningLock) {
        check(session?.backend != "opencl" && startingBackend != "opencl") { "请先结束 OpenCL 对局" }
        val key = args["tuningId"] as? String ?: tuningKey(args)
        activeTuning?.takeIf { it.key == key }?.let(::cancelTuning)
        // Wait behind cancelled file writes, so they cannot recreate a reset cache.
        tuner.submit {
            check(!tuningDir(key).exists() || tuningDir(key).deleteRecursively()) { "无法清除 OpenCL 调优缓存" }
        }.get(10, TimeUnit.SECONDS)
        mapOf("tuningId" to key, "reset" to true)
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
        controls.execute { stopSession(); activeTuning?.let(::cancelTuning) }
        commands.shutdown()
        tuner.shutdown()
        controls.shutdown()
    }

    private class TuningRequired(message: String) : IllegalStateException(message)
}
