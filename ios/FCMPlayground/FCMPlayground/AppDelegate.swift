//
//  AppDelegate.swift
//  FCMPlayground
//
//  Created by 杨天凡 on 11/28/25.
//

import UIKit
import FirebaseCore   // from Firebase package
import FirebaseMessaging

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        // Initialize Firebase
        FirebaseApp.configure()

        // We will set Messaging.messaging().delegate and push-related stuff later (Part 3)
        print("✅ Firebase configured")

        return true
    }
}
