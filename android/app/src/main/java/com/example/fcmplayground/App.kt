package com.example.fcmplayground

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.ktx.Firebase

class App : Application() {

    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)
        
        // Initialize Firebase Analytics - required for FCM delivery reporting
        val analytics = Firebase.analytics
        Log.d("App", "Firebase initialized with Analytics")
    }
}
