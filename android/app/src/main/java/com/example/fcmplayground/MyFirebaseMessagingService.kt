package com.example.fcmplayground

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
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
        private val ACK_ENDPOINT = ApiRoutes.TEST_ACK
        private const val CONNECT_TIMEOUT_MS = 10_000
        private const val READ_TIMEOUT_MS = 10_000
        
        // Notification
        private const val CHANNEL_ID = "fcm_default_channel"
        private const val CHANNEL_NAME = "FCM Messages"
        private const val NOTIFICATION_ID_MASK = 0x7FFFFFFF
        
        // Data keys
        private const val DATA_KEY_TYPE = "type"
        private const val DATA_KEY_TITLE = "title"
        private const val DATA_KEY_BODY = "body"
        private const val DATA_KEY_NONCE = "nonce"
        
        // Message types
        private const val MSG_TYPE_E2E_TEST = "e2e_test"
        
        // Default values
        private const val DEFAULT_TITLE = "FCM Message"
        private const val DEFAULT_BODY = ""
        
        // Toast format
        private const val TOAST_FORMAT = "📩 %s: %s"
        
        // HTTP
        private const val HTTP_METHOD_POST = "POST"
        private const val HTTP_HEADER_CONTENT_TYPE = "Content-Type"
        private const val HTTP_CONTENT_TYPE_JSON = "application/json"
        private const val HTTP_ERROR_CODE_THRESHOLD = 400
        
        // JSON keys
        private const val JSON_KEY_NONCE = "nonce"
        
        // Log messages
        private const val LOG_NEW_TOKEN = "New token: "
        private const val LOG_E2E_MSG = "e2e_test message with nonce=%s, sending %s"
        private const val LOG_E2E_MISSING_NONCE = "e2e_test message missing nonce"
        private const val LOG_POST_REQUEST = "POST %s body=%s"
        private const val LOG_READ_RESPONSE_ERROR = "Error reading response stream"
        private const val LOG_ACK_RESPONSE = "%s HTTP %d, response=%s"
        private const val LOG_ACK_FAILED = "%s failed"
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "$LOG_NEW_TOKEN$token")

        // Save token for later use in UI and /devices/register
        FcmTokenStore.saveToken(this, token)
        val userId = UserIdManager.getOrCreateUserId(applicationContext)
        val deviceId = DeviceIdManager.getOrCreateDeviceId(this)
        val apiBaseUrl = BuildConfig.API_BASE_URL

        DeviceRegister.registerDevice(
            context = applicationContext,
            userId = userId,
            deviceId = deviceId,
            fcmToken = token,
            apiBaseUrl = apiBaseUrl
        )
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        val notif = remoteMessage.notification
        Log.d(
            TAG,
            "Message received: data=${remoteMessage.data}, " +
                    "title=${notif?.title}, body=${notif?.body}"
        )

        val data = remoteMessage.data
        val type = data[DATA_KEY_TYPE]
        val title = remoteMessage.notification?.title ?: data[DATA_KEY_TITLE] ?: DEFAULT_TITLE
        val body = remoteMessage.notification?.body ?: data[DATA_KEY_BODY] ?: DEFAULT_BODY

        if (type == MSG_TYPE_E2E_TEST) {
            // e2e test message: show Toast and call ack
            showToast(String.format(TOAST_FORMAT, title, body))
            val nonce = data[DATA_KEY_NONCE]
            if (!nonce.isNullOrBlank()) {
                Log.d(TAG, String.format(LOG_E2E_MSG, nonce, ACK_ENDPOINT))
                ackTestMessage(nonce)
            } else {
                Log.w(TAG, LOG_E2E_MISSING_NONCE)
            }
        } else {
            // Normal message: show system notification
            showNotification(title, body)
        }
    }

    /**
     * Show a Toast message on the main thread.
     */
    private fun showToast(message: String) {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(applicationContext, message, Toast.LENGTH_LONG).show()
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
                val url = URL("$apiBaseUrl$ACK_ENDPOINT")

                val jsonBody = JSONObject().apply {
                    put(JSON_KEY_NONCE, nonce)
                }

                Log.d(TAG, String.format(LOG_POST_REQUEST, url, jsonBody))

                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = HTTP_METHOD_POST
                    connectTimeout = CONNECT_TIMEOUT_MS
                    readTimeout = READ_TIMEOUT_MS
                    doOutput = true
                    setRequestProperty(HTTP_HEADER_CONTENT_TYPE, HTTP_CONTENT_TYPE_JSON)
                }

                conn.outputStream.use { os ->
                    os.write(jsonBody.toString().toByteArray(Charsets.UTF_8))
                }

                val code = conn.responseCode
                val responseText = try {
                    if (code >= HTTP_ERROR_CODE_THRESHOLD) {
                        conn.errorStream?.bufferedReader()?.use { it.readText() } ?: DEFAULT_BODY
                    } else {
                        conn.inputStream.bufferedReader().use { it.readText() }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, LOG_READ_RESPONSE_ERROR, e)
                    DEFAULT_BODY
                }
                conn.disconnect()

                Log.d(TAG, String.format(LOG_ACK_RESPONSE, ACK_ENDPOINT, code, responseText))
            } catch (e: Exception) {
                Log.e(TAG, String.format(LOG_ACK_FAILED, ACK_ENDPOINT), e)
            }
        }
    }

    /**
     * Show a system notification for normal messages.
     * Uses HIGH importance/priority to show heads-up notification (popup).
     */
    private fun showNotification(title: String, body: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create channel on Android O+ with HIGH importance for heads-up
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH  // HIGH for heads-up popup
            )
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)  // HIGH priority for heads-up
            .setAutoCancel(true)
            .build()

        // Use positive ID to avoid overwriting and conflicts
        val notificationId = (System.currentTimeMillis() and NOTIFICATION_ID_MASK.toLong()).toInt()
        manager.notify(notificationId, notification)
    }
}
