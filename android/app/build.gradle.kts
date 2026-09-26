plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.easyplay.easyplay"
    // file_picker and flutter_plugin_android_lifecycle currently require API 36.
    // compileSdk only controls which APIs can be compiled against; targetSdk and
    // minSdk remain managed by Flutter below.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.easyplay.easyplay"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // KataGo is a native GTP executable packaged as an ABI-specific native
    // library so Android extracts it to nativeLibraryDir, an executable path.
    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += "**/libkatago.so"
            keepDebugSymbols += "**/libkatago-opencl.so"
            keepDebugSymbols += "**/libkatago-opencl-probe.so"
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
