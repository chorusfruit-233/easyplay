package com.easyplay.easyplay

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.nio.FloatBuffer
import java.security.MessageDigest

/** CPU inference only. Caller supplies public-observation tensors, never a Session. */
class DouZeroInference(
    private val readModel: (String) -> ByteArray,
    private val hashes: Map<String, String>,
) : AutoCloseable {
    private val environment = OrtEnvironment.getEnvironment()
    private val sessions = mutableMapOf<String, OrtSession>()

    private fun session(role: String): OrtSession = sessions.getOrPut(role) {
        val expected = hashes[role] ?: error("Invalid DouZero role")
        val bytes = readModel(role)
        val actual = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        require(actual == expected) { "DouZero model checksum mismatch" }
        OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(1)
            options.setInterOpNumThreads(1)
            options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            environment.createSession(bytes, options)
        }
    }

    fun score(role: String, x: FloatArray, z: FloatArray): FloatArray {
        require(role in setOf("landlord", "landlord_up", "landlord_down"))
        val width = if (role == "landlord") 373 else 484
        require(z.size == 810 && x.size % width == 0 && x.size / width in 1..16384)
        require(x.all { it.isFinite() } && z.all { it.isFinite() })
        val session = session(role)
        val count = x.size / width
        val scores = FloatArray(count)
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(z), longArrayOf(1, 5, 162)).use { history ->
            for (start in 0 until count step 128) {
                val end = minOf(count, start + 128)
                val batch = x.copyOfRange(start * width, end * width)
                OnnxTensor.createTensor(environment, FloatBuffer.wrap(batch), longArrayOf((end - start).toLong(), width.toLong())).use { candidates ->
                    session.run(mapOf("x" to candidates, "z" to history)).use { output ->
                        val tensor = output[0] as OnnxTensor
                        val values = tensor.floatBuffer
                        require(values.remaining() == end - start)
                        values.get(scores, start, end - start)
                    }
                }
            }
        }
        require(scores.all { it.isFinite() })
        return scores
    }

    override fun close() {
        sessions.values.forEach { it.close() }
        sessions.clear()
        // OrtEnvironment is shared process-wide; do not close it here.
    }
}
