package com.example.fcmplayground

import android.content.Context
import java.util.UUID

object UserIdManager {

    private const val PREFS_NAME = "fcm_playground_prefs"
    private const val KEY_USER_ID = "user_id"

    fun getOrCreateUserId(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_USER_ID, null)
        if (existing != null) {
            return existing
        }

        val newId = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_USER_ID, newId).apply()
        return newId
    }
}

