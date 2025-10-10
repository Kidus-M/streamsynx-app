pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // ✅ Upgraded Android Gradle Plugin
    id("com.android.application") version "8.9.1" apply false

    // ✅ Keep your Firebase Google Services plugin up-to-date (4.4.2 is latest)
    id("com.google.gms.google-services") version "4.4.2" apply false

    // ✅ Kotlin plugin (1.9.23 stable for AGP 8.9.x)
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
