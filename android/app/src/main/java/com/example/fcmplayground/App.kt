package com.example.fcmplayground

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp

class App : Application() {

    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)
        Log.d("App", "Firebase initialized")
    }
}
