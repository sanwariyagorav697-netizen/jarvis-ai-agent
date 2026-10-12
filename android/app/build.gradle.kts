import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ============================================================================
// Release signing.
//
// android/key.properties git me NAHI jata (android/.gitignore use ignore karta
// hai). CI use GitHub Actions Secrets se banata hai:
//   JARVIS_KEYSTORE_BASE64, JARVIS_KEYSTORE_PASSWORD, JARVIS_KEY_ALIAS, JARVIS_KEY_PASSWORD
//
// Agar key.properties nahi mila to build FAIL nahi hota -- debug key par
// fallback hota hai aur workflow step-summary me clear warning likhi jati hai.
// Dhyan rahe: debug-key wale APK ke upar doosra debug-key APK install NAHI
// hoga (har runner ka debug.keystore alag hota hai), isliye ek baar proper
// keystore setup karna zaroori hai.
// ============================================================================
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.jarvis.assistant"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jarvis.assistant"
        // minSdk/targetSdk Flutter SDK se aate hain (template jaisa) -- manual
        // number yahan likhne se Flutter upgrade par drift hota hai.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("jarvis") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) {
                    signingConfigs.getByName("jarvis")
                } else {
                    signingConfigs.getByName("debug")
                }
            // R8/shrink abhi OFF: plugins me reflection hota hai, rules likhe
            // bina enable karna runtime crash ka risk hai. (README me note hai.)
            isMinifyEnabled = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
