import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The keystore and its passwords live in android/key.properties,
// which is gitignored (as are *.jks / *.keystore) and must never be committed.
// Without key.properties a release build FAILS (see the check at the end of
// this file); it never falls back to the debug key. A debug-signed APK on
// Dad's phone could not be updated by a properly signed one without an
// uninstall, which would also lose his lock pattern. Debug builds are unaffected.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    // Package name / application id: see DECISIONS.md (D10). It is bound to the
    // Android OAuth client in Google Cloud, so don't change it casually.
    namespace = "com.ventrafin.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on older Android versions.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.ventrafin.app"
        // local_auth and flutter_secure_storage need API 24 (Android 7.0) or newer.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // AppCompat themes for the launch/normal window themes (required by local_auth).
    implementation("androidx.appcompat:appcompat:1.7.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

// Refuse to build a release without the release keystore (never sign it with the debug key).
gradle.taskGraph.whenReady {
    val releaseTask = allTasks.any { it.project == project && it.name.contains("Release") }
    if (releaseTask && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "Release builds need android/key.properties (the release keystore). " +
                "It is missing, so the build stops instead of signing with the debug key."
        )
    }
}
