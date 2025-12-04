package com.example.fcmplayground

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object FcmTokenStore {
    private const val PREFS_NAME = "fcm_playground_prefs"
    private const val KEY_FCM_TOKEN = "fcm_token"

    // StateFlow for UI to subscribe to token changes
    private val _tokenFlow = MutableStateFlow<String?>(null)
    val tokenFlow: StateFlow<String?> = _tokenFlow.asStateFlow()

    fun saveToken(context: Context, token: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(KEY_FCM_TOKEN, token).apply()
        _tokenFlow.value = token  // Update Flow for UI
    }

    fun getToken(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_FCM_TOKEN, null)
    }

    // Initialize Flow from SharedPreferences
    fun initFlow(context: Context) {
        _tokenFlow.value = getToken(context)
    }
}


