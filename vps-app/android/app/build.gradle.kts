import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.myth.publicnode"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    // compilerOptions {
    //     jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    // }

    defaultConfig {
        applicationId = "com.myth.publicnode"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            val keystoreProperties = Properties()
            
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
            }

            val storeFilePath = keystoreProperties.getProperty("storeFile") ?: System.getenv("KEYSTORE_PATH")
            val storePasswordStr = keystoreProperties.getProperty("storePassword") ?: System.getenv("KEYSTORE_PASSWORD")
            val keyAliasStr = keystoreProperties.getProperty("keyAlias") ?: System.getenv("KEY_ALIAS")
            val keyPasswordStr = keystoreProperties.getProperty("keyPassword") ?: System.getenv("KEY_PASSWORD")

            if (storeFilePath != null && storePasswordStr != null && keyAliasStr != null && keyPasswordStr != null) {
                storeFile = file(storeFilePath)
                storePassword = storePasswordStr
                keyAlias = keyAliasStr
                keyPassword = keyPasswordStr
            } else {
                // Fallback to debug for local development, but print a warning
                println("WARNING: key.properties or signing environment variables missing. Building with DEBUG keys.")
                storeFile = file(System.getProperty("user.home") + "/.android/debug.keystore")
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

tasks.register<Exec>("syncPublicNodeAssets") {
    workingDir = file("../../..")
    commandLine = listOf("make", "sync")
}

project.afterEvaluate {
    tasks.named("preBuild") {
        dependsOn("syncPublicNodeAssets")
    }
}
