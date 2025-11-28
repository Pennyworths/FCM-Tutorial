//
//  ContentView.swift
//  FCMPlayground
//
//  Created by 杨天凡 on 11/27/25.
//

import SwiftUI

// App-level config (initial values, can be overridden in UI)
struct AppConfig {
    static let defaultUserId = ""          // initial value only
    static let defaultApiBaseURL = ""
}

// Generate & persist device_id in UserDefaults
final class DeviceIDProvider {
    private let key = "com.example.fcmplayground.device_id"

    static let shared = DeviceIDProvider()
    private init() {}

    var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}

struct ContentView: View {

    // These are the values the UI shows / edits
    @State private var userId: String = AppConfig.defaultUserId
    @State private var deviceId: String = DeviceIDProvider.shared.deviceId
    @State private var fcmToken: String = ""                  // will be filled by FCM later
    @State private var apiBaseURL: String = AppConfig.defaultApiBaseURL

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {

                Group {
                    Text("User ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("user_id", text: $userId)
                        .textFieldStyle(.roundedBorder)
                }

                Group {
                    Text("Device ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("device_id", text: $deviceId)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)   // generated, not editable
                }

                Group {
                    Text("FCM Token")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("fcm_token", text: $fcmToken)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)   // will be set from Firebase
                }

                Group {
                    Text("API Base URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("API_BASE_URL", text: $apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                }

                Spacer().frame(height: 24)

                Button(action: {
                    registerDevice()
                }) {
                    Text("Re-register device")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("FCM Playground")
        }
    }

    private func registerDevice() {
        // TODO: implement real POST /devices/register here
        // For now just log so we see it works when tapped
        print("Re-register device tapped")
        print("user_id=\(userId)")
        print("device_id=\(deviceId)")
        print("fcm_token=\(fcmToken)")
        print("API_BASE_URL=\(apiBaseURL)")
    }
}

#Preview {
    ContentView()
}




