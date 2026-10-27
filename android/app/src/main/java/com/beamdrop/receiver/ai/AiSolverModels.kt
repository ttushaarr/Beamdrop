package com.beamdrop.receiver.ai

import java.io.Serializable

data class AiQuestionItem(
    val id: String = java.util.UUID.randomUUID().toString(),
    val imagePath: String,
    val fileName: String,
    val timestamp: Long = System.currentTimeMillis(),
    val isSolving: Boolean = false,
    val solutionMarkdown: String? = null,
    val errorMessage: String? = null
) : Serializable

data class AiSolveResult(
    val success: Boolean,
    val solutionText: String? = null,
    val errorMessage: String? = null
)
