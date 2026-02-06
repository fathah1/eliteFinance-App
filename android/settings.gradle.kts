pluginManagement {
    val properties = java.util.Properties()
    val localPropertiesFile = file("local.properties")
    check(localPropertiesFile.exists()) { "local.properties not found" }
    localPropertiesFile.inputStream().use { properties.load(it) }

    val flutterSdkPath = properties.getProperty("flutter.sdk")
        ?: error("flutter.sdk not set in local.properties")

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.3.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}

include(":app")
