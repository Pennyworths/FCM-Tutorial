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
        private const val LOG_MSG_ACK = "Regular message with nonce=%s, sending %s"
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
        val nonce = data[DATA_KEY_NONCE]

        if (type == MSG_TYPE_E2E_TEST) {
            // e2e test message: show Toast and call /test/ack
            showToast(String.format(TOAST_FORMAT, title, body))
            if (!nonce.isNullOrBlank()) {
                Log.d(TAG, String.format(LOG_E2E_MSG, nonce, ApiRoutes.TEST_ACK))
                ackMessage(nonce, ApiRoutes.TEST_ACK)
            } else {
                Log.w(TAG, LOG_E2E_MISSING_NONCE)
            }
        } else {
            // Normal message: show system notification
            // Pass nonce to notification so it can be sent ACK when user clicks
            showNotification(title, body, nonce)
            
            // If app is in foreground, send ACK immediately
            // If app is in background, ACK will be sent when user clicks notification (in MainActivity)
            if (!nonce.isNullOrBlank()) {
                Log.d(TAG, String.format(LOG_MSG_ACK, nonce, ApiRoutes.MESSAGES_ACK))
                ackMessage(nonce, ApiRoutes.MESSAGES_ACK)
            } else {
                Log.w(TAG, "Regular message received without nonce. This is unexpected. Data keys: ${data.keys}")
            }
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
     * Call POST /test/ack or POST /messages/ack with { "nonce": "<nonce>" }.
     * @param nonce The nonce to acknowledge
     * @param endpoint The endpoint to call (either ApiRoutes.TEST_ACK or ApiRoutes.MESSAGES_ACK)
     */
    private fun ackMessage(nonce: String, endpoint: String) {
        val apiBaseUrl = BuildConfig.API_BASE_URL
        MessageAckHelper.sendAck(nonce, endpoint, apiBaseUrl)
    }

    /**
     * Show a system notification for normal messages.
     * Uses HIGH importance/priority to show heads-up notification (popup).
     * @param title Notification title
     * @param body Notification body
     * @param nonce Optional nonce to include in notification click Intent (for ACK tracking)
     */
    private fun showNotification(title: String, body: String, nonce: String? = null) {
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

        // Create Intent for notification click - will open MainActivity
        // FCM automatically includes data fields in Intent extras when app is in background
        // But we also add nonce explicitly for when app is in foreground
        val intent = android.content.Intent(this, MainActivity::class.java).apply {
            flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TASK
            // Add nonce to Intent so MainActivity can extract it and send ACK
            if (!nonce.isNullOrBlank()) {
                putExtra("nonce", nonce)
            }
        }

        val pendingIntent = android.app.PendingIntent.getActivity(
            this,
            0,
            intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)  // HIGH priority for heads-up
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)  // Set click action
            .build()

        // Use positive ID to avoid overwriting and conflicts
        val notificationId = (System.currentTimeMillis() and NOTIFICATION_ID_MASK.toLong()).toInt()
        manager.notify(notificationId, notification)
    }
}
