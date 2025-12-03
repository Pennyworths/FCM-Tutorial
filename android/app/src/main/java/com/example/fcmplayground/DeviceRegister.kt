package com.example.fcmplayground

import android.content.Context
import android.util.Log
import android.widget.Toast
import kotlinx.coroutines.*
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object DeviceRegister {

    private const val CONNECTION_TIMEOUT_MS = 10_000
    private const val READ_TIMEOUT_MS = 10_000
    private const val REGISTER_PATH = "/devices/register"

    fun registerDevice(
        context: Context,
        userId: String,
        deviceId: String,
        fcmToken: String,
        apiBaseUrl: String
    ) {
        if (fcmToken.startsWith("FCM token not")) {
            Toast.makeText(
                context.applicationContext,
                "FCM token not ready yet",
                Toast.LENGTH_SHORT
            ).show()
            return
        }

        val jsonBody = JSONObject().apply {
            put("user_id", userId)
            put("device_id", deviceId)
            put("fcm_token", fcmToken)
            put("platform", "android")
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val url = URL("$apiBaseUrl$REGISTER_PATH")
                Log.d("API", "POST $url body=$jsonBody")

                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = CONNECTION_TIMEOUT_MS
                    readTimeout = READ_TIMEOUT_MS
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
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

                Log.d("API", "registerDevice HTTP $code, response=$responseText")

                withContext(Dispatchers.Main) {
                    Toast.makeText(
                        context.applicationContext,
                        "registerDevice: HTTP $code",
                        Toast.LENGTH_SHORT
                    ).show()
                }
            } catch (e: Exception) {
                Log.e("API", "registerDevice failed: ${e.javaClass.name}: ${e.message}", e)
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