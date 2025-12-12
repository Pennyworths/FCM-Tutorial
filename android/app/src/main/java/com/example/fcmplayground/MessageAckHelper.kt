package com.example.fcmplayground

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object MessageAckHelper {
    private const val TAG = "FCM"
    private const val CONNECT_TIMEOUT_MS = 10_000
    private const val READ_TIMEOUT_MS = 10_000
    private const val HTTP_METHOD_POST = "POST"
    private const val HTTP_HEADER_CONTENT_TYPE = "Content-Type"
    private const val HTTP_CONTENT_TYPE_JSON = "application/json"
    private const val HTTP_ERROR_CODE_THRESHOLD = 400
    private const val JSON_KEY_NONCE = "nonce"
    private const val DEFAULT_BODY = ""
    private const val LOG_POST_REQUEST = "POST %s body=%s"
    private const val LOG_READ_RESPONSE_ERROR = "Error reading response stream"
    private const val LOG_ACK_RESPONSE = "%s HTTP %d, response=%s"
    private const val LOG_ACK_FAILED = "%s failed"

    /**
     * Send ACK for a message with nonce.
     * @param nonce The nonce to acknowledge
     * @param endpoint The endpoint to call (either ApiRoutes.TEST_ACK or ApiRoutes.MESSAGES_ACK)
     * @param apiBaseUrl The API base URL
     */
    fun sendAck(nonce: String, endpoint: String, apiBaseUrl: String) {
        // Fire-and-forget background call
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val url = URL("$apiBaseUrl$endpoint")

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

                Log.d(TAG, String.format(LOG_ACK_RESPONSE, endpoint, code, responseText))
            } catch (e: Exception) {
                Log.e(TAG, String.format(LOG_ACK_FAILED, endpoint), e)
            }
        }
    }
}

