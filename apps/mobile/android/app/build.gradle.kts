buildscript {
    if (file("google-services.json").isFile) {
        repositories { google(); mavenCentral() }
        dependencies { classpath("com.google.gms:google-services:4.6.0") }
    }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").isFile) {
    apply(plugin = "com.google.gms.google-services")
}

val signingVariables = listOf("SOBATNIRA_ANDROID_KEYSTORE", "SOBATNIRA_ANDROID_STORE_PASSWORD",
    "SOBATNIRA_ANDROID_KEY_ALIAS", "SOBATNIRA_ANDROID_KEY_PASSWORD")
val teamSigning = signingVariables.associateWith { providers.environmentVariable(it).orNull }
val signingRequired = providers.environmentVariable("SOBATNIRA_ANDROID_SIGNING_REQUIRED").orNull == "true"
val signWithTeam = signingRequired || teamSigning.values.any { !it.isNullOrBlank() }
if (signWithTeam) {
    val missing = signingVariables.filter { teamSigning[it].isNullOrBlank() }
    require(missing.isEmpty()) { "Lengkapi konfigurasi signing Android: ${missing.joinToString()}" }
    require(file(teamSigning.getValue("SOBATNIRA_ANDROID_KEYSTORE")!!).isFile) { "Keystore Android tidak ditemukan." }
}

android {
    namespace = "com.sobatnira.sobatnira"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sobatnira.sobatnira"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signWithTeam) {
            create("teamRelease") {
                storeFile = file(teamSigning.getValue("SOBATNIRA_ANDROID_KEYSTORE")!!)
                storePassword = teamSigning.getValue("SOBATNIRA_ANDROID_STORE_PASSWORD")
                keyAlias = teamSigning.getValue("SOBATNIRA_ANDROID_KEY_ALIAS")
                keyPassword = teamSigning.getValue("SOBATNIRA_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (signWithTeam) "teamRelease" else "debug")
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
