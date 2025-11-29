//
//  AppDelegate.swift
//  FCMPlayground
//
//  Created by 杨天凡 on 11/28/25.
//

import UIKit
import FirebaseCore   // from Firebase package
import FirebaseMessaging
import UserNotifications


class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        
        // 1. Initialize Firebase
        FirebaseApp.configure()
        
        // We will set Messaging.messaging().delegate and push-related stuff later (Part 3)
        print("✅ Firebase configured")
        
        // 2. Setup notification center delegate
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // 3. Request notification permission
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("❌ Notification auth error: \(error)")
                return
            }
            print("🔔 Notification permission granted: \(granted)")
            
            guard granted else { return }
            
            // 4. Register for APNs on main thread
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        
        // 5. Messaging delegate (for FCM token later)
        Messaging.messaging().delegate = self
        
        return true
    }
    
    // MARK: - APNs registration callbacks

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // This is the APNs token from Apple
        let tokenParts = deviceToken.map { String(format: "%02.2hhx", $0) }
        let tokenString = tokenParts.joined()
        print("📬 APNs device token: \(tokenString)")

        // Pass token to Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error)")
    }

    // MARK: - Firebase Messaging delegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // We will use this in Part 4 to update UI + call /devices/register
        print("🎯 FCM registration token: \(fcmToken ?? "nil")")
    }

    
    // MARK: - UNUserNotificationCenterDelegate (we'll extend in Part 5)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // When app is in foreground, show alert + sound
        return [.banner, .sound]
    }
    
}
