package com.easyplay.easyplay

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Test

/** Runs the same inference class used by the Android MethodChannel, with real ORT JNI. */
class DouZeroInferenceTest {
    private val root = File(System.getProperty("easyplayRoot"))
    private val models = File(root, "assets/douzero")
    private val manifest = JsonParser.parseString(File(models, "manifest.json").readText()).asJsonObject.getAsJsonObject("models")
    private val hashes = manifest.entrySet().associate { it.key to it.value.asJsonObject["sha256"].asString }
    private val cases = JsonParser.parseString(File(root, "test/doudizhu/fixtures/douzero_reference.json").readText()).asJsonObject.getAsJsonArray("cases")

    private fun input(data: JsonObject): FloatArray {
        val prefix = data["xPrefix"].asString.map { if (it == '1') 1f else 0f }.toFloatArray()
        val width = prefix.size + 54
        val actions = data.getAsJsonArray("actions")
        val x = FloatArray(width * actions.size())
        actions.forEachIndexed { row, value ->
            prefix.copyInto(x, row * width)
            val counts = IntArray(15)
            value.asJsonArray.forEach { card ->
                val id = card.asInt
                counts[if (id < 52) id / 4 else id - 39]++
            }
            for (rank in 0..12) for (copy in 0 until counts[rank]) x[row * width + prefix.size + rank * 4 + copy] = 1f
            x[row * width + prefix.size + 52] = counts[13].toFloat()
            x[row * width + prefix.size + 53] = counts[14].toFloat()
        }
        val bytes = ByteBuffer.allocate(x.size * 4).order(ByteOrder.LITTLE_ENDIAN)
        bytes.asFloatBuffer().put(x)
        val actual = MessageDigest.getInstance("SHA-256").digest(bytes.array()).joinToString("") { "%02x".format(it.toInt() and 255) }
        assertEquals(data["xSha256"].asString, actual)
        return x
    }

    @Test fun allRolesMatchOriginalPyTorchAndBatchBoundaries() {
        DouZeroInference({ role -> File(models, "$role.onnx").readBytes() }, hashes).use { engine ->
            for (entry in cases) {
                val data = entry.asJsonObject
                val role = data["role"].asString
                val x = input(data)
                val z = data["z"].asString.map { if (it == '1') 1f else 0f }.toFloatArray()
                val expected = data.getAsJsonArray("values").map { it.asFloat }
                val actual = engine.score(role, x, z)
                assertEquals(expected.size, actual.size)
                actual.forEachIndexed { i, score -> assertEquals("${data["name"].asString} action $i", expected[i], score, 0.00002f) }
                val width = if (role == "landlord") 373 else 484
                val repeated = FloatArray(257 * width) { index -> x[(index / width % expected.size) * width + index % width] }
                val batched = engine.score(role, repeated, z)
                batched.forEachIndexed { i, score -> assertEquals(expected[i % expected.size], score, 0.00002f) }
            }
        }
    }

    @Test fun corruptedModelIsRejectedBeforeInference() {
        DouZeroInference({ role -> File(models, "$role.onnx").readBytes().also { it[0] = (it[0].toInt() xor 1).toByte() } }, hashes).use { engine ->
            assertThrows(IllegalArgumentException::class.java) { engine.score("landlord", FloatArray(373), FloatArray(810)) }
        }
    }
}
