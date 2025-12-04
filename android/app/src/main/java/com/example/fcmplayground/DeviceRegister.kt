package com.example.fcmplayground

import android.content.Context
import android.util.Log
import android.widget.Toast
import kotlinx.coroutines.*
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object DeviceRegister {
    private const val TAG = "API"
    private const val HTTP_METHOD_POST = "POST"
    private const val HTTP_HEADER_CONTENT_TYPE = "Content-Type"
    private const val HTTP_CONTENT_TYPE_JSON = "application/json"
    private const val JSON_KEY_USER_ID = "user_id"
    private const val JSON_KEY_DEVICE_ID = "device_id"
    private const val JSON_KEY_FCM_TOKEN = "fcm_token"
    private const val JSON_KEY_PLATFORM = "platform"
    private const val PLATFORM_ANDROID = "android"
    private const val TOAST_TOKEN_NOT_READY = "FCM token not ready yet"
    private const val CONNECTION_TIMEOUT_MS = 10_000
    private const val READ_TIMEOUT_MS = 10_000

    fun registerDevice(
        context: Context,
        userId: String,
        deviceId: String,
        fcmToken: String,
        apiBaseUrl: String
    ) {
        if (fcmToken.startsWith(MainActivity.FCM_TOKEN_NOT_PREFIX)) {
            Toast.makeText(
                context.applicationContext,
                TOAST_TOKEN_NOT_READY,
                Toast.LENGTH_SHORT
            ).show()
            return
        }

        val jsonBody = JSONObject().apply {
            put(JSON_KEY_USER_ID, userId)
            put(JSON_KEY_DEVICE_ID, deviceId)
            put(JSON_KEY_FCM_TOKEN, fcmToken)
            put(JSON_KEY_PLATFORM, PLATFORM_ANDROID)
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val url = URL("$apiBaseUrl${ApiRoutes.DEVICES_REGISTER}")
                Log.d(TAG, "$HTTP_METHOD_POST $url body=$jsonBody")

                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = HTTP_METHOD_POST
                    connectTimeout = CONNECTION_TIMEOUT_MS
                    readTimeout = READ_TIMEOUT_MS
                    doOutput = true
                    setRequestProperty(HTTP_HEADER_CONTENT_TYPE, HTTP_CONTENT_TYPE_JSON)
                }

                conn.outputStream.use { os ->
                    os.write(jsonBody.toString().toByteArray(Charsets.UTF_8))
                }

                val code = conn.responseCode
                val responseText = try {
                    conn.inputStream.bufferedReader().use { it.readText() }
                } catch (_: Exception) {
                    ""
                }
                conn.disconnect()

                Log.d(TAG, "registerDevice HTTP $code, response=$responseText")

                withContext(Dispatchers.Main) {
                    Toast.makeText(
                        context.applicationContext,
                        "registerDevice: HTTP $code",
                        Toast.LENGTH_SHORT
                    ).show()
                }
            } catch (e: Exception) {
                Log.e(TAG, "registerDevice failed: ${e.javaClass.name}: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    Toast.makeText(
                        context.applicationContext,
                        "register failed: ${e.javaClass.simpleName}: ${e.message}",
                        Toast.LENGTH_SHORT
                    ).show()
                }
            }
        }
    }
}
