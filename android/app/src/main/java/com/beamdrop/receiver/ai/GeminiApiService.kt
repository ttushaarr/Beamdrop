package com.beamdrop.receiver.ai

import android.content.Context
import android.util.Base64
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class GeminiApiService(private val context: Context) {

    companion object {
        private const val TAG = "GeminiApiService"
        private const val PREFS_NAME = "beamdrop_ai_prefs"
        private const val KEY_GEMINI_API_KEY = "gemini_api_key"
        private const val DEFAULT_MODEL = "gemini-1.5-flash"
    }

    fun getApiKey(): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_GEMINI_API_KEY, "")?.trim() ?: ""
    }

    fun saveApiKey(key: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(KEY_GEMINI_API_KEY, key.trim()).apply()
    }

    fun hasApiKey(): Boolean = getApiKey().isNotEmpty()

    suspend fun solveQuestionFromImage(
        imageFile: File,
        customPrompt: String? = null
    ): AiSolveResult = withContext(Dispatchers.IO) {
        val apiKey = getApiKey()
        if (apiKey.isEmpty()) {
            return@withContext AiSolveResult(
                success = false,
                errorMessage = "Gemini API key not found. Please enter your free Google Gemini API key to start solving questions automatically."
            )
        }

        if (!imageFile.exists() || imageFile.length() == 0L) {
            return@withContext AiSolveResult(
                success = false,
                errorMessage = "Question screenshot file not found or empty."
            )
        }

        try {
            val imageBytes = imageFile.readBytes()
            val base64Image = Base64.encodeToString(imageBytes, Base64.NO_WRAP)

            val systemInstructions = customPrompt ?: """
You are an expert AI tutor, competitive programmer, and exam question solver.
Carefully examine the screenshot provided. Locate the question, problem statement, quiz question, or code challenge shown.

Format your response cleanly in GitHub Markdown using this structure:

### 🎯 Identified Question
[Quote or summarize the exact question clearly]

### 💡 Step-by-Step Solution & Reasoning
[Provide clear, step-by-step logic, mathematical formulas, or executable code with syntax highlighting]

### 🏁 Final Answer
[State the exact concise answer or selected option (e.g., Option B: 42) highlighted clearly]
""".trimIndent()

            val requestJson = JSONObject().apply {
                val contents = JSONArray()
                val contentObj = JSONObject()
                val parts = JSONArray()

                // Prompt part
                parts.put(JSONObject().apply {
                    put("text", systemInstructions)
                })

                // Image part
                val inlineData = JSONObject().apply {
                    put("mimeType", "image/png")
                    put("data", base64Image)
                }
                parts.put(JSONObject().apply {
                    put("inlineData", inlineData)
                })

                contentObj.put("parts", parts)
                contents.put(contentObj)
                put("contents", contents)

                // Fast generation parameters
                val genConfig = JSONObject().apply {
                    put("temperature", 0.2)
                    put("maxOutputTokens", 2500)
                }
                put("generationConfig", genConfig)
            }

            val endpoint = "https://generativelanguage.googleapis.com/v1beta/models/$DEFAULT_MODEL:generateContent?key=$apiKey"
            val url = URL(endpoint)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
            conn.doOutput = true
            conn.doInput = true
            conn.connectTimeout = 30000
            conn.readTimeout = 45000

            OutputStreamWriter(conn.outputStream, "UTF-8").use { writer ->
                writer.write(requestJson.toString())
                writer.flush()
            }

            val code = conn.responseCode
            if (code == 200) {
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                val respJson = JSONObject(body)
                val candidates = respJson.optJSONArray("candidates")
                if (candidates != null && candidates.length() > 0) {
                    val candidate = candidates.getJSONObject(0)
                    val content = candidate.optJSONObject("content")
                    val partsArr = content?.optJSONArray("parts")
                    if (partsArr != null && partsArr.length() > 0) {
                        val text = partsArr.getJSONObject(0).optString("text", "")
                        return@withContext AiSolveResult(
                            success = true,
                            solutionText = text
                        )
                    }
                }
                return@withContext AiSolveResult(
                    success = false,
                    errorMessage = "Gemini returned an empty response. Please try again."
                )
            } else {
                val errBody = conn.errorStream?.bufferedReader()?.use { it.readText() } ?: "HTTP $code"
                val message = try {
                    val errJson = JSONObject(errBody)
                    errJson.optJSONObject("error")?.optString("message") ?: errBody
                } catch (_: Exception) {
                    errBody
                }
                Log.e(TAG, "Gemini API failed with HTTP $code: $message")
                return@withContext AiSolveResult(
                    success = false,
                    errorMessage = "Gemini Error ($code): $message"
                )
            }

        } catch (e: Exception) {
            Log.e(TAG, "Exception calling Gemini API: ${e.message}", e)
            return@withContext AiSolveResult(
                success = false,
                errorMessage = "Network or connection error: ${e.localizedMessage ?: e.message}"
            )
        }
    }

    suspend fun askFollowUp(
        imageFile: File,
        originalSolution: String,
        followUpQuestion: String
    ): AiSolveResult = withContext(Dispatchers.IO) {
        val prompt = """
Previous Solution:
$originalSolution

Follow-up User Question:
$followUpQuestion

Please provide a clear and direct answer addressing the user's follow-up question.
""".trimIndent()
        solveQuestionFromImage(imageFile, prompt)
    }
}
