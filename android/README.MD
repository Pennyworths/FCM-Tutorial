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

### Using Android Studio (Recommended)

1. Open the `android/` folder in Android Studio
2. Wait for Gradle sync to complete
3. Connect your phone via USB (enable **USB Debugging** in Developer Options)
4. Select your device in the toolbar
5. Click **Run** (▶️) - app will install and launch on your phone

### Install APK Manually

1. In Android Studio: **Build → Build Bundle(s) / APK(s) → Build APK(s)**
2. Find APK at: `android/app/build/outputs/apk/debug/app-debug.apk`
3. Transfer APK to your phone (USB, email, cloud, etc.)
4. On phone: Open the APK file and tap **Install**
   > You may need to enable "Install from unknown sources"

## How to Use

### On App Launch

1. App automatically fetches FCM token
2. App auto-registers device with backend
3. You will see a **Toast**: `registerDevice: HTTP 200`
4. Screen displays:
   - `user_id`: debug-user-1
   - `device_id`: auto-generated UUID
   - `FCM token`: Firebase token

### Receiving Messages

| Message Type | Display |
|--------------|---------|
| **E2E Test** (`type: e2e_test`) | Toast popup |
| **Normal Message** | System Notification (heads-up popup) |

### E2E Test Flow

When backend sends an E2E test message:
1. App receives FCM push
2. App shows **Toast**: `📩 Title: Body`
3. App automatically calls `/test/ack` to acknowledge

### Normal Message Flow

When backend sends a normal message:
1. App receives FCM push
2. App shows **System Notification** (heads-up popup with sound)
3. Notification appears in notification tray

> 💡 Keep the app **open in foreground** to see Toast messages for E2E tests.

