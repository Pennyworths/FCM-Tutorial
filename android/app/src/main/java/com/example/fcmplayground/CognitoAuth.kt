package com.example.fcmplayground

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.core.content.edit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

object CognitoAuth {
    private const val TAG = "CognitoAuth"
    private const val PREFS_NAME = "cognito_auth_prefs"
    private const val KEY_ID_TOKEN = "id_token"
    private const val KEY_ACCESS_TOKEN = "access_token"
    private const val KEY_REFRESH_TOKEN = "refresh_token"
    private const val KEY_USER_ID = "user_id"
    private const val KEY_USER_EMAIL = "user_email"
    
    private const val CONNECTION_TIMEOUT_MS = 10_000
    private const val READ_TIMEOUT_MS = 10_000
    private const val HTTP_METHOD_POST = "POST"
    private const val HTTP_HEADER_CONTENT_TYPE = "Content-Type"
    private const val HTTP_CONTENT_TYPE_JSON = "application/x-amz-json-1.1" // AWS Cognito requires this specific Content-Type (not application/json)
    private const val HTTP_HEADER_X_AMZ_TARGET = "X-Amz-Target"
    private const val HTTP_HEADER_X_AMZ_TARGET_VALUE = "AWSCognitoIdentityProviderService.InitiateAuth"
    
    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
    
    /**
     * Get the current ID token, or null if not logged in
     */
    fun getIdToken(context: Context): String? {
        return getPrefs(context).getString(KEY_ID_TOKEN, null)
    }
    
    /**
     * Get the current user ID from stored token, or null if not logged in
     */
    fun getUserId(context: Context): String? {
        val idToken = getIdToken(context) ?: return null
        return JwtUtils.getSubject(idToken)
    }
    
    /**
     * Get the current user email from stored token, or null if not logged in
     */
    fun getUserEmail(context: Context): String? {
        val idToken = getIdToken(context) ?: return null
        return JwtUtils.getEmail(idToken)
    }
    
    /**
     * Check if user is currently logged in
     */
    fun isLoggedIn(context: Context): Boolean {
        return getIdToken(context) != null
    }
    
    /**
     * Login with username and password
     */
    suspend fun login(
        context: Context,
        username: String,
        password: String
    ): Result<LoginResult> = withContext(Dispatchers.IO) {
        try {
            // Get configuration from CognitoConfig
            val userPoolId = CognitoConfig.USER_POOL_ID
            val clientId = CognitoConfig.CLIENT_ID
            val region = CognitoConfig.REGION
            
            if (userPoolId.isBlank() || clientId.isBlank()) {
                return@withContext Result.failure(
                    IllegalStateException("Cognito not configured. Check local.properties")
                )
            }
            
            // Cognito endpoint: https://cognito-idp.{region}.amazonaws.com/
            val endpoint = "https://cognito-idp.$region.amazonaws.com/"
            
            val requestBody = JSONObject().apply {
                put("AuthFlow", "USER_PASSWORD_AUTH")
                put("ClientId", clientId)
                put("AuthParameters", JSONObject().apply {
                    put("USERNAME", username)
                    put("PASSWORD", password)
                })
            }
            
            Log.d(TAG, "Attempting login for user: $username")
            
            val url = URL(endpoint)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = HTTP_METHOD_POST
                connectTimeout = CONNECTION_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                doOutput = true
                setRequestProperty(HTTP_HEADER_CONTENT_TYPE, HTTP_CONTENT_TYPE_JSON)
                setRequestProperty(HTTP_HEADER_X_AMZ_TARGET, HTTP_HEADER_X_AMZ_TARGET_VALUE)
            }
            
            conn.outputStream.use { os ->
                os.write(requestBody.toString().toByteArray(StandardCharsets.UTF_8))
            }
            
            val code = conn.responseCode
            val responseText = try {
                if (code >= 400) {
                    conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                } else {
                    conn.inputStream.bufferedReader().use { it.readText() }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error reading response", e)
                ""
            }
            conn.disconnect()
            
            // Log full response for debugging (first 500 chars to avoid log spam)
            val responsePreview = if (responseText.length > 500) {
                responseText.substring(0, 500) + "..."
            } else {
                responseText
            }
            Log.d(TAG, "Cognito response (code=$code): $responsePreview")
            
            if (code != 200) {
                val errorMessage = try {
                    val errorJson = JSONObject(responseText)
                    errorJson.optString("__type", "Unknown error") + ": " +
                            errorJson.optString("message", responseText)
                } catch (_: Exception) {
                    "HTTP $code: $responseText"
                }
                Log.e(TAG, "Login failed: $errorMessage")
                return@withContext Result.failure(Exception(errorMessage))
            }
            
            // Parse response
            val responseJson = JSONObject(responseText)
            
            // Check if this is a challenge response (requires additional steps)
            if (responseJson.has("ChallengeName")) {
                val challengeName = responseJson.optString("ChallengeName", "Unknown")
                val challengeMessage = when (challengeName) {
                    "NEW_PASSWORD_REQUIRED" -> "This user requires a new password. Please use admin-set-user-password to set a permanent password first."
                    "SOFTWARE_TOKEN_MFA" -> "Multi-factor authentication required"
                    "SMS_MFA" -> "SMS verification code required"
                    else -> "Additional authentication step required: $challengeName"
                }
                Log.e(TAG, "Login challenge: $challengeName - $challengeMessage")
                Log.e(TAG, "Full challenge response: $responseText")
                return@withContext Result.failure(Exception("Login requires additional step: $challengeMessage"))
            }
            
            // Check if AuthenticationResult exists
            if (!responseJson.has("AuthenticationResult")) {
                Log.e(TAG, "Unexpected response format. Full response: $responseText")
                return@withContext Result.failure(
                    Exception("Unexpected login response format. Response: $responsePreview")
                )
            }
            
            val authenticationResult = responseJson.getJSONObject("AuthenticationResult")
            
            val idToken = authenticationResult.getString("IdToken")
            val accessToken = authenticationResult.getString("AccessToken")
            val refreshToken = authenticationResult.optString("RefreshToken", "")
            
            // Parse user info from ID token
            val userId = JwtUtils.getSubject(idToken) ?: ""
            val email = JwtUtils.getEmail(idToken) ?: ""
            
            // Save tokens
            getPrefs(context).edit {
                putString(KEY_ID_TOKEN, idToken)
                putString(KEY_ACCESS_TOKEN, accessToken)
                if (refreshToken.isNotEmpty()) {
                    putString(KEY_REFRESH_TOKEN, refreshToken)
                }
                putString(KEY_USER_ID, userId)
                putString(KEY_USER_EMAIL, email)
            }
            
            Log.d(TAG, "Login successful for user: $userId")
            
            Result.success(
                LoginResult(
                    userId = userId,
                    email = email,
                    idToken = idToken
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "Login exception", e)
            Result.failure(e)
        }
    }
    
    /**
     * Register a new user with username and password
     */
    suspend fun register(
        context: Context,
        username: String,
        password: String
    ): Result<RegisterResult> = withContext(Dispatchers.IO) {
        try {
            val clientId = CognitoConfig.CLIENT_ID
            val region = CognitoConfig.REGION
            
            if (clientId.isBlank()) {
                return@withContext Result.failure(
                    IllegalStateException("Cognito not configured. Check local.properties")
                )
            }
            
            val endpoint = "https://cognito-idp.$region.amazonaws.com/"
            
            val requestBody = JSONObject().apply {
                put("ClientId", clientId)
                put("Username", username)
                put("Password", password)
                // No UserAttributes needed - using username only (no email required)
            }
            
            Log.d(TAG, "Attempting registration for username: $username")
            
            val url = URL(endpoint)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = HTTP_METHOD_POST
                connectTimeout = CONNECTION_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                doOutput = true
                setRequestProperty(HTTP_HEADER_CONTENT_TYPE, HTTP_CONTENT_TYPE_JSON)
                setRequestProperty(HTTP_HEADER_X_AMZ_TARGET, "AWSCognitoIdentityProviderService.SignUp")
            }
            
            conn.outputStream.use { os ->
                os.write(requestBody.toString().toByteArray(StandardCharsets.UTF_8))
            }
            
            val code = conn.responseCode
            val responseText = try {
                if (code >= 400) {
                    conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                } else {
                    conn.inputStream.bufferedReader().use { it.readText() }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error reading response", e)
                ""
            }
            conn.disconnect()
            
            if (code != 200) {
                val errorMessage = try {
                    val errorJson = JSONObject(responseText)
                    errorJson.optString("__type", "Unknown error") + ": " +
                            errorJson.optString("message", responseText)
                } catch (_: Exception) {
                    "HTTP $code: $responseText"
                }
                Log.e(TAG, "Registration failed: $errorMessage")
                return@withContext Result.failure(Exception(errorMessage))
            }
            
            // Parse response
            val responseJson = JSONObject(responseText)
            val userSub = responseJson.optString("UserSub", "")
            
            Log.d(TAG, "Registration successful for user: $userSub")
            
            Result.success(
                RegisterResult(
                    userSub = userSub,
                    username = username
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "Registration exception", e)
            Result.failure(e)
        }
    }
    
    /**
     * Confirm user registration with verification code
     */
    suspend fun confirmRegistration(
        context: Context,
        email: String,
        confirmationCode: String
    ): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val clientId = CognitoConfig.CLIENT_ID
            val region = CognitoConfig.REGION
            
            if (clientId.isBlank()) {
                return@withContext Result.failure(
                    IllegalStateException("Cognito not configured. Check local.properties")
                )
            }
            
            val endpoint = "https://cognito-idp.$region.amazonaws.com/"
            
            val requestBody = JSONObject().apply {
                put("ClientId", clientId)
                put("Username", email)
                put("ConfirmationCode", confirmationCode)
            }
            
            Log.d(TAG, "Attempting to confirm registration for: $email")
            
            val url = URL(endpoint)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = HTTP_METHOD_POST
                connectTimeout = CONNECTION_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                doOutput = true
                setRequestProperty(HTTP_HEADER_CONTENT_TYPE, HTTP_CONTENT_TYPE_JSON)
                setRequestProperty(HTTP_HEADER_X_AMZ_TARGET, "AWSCognitoIdentityProviderService.ConfirmSignUp")
            }
            
            conn.outputStream.use { os ->
                os.write(requestBody.toString().toByteArray(StandardCharsets.UTF_8))
            }
            
            val code = conn.responseCode
            val responseText = try {
                if (code >= 400) {
                    conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                } else {
                    conn.inputStream.bufferedReader().use { it.readText() }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error reading response", e)
                ""
            }
            conn.disconnect()
            
            if (code != 200) {
                val errorMessage = try {
                    val errorJson = JSONObject(responseText)
                    errorJson.optString("__type", "Unknown error") + ": " +
                            errorJson.optString("message", responseText)
                } catch (_: Exception) {
                    "HTTP $code: $responseText"
                }
                Log.e(TAG, "Confirmation failed: $errorMessage")
                return@withContext Result.failure(Exception(errorMessage))
            }
            
            Log.d(TAG, "Registration confirmed successfully")
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Confirmation exception", e)
            Result.failure(e)
        }
    }
    
    /**
     * Logout and clear stored tokens
     */
    fun logout(context: Context) {
        getPrefs(context).edit {
            clear()
        }
        Log.d(TAG, "Logged out")
    }
    
    data class LoginResult(
        val userId: String,
        val email: String,
        val idToken: String
    )
    
    data class RegisterResult(
        val userSub: String,
        val username: String
    )
}

