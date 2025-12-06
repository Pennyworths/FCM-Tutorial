package com.example.fcmplayground

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.core.content.ContextCompat
import com.example.fcmplayground.ui.theme.FcmplaygroundTheme
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    companion object {
        const val TAG = "FCM"
        const val FCM_TOKEN_NOT_AVAILABLE = "FCM token not available yet"
        const val FCM_TOKEN_NOT_PREFIX = "FCM token not"
        
        // Log messages
        const val LOG_PERMISSION_GRANTED = "Notification permission granted"
        const val LOG_PERMISSION_DENIED = "Notification permission denied"
        const val LOG_PERMISSION_ALREADY_GRANTED = "Notification permission already granted"
        const val LOG_TOKEN_FETCH_FAILED = "Fetching FCM registration token failed"
        const val LOG_MANUAL_FETCH_TOKEN = "Manual fetch token: "
    }

    // Permission request launcher for Android 13+
    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted: Boolean ->
        if (isGranted) {
            Log.d(TAG, LOG_PERMISSION_GRANTED)
        } else {
            Log.w(TAG, LOG_PERMISSION_DENIED)
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            when {
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED -> {
                    Log.d(TAG, LOG_PERMISSION_ALREADY_GRANTED)
                }
                else -> {
                    requestPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                }
            }
        }
    }
   
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // Request notification permission for Android 13+
        requestNotificationPermission()

        // Initialize token flow for UI updates
        FcmTokenStore.initFlow(this)

        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                Log.w(TAG, LOG_TOKEN_FETCH_FAILED, task.exception)
                return@addOnCompleteListener
            }

            val token = task.result
            Log.d(TAG, "$LOG_MANUAL_FETCH_TOKEN$token")
            FcmTokenStore.saveToken(this, token)
            
            // Auto-register if user is logged in
            if (CognitoAuth.isLoggedIn(this)) {
                val deviceId = DeviceIdManager.getOrCreateDeviceId(this)
                val apiBaseUrl = BuildConfig.API_BASE_URL
                DeviceRegister.registerDevice(
                    context = this,
                    deviceId = deviceId,
                    fcmToken = token,
                    apiBaseUrl = apiBaseUrl
                )
            }
        }

        setContent {
            FcmplaygroundTheme {
                MainScreen()
            }
        }
    }
}

@Composable
fun MainScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    
    // Authentication state
    var isLoggedIn by remember { mutableStateOf(CognitoAuth.isLoggedIn(context)) }
    var userId by remember { mutableStateOf(CognitoAuth.getUserId(context) ?: "Not logged in") }
    var userEmail by remember { mutableStateOf(CognitoAuth.getUserEmail(context) ?: "") }
    
    // Login state
    var showLoginDialog by remember { mutableStateOf(false) }
    var loginUsername by remember { mutableStateOf("") }
    var loginPassword by remember { mutableStateOf("") }
    var isLoginLoading by remember { mutableStateOf(false) }
    var loginError by remember { mutableStateOf<String?>(null) }
    
    // Register state
    var showRegisterDialog by remember { mutableStateOf(false) }
    var registerUsername by remember { mutableStateOf("") }
    var registerPassword by remember { mutableStateOf("") }
    var registerConfirmPassword by remember { mutableStateOf("") }
    var isRegisterLoading by remember { mutableStateOf(false) }
    var registerError by remember { mutableStateOf<String?>(null) }
    
    val scope = rememberCoroutineScope()
    val deviceId = remember { DeviceIdManager.getOrCreateDeviceId(context) }
    val apiBaseUrl = BuildConfig.API_BASE_URL
    
    // Subscribe to token flow - UI auto-updates when token changes
    val fcmToken by FcmTokenStore.tokenFlow.collectAsState()
    val displayToken = fcmToken ?: MainActivity.FCM_TOKEN_NOT_AVAILABLE
    
    // Handle login
    val handleLogin: () -> Unit = {
        if (loginUsername.isBlank() || loginPassword.isBlank()) {
            loginError = "Please enter username and password"
        } else {
            isLoginLoading = true
            loginError = null
            
            scope.launch {
                try {
                    val result = CognitoAuth.login(context, loginUsername, loginPassword)
                    val loginResult = result.getOrThrow()
                    
                    isLoggedIn = true
                    userId = loginResult.userId
                    userEmail = loginResult.email
                    showLoginDialog = false
                    loginUsername = ""
                    loginPassword = ""
                    
                    // Auto-register device after login
                    fcmToken?.let { token ->
                        DeviceRegister.registerDevice(
                            context = context,
                            deviceId = deviceId,
                            fcmToken = token,
                            apiBaseUrl = apiBaseUrl
                        )
                    }
                    
                    Toast.makeText(context, "Login successful!", Toast.LENGTH_SHORT).show()
                    isLoginLoading = false
                } catch (error: Exception) {
                    Log.e(MainActivity.TAG, "Login error", error)
                    loginError = error.message ?: "Login failed"
                    Toast.makeText(context, "Login failed: ${error.message}", Toast.LENGTH_SHORT).show()
                    isLoginLoading = false
                }
            }
        }
    }
    
    // Handle register
    val handleRegister: () -> Unit = {
        when {
            registerUsername.isBlank() -> {
                registerError = "Please enter username"
            }
            registerPassword.isBlank() -> {
                registerError = "Please enter password"
            }
            registerPassword.length < 8 -> {
                registerError = "Password must be at least 8 characters"
            }
            registerPassword != registerConfirmPassword -> {
                registerError = "Passwords do not match"
            }
            else -> {
                isRegisterLoading = true
                registerError = null
                
                scope.launch {
                    try {
                        val result = CognitoAuth.register(context, registerUsername, registerPassword)
                        val registerResult = result.getOrThrow()
                        
                        // Registration successful - auto login immediately (no email verification needed)
                        val loginResult = CognitoAuth.login(context, registerUsername, registerPassword)
                        val loginData = loginResult.getOrThrow()
                        
                        isLoggedIn = true
                        userId = loginData.userId
                        userEmail = loginData.email ?: ""
                        showRegisterDialog = false
                        registerUsername = ""
                        registerPassword = ""
                        registerConfirmPassword = ""
                        
                        // Auto-register device after registration and login
                        fcmToken?.let { token ->
                            DeviceRegister.registerDevice(
                                context = context,
                                deviceId = deviceId,
                                fcmToken = token,
                                apiBaseUrl = apiBaseUrl
                            )
                        }
                        
                        Toast.makeText(context, "Registration and login successful!", Toast.LENGTH_SHORT).show()
                        isRegisterLoading = false
                    } catch (error: Exception) {
                        Log.e(MainActivity.TAG, "Register error", error)
                        registerError = error.message ?: "Registration failed"
                        Toast.makeText(context, "Registration failed: ${error.message}", Toast.LENGTH_SHORT).show()
                        isRegisterLoading = false
                    }
                }
            }
        }
    }
    
    // Handle logout
    val handleLogout: () -> Unit = {
        CognitoAuth.logout(context)
        isLoggedIn = false
        userId = "Not logged in"
        userEmail = ""
        Toast.makeText(context, "Logged out", Toast.LENGTH_SHORT).show()
    }
    
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        // User info (when logged in)
        if (isLoggedIn) {
            Text("user_id: $userId", style = MaterialTheme.typography.bodyLarge)
            Spacer(Modifier.height(8.dp))
            
            if (userEmail.isNotEmpty()) {
                Text("email: $userEmail", style = MaterialTheme.typography.bodyLarge)
                Spacer(Modifier.height(8.dp))
            }
        } else {
            Text("Please login or register to continue", style = MaterialTheme.typography.bodyLarge)
            Spacer(Modifier.height(8.dp))
        }
        
        Text("device_id: $deviceId", style = MaterialTheme.typography.bodyLarge)
        Spacer(Modifier.height(8.dp))
        
        Text("FCM token: $displayToken", style = MaterialTheme.typography.bodyLarge)
        Spacer(Modifier.height(8.dp))
        
        Text("API_BASE_URL: $apiBaseUrl", style = MaterialTheme.typography.bodyLarge)
        
        Spacer(modifier = Modifier.weight(1f))
        
        // Buttons at the bottom
        if (isLoggedIn) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = {
                        fcmToken?.let { token ->
                            DeviceRegister.registerDevice(
                                context = context,
                                deviceId = deviceId,
                                fcmToken = token,
                                apiBaseUrl = apiBaseUrl
                            )
                        }
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Re-register device")
                }
                
                Button(
                    onClick = handleLogout,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Logout")
                }
            }
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = { showRegisterDialog = true },
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Register")
                }
                
                Button(
                    onClick = { showLoginDialog = true },
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Login")
                }
            }
        }
    }
    
    // Login dialog
    if (showLoginDialog) {
        AlertDialog(
            onDismissRequest = {
                if (!isLoginLoading) {
                    showLoginDialog = false
                    loginError = null
                    loginUsername = ""
                    loginPassword = ""
                }
            },
            title = { Text("Login") },
            text = {
                Column {
                    if (loginError != null) {
                        Text(
                            text = loginError!!,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall
                        )
                        Spacer(Modifier.height(8.dp))
                    }
                    
                    OutlinedTextField(
                        value = loginUsername,
                        onValueChange = { 
                            loginUsername = it
                            loginError = null
                        },
                        label = { Text("Username/Email") },
                        enabled = !isLoginLoading,
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )
                    
                    Spacer(Modifier.height(8.dp))
                    
                    OutlinedTextField(
                        value = loginPassword,
                        onValueChange = { 
                            loginPassword = it
                            loginError = null
                        },
                        label = { Text("Password") },
                        enabled = !isLoginLoading,
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = handleLogin,
                    enabled = !isLoginLoading && loginUsername.isNotBlank() && loginPassword.isNotBlank()
                ) {
                    if (isLoginLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text("Login")
                    }
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showLoginDialog = false
                        loginError = null
                        loginUsername = ""
                        loginPassword = ""
                    },
                    enabled = !isLoginLoading
                ) {
                    Text("Cancel")
                }
            }
        )
    }
    
    // Register dialog
    if (showRegisterDialog) {
        AlertDialog(
            onDismissRequest = {
                if (!isRegisterLoading) {
                    showRegisterDialog = false
                    registerError = null
                    registerUsername = ""
                    registerPassword = ""
                    registerConfirmPassword = ""
                }
            },
            title = { Text("Register") },
            text = {
                Column {
                    if (registerError != null) {
                        Text(
                            text = registerError!!,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall
                        )
                        Spacer(Modifier.height(8.dp))
                    }
                    
                    OutlinedTextField(
                        value = registerUsername,
                        onValueChange = { 
                            registerUsername = it
                            registerError = null
                        },
                        label = { Text("Username") },
                        enabled = !isRegisterLoading,
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )
                    
                    Spacer(Modifier.height(8.dp))
                    
                    OutlinedTextField(
                        value = registerPassword,
                        onValueChange = { 
                            registerPassword = it
                            registerError = null
                        },
                        label = { Text("Password") },
                        enabled = !isRegisterLoading,
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation()
                    )
                    
                    Spacer(Modifier.height(8.dp))
                    
                    OutlinedTextField(
                        value = registerConfirmPassword,
                        onValueChange = { 
                            registerConfirmPassword = it
                            registerError = null
                        },
                        label = { Text("Confirm Password") },
                        enabled = !isRegisterLoading,
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = handleRegister,
                    enabled = !isRegisterLoading && registerUsername.isNotBlank() && 
                             registerPassword.isNotBlank() && registerConfirmPassword.isNotBlank()
                ) {
                    if (isRegisterLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text("Register")
                    }
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showRegisterDialog = false
                        registerError = null
                        registerUsername = ""
                        registerPassword = ""
                        registerConfirmPassword = ""
                    },
                    enabled = !isRegisterLoading
                ) {
                    Text("Cancel")
                }
            }
        )
    }
    
}
