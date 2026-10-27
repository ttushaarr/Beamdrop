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
        val CANDIDATE_MODELS = listOf(
            "gemini-3.5-flash-lite",
            "gemini-3.5-flash",
            "gemini-2.5-flash",
            "gemini-flash-latest",
            "gemini-2.0-flash",
            "gemini-1.5-flash"
        )
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
You are a friendly, brilliant tutor and expert problem solver.
Carefully examine the screenshot. Locate the exact question, test problem, or coding challenge shown.

Explain everything in SIMPLE, NATURAL, EASY-TO-READ HUMAN LANGUAGE:
- Write in plain English as if explaining to a smart friend.
- NEVER use LaTeX math notation or dollar signs (do NOT write ${'$'}O(n)${'$'} or ${'$'}x${'$'}). Write plain readable text (e.g., O(n) time, O(1) space, num % 3 != 0).
- For coding problems, explain the intuitive trick in 2-3 simple bullet points, then provide the complete, clean, working code.
- For multiple-choice or math problems, clearly state the correct option and answer.

Please structure your response into these 3 clear sections:

### 🎯 The Question
[Explain in 1-2 simple sentences what the problem is asking for]

### 💡 Simple Explanation
[Explain the core logic in plain, easy-to-understand words with clean bullet points]

### 🏁 Final Answer & Code
[State the exact concise answer and complete clean code]
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

            var lastErrorMessage = "Unable to connect to Gemini API."

            // Try candidate models in order of speed and availability
            for (model in CANDIDATE_MODELS) {
                try {
                    val endpoint = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey"
                    val url = URL(endpoint)
                    val conn = url.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                    conn.doOutput = true
                    conn.doInput = true
                    conn.connectTimeout = 15000
                    conn.readTimeout = 30000

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
                    } else if (code == 404 || code == 503 || code == 429) {
                        // Model not available or high demand; automatically fall back to next candidate model
                        Log.w(TAG, "Model $model returned HTTP $code, attempting next candidate...")
                        continue
                    } else {
                        val errBody = conn.errorStream?.bufferedReader()?.use { it.readText() } ?: "HTTP $code"
                        val message = try {
                            val errJson = JSONObject(errBody)
                            errJson.optJSONObject("error")?.optString("message") ?: errBody
                        } catch (_: Exception) {
                            errBody
                        }
                        Log.e(TAG, "Gemini model $model failed with HTTP $code: $message")
                        lastErrorMessage = "Gemini Error ($code): $message"
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error connecting with model $model: ${e.message}")
                    lastErrorMessage = "Network error: ${e.localizedMessage ?: e.message}"
                }
            }

            return@withContext AiSolveResult(
                success = false,
                errorMessage = lastErrorMessage
            )

        } catch (e: Exception) {
            Log.e(TAG, "Exception calling Gemini API: ${e.message}", e)
            return@withContext AiSolveResult(
                success = false,
                errorMessage = "Error: ${e.localizedMessage ?: e.message}"
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
