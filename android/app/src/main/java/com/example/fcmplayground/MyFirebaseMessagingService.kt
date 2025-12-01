package com.example.fcmplayground

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class MyFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "FCM"
        private const val CHANNEL_ID = "fcm_default_channel"
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "New token: $token")

        // Save token for later use in UI and /devices/register
        FcmTokenStore.saveToken(this, token)
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        Log.d(TAG, "Message received: data=${remoteMessage.data}, notification=${remoteMessage.notification}")

        val data = remoteMessage.data
        val type = data["type"]

        if (type == "e2e_test") {
            // e2e test message: we expect a nonce in data.nonce
            val nonce = data["nonce"]
            if (!nonce.isNullOrBlank()) {
                Log.d(TAG, "e2e_test message with nonce=$nonce, sending /test/ack")
                ackTestMessage(nonce)
            } else {
                Log.w(TAG, "e2e_test message missing nonce")
            }
        } else {
            // Normal notification: show it
            val title = remoteMessage.notification?.title ?: data["title"] ?: "FCM Message"
            val body = remoteMessage.notification?.body ?: data["body"] ?: data.toString()
            showNotification(title, body)
        }
    }

    /**
     * Call POST /test/ack with { "nonce": "<nonce>" }.
     */
    private fun ackTestMessage(nonce: String) {
        // Fire-and-forget background call
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val apiBaseUrl = BuildConfig.API_BASE_URL
                val url = URL("$apiBaseUrl/test/ack")

                val jsonBody = JSONObject().apply {
                    put("nonce", nonce)
                }

                Log.d(TAG, "POST $url body=$jsonBody")

                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 10_000
                    readTimeout = 10_000
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

                Log.d(TAG, "test/ack HTTP $code, response=$responseText")
            } catch (e: Exception) {
                Log.e(TAG, "test/ack failed", e)
            }
        }
    }

    /**
     * Show a normal notification for non-e2e messages.
     */
    private fun showNotification(title: String, body: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create channel on Android O+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FCM Messages",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .build()

        // Use incremental ID to avoid overwriting
        val notificationId = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        manager.notify(notificationId, notification)
    }
}


