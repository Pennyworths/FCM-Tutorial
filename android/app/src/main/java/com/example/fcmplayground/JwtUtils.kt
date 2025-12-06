package com.example.fcmplayground

import android.util.Base64
import android.util.Log
import org.json.JSONObject

object JwtUtils {
    private const val TAG = "JwtUtils"
    
    /**
     * Parse JWT token and extract payload as JSONObject
     * JWT format: header.payload.signature
     */
    private fun parseJwtPayload(token: String): JSONObject? {
        return try {
            val parts = token.split(".")
            if (parts.size != 3) {
                Log.e(TAG, "Invalid JWT format: expected 3 parts, got ${parts.size}")
                return null
            }
            
            // Decode payload (second part)
            val payload = parts[1]
            // Add padding if needed for Base64 decoding
            val paddedPayload = when (payload.length % 4) {
                2 -> "$payload=="
                3 -> "$payload="
                else -> payload
            }
            
            val decodedBytes = Base64.decode(paddedPayload, Base64.URL_SAFE)
            val jsonString = String(decodedBytes, Charsets.UTF_8)
            JSONObject(jsonString)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse JWT payload", e)
            null
        }
    }
    
    /**
     * Get subject (user ID) from JWT token
     */
    fun getSubject(token: String): String? {
        val payload = parseJwtPayload(token) ?: return null
        return payload.optString("sub", null).takeIf { it.isNotBlank() }
    }
    
    /**
     * Get email from JWT token
     */
    fun getEmail(token: String): String? {
        val payload = parseJwtPayload(token) ?: return null
        return payload.optString("email", null).takeIf { it.isNotBlank() }
    }
}

