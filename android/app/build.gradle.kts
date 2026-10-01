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

// Android Studio invokes Gradle directly, bypassing package_lan_android.py.
// Verify the pinned executable on every build; the helper downloads it only
// when missing or invalid. Web artifacts are handled by prepareLanWeb below.
val prepareStockfish = tasks.register<Exec>("prepareStockfish") {
    group = "build"
    description = "Prepare and verify the pinned Stockfish Android executable"
    workingDir(rootProject.projectDir.parentFile)
    val defaultPython = if (System.getProperty("os.name").startsWith("Windows")) "python" else "python3"
    commandLine(
        providers.gradleProperty("stockfishPython").getOrElse(defaultPython),
        "tools/prepare_stockfish.py", "--android-only",
    )
}

tasks.matching {
    it.name == "preBuild" || (it.name.startsWith("merge") &&
        (it.name.endsWith("NativeLibs") || it.name.endsWith("JniLibFolders")))
}.configureEach {
    dependsOn(prepareStockfish)
}

// Generate assets for rootBundle directly, so every Android entry point packs
// the LAN client without adding a recursive Web bundle to pubspec.yaml.
val localProperties = Properties().apply {
    rootProject.file("local.properties").inputStream().use { load(it) }
}
val flutterSdk = localProperties.getProperty("flutter.sdk")
    ?: throw GradleException("flutter.sdk is missing from android/local.properties")
val lanWebAssets = layout.buildDirectory.dir("generated/lanWebAssets")
val prepareLanWeb = tasks.register<Exec>("prepareLanWeb") {
    group = "build"
    description = "Build and bundle the LAN Web client"
    val repository = rootProject.projectDir.parentFile
    workingDir(repository)
    val windows = System.getProperty("os.name").startsWith("Windows")
    commandLine(
        providers.gradleProperty("lanWebPython").getOrElse(if (windows) "python" else "python3"),
        "tools/prepare_lan_web.py",
        "--flutter", "$flutterSdk/bin/${if (windows) "flutter.bat" else "flutter"}",
        "--output", lanWebAssets.get().asFile.absolutePath,
    )
    inputs.files(repository.resolve("pubspec.yaml"), repository.resolve("pubspec.lock"))
    inputs.files(repository.resolve(".dart_tool/package_config.json"))
    inputs.dir(repository.resolve("lib"))
    inputs.dir(repository.resolve("web"))
    inputs.dir(repository.resolve("assets"))
    inputs.files(
        repository.resolve("tools/prepare_lan_web.py"),
        repository.resolve("tools/package_lan_android.py"),
        repository.resolve("tools/prepare_stockfish.py"),
    )
    inputs.property("flutterSdk", flutterSdk)
    inputs.file("$flutterSdk/bin/cache/flutter_tools.stamp")
    outputs.dir(lanWebAssets)
    // Serialize against Flutter's native build before generating Web output.
    mustRunAfter(tasks.matching { it.name.startsWith("compileFlutterBuild") })
}

tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach {
    dependsOn(prepareLanWeb)
}

android {
    namespace = "com.easyplay.easyplay"
    // file_picker and flutter_plugin_android_lifecycle currently require API 36.
    // compileSdk only controls which APIs can be compiled against; targetSdk and
    // minSdk remain managed by Flutter below.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    sourceSets.getByName("main").assets.srcDir(lanWebAssets.get().asFile)

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
            keepDebugSymbols += "**/libstockfish.so"
            keepDebugSymbols += "**/libkatago.so"
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
