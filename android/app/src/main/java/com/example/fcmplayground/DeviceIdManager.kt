package com.example.fcmplayground

import android.content.Context
import java.util.UUID

object DeviceIdManager {

    private const val PREFS_NAME = "fcm_playground_prefs"
    private const val KEY_DEVICE_ID = "device_id"
    
    // Lock object for thread synchronization
    private val lock = Any()

    fun getOrCreateDeviceId(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        // Use synchronized block to prevent race condition when multiple threads
        // call this function simultaneously before a device ID exists
        synchronized(lock) {
            // Double-check: read again inside synchronized block
            val existing = prefs.getString(KEY_DEVICE_ID, null)
            if (existing != null) {
                return existing
            }

            val newId = UUID.randomUUID().toString()
            // Use commit() instead of apply() to ensure synchronous write
            // This guarantees that the value is written before other threads can read it
            prefs.edit().putString(KEY_DEVICE_ID, newId).commit()
            return newId
        }
    }
}

