package com.example.fcmplayground

import android.content.Context
import java.util.UUID

object EmailManager {

    private const val PREFS_NAME = "fcm_playground_prefs"
    private const val KEY_EMAIL = "user_email"
    
    // Lock object for thread synchronization
    private val lock = Any()

    /**
     * Get or create a default email for the user
     * Uses device_id to generate a deterministic email
     * Format: device-{deviceId}@fcm-playground.local
     */
    fun getOrCreateEmail(context: Context, deviceId: String): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        // Use synchronized block to prevent race condition
        synchronized(lock) {
            // Double-check: read again inside synchronized block
            val existing = prefs.getString(KEY_EMAIL, null)
            if (existing != null) {
                return existing
            }

            // Generate default email based on device_id
            val newEmail = "device-${deviceId}@fcm-playground.local"
            // Use commit() instead of apply() to ensure synchronous write
            prefs.edit().putString(KEY_EMAIL, newEmail).commit()
            return newEmail
        }
    }

    /**
     * Set a custom email for the user
     */
    fun setEmail(context: Context, email: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(KEY_EMAIL, email).apply()
    }

    /**
     * Get the current email (if set)
     */
    fun getEmail(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_EMAIL, null)
    }
}

