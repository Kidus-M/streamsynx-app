plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.streamsynx"

    // ✅ Updated to latest SDK level required by plugins
    compileSdk = 36
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Unchanged on purpose: the applicationId is the app's identity on a
        // device, so altering it would make this a different app that existing
        // users could not update to.
        applicationId = "com.example.streamsynx"
        minSdk = flutter.minSdkVersion
        targetSdk = 36

        // Driven by the `version:` line in pubspec.yaml, so a release only has to
        // be bumped in one place and Android sees the increment it needs to
        // treat the build as an update.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
