import java.io.FileInputStream
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    id("com.google.gms.google-services")
}

// Load local.properties
val localPropsFile = rootProject.file("local.properties")
val localProps = Properties()
if (localPropsFile.exists()) {
    localProps.load(FileInputStream(localPropsFile))
}

android {
    namespace = "com.example.fcmplayground"
    compileSdk {
        version = release(36)
    }

    defaultConfig {
        applicationId = "com.example.fcmplayground"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        
        // Read API_BASE_URL from local.properties (required, no hardcoded fallback)
        val apiBaseUrl = localProps.getProperty("API_BASE_URL")
        if (apiBaseUrl.isNullOrBlank()) {
            throw GradleException("API_BASE_URL must be set in local.properties")
        }
        buildConfigField("String", "API_BASE_URL", "\"$apiBaseUrl\"")
        
        // Read Cognito configuration from local.properties (optional for Cognito integration)
        val cognitoUserPoolId = localProps.getProperty("COGNITO_USER_POOL_ID", "")
        val cognitoClientId = localProps.getProperty("COGNITO_CLIENT_ID", "")
        val cognitoRegion = localProps.getProperty("COGNITO_REGION", "us-east-1")
        val cognitoDomain = localProps.getProperty("COGNITO_DOMAIN", "")
        
        buildConfigField("String", "COGNITO_USER_POOL_ID", if (cognitoUserPoolId.isNotBlank()) "\"$cognitoUserPoolId\"" else "\"\"")
        buildConfigField("String", "COGNITO_CLIENT_ID", if (cognitoClientId.isNotBlank()) "\"$cognitoClientId\"" else "\"\"")
        buildConfigField("String", "COGNITO_REGION", "\"$cognitoRegion\"")
        buildConfigField("String", "COGNITO_DOMAIN", if (cognitoDomain.isNotBlank()) "\"$cognitoDomain\"" else "\"\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
    implementation(libs.okhttp)
    implementation(libs.gson)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

}
