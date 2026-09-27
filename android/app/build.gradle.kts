import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releasePropertiesFile = rootProject.file("key.properties")
val releaseProperties = Properties()
if (releasePropertiesFile.exists()) {
    FileInputStream(releasePropertiesFile).use { releaseProperties.load(it) }
}
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (releaseRequested && listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .any { releaseProperties.getProperty(it).isNullOrBlank() }) {
    throw GradleException("Release signing requires android/key.properties with storeFile, storePassword, keyAlias and keyPassword")
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

    signingConfigs {
        create("release") {
            if (releasePropertiesFile.exists()) {
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
                storeFile = releaseProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = releaseProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
