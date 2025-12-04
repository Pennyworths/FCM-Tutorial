# Android App

FCM Playground - Android app for testing Firebase Cloud Messaging.

## Setup

### 1. Firebase Configuration

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (or create one)
3. Click **Add app** → **Android**
4. Enter package name: `com.example.fcmplayground`
5. Download `google-services.json`
6. Place it in `android/app/google-services.json`

### 2. Configure API URL

Edit `android/local.properties`:

```properties
sdk.dir=C\:\\Users\\<username>\\AppData\\Local\\Android\\Sdk
API_BASE_URL=https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/dev
```

> ⚠️ Get `API_BASE_URL` from `make output` in `infra/` after deployment.

## Run the App

### Using Android Studio

1. Open the `android/` folder in Android Studio
2. Wait for Gradle sync to complete
3. Connect a device or start an emulator
4. Click **Run** (▶️)

### Using Command Line

```bash
cd android

# Build debug APK
./gradlew assembleDebug

# Install on connected device
./gradlew installDebug
```

## Features

- Receives FCM push notifications
- Displays device info (user_id, device_id, FCM token)
- Auto-registers device with backend on startup
- Manual re-register button

