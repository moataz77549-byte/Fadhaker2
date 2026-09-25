import com.google.gms.googleservices.GoogleServicesPlugin
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "app.fadhkur"
    compileSdk = 36

    val signingPropertiesFile = rootProject.file("key.properties")
    val signingProperties = Properties().apply {
        if (signingPropertiesFile.exists()) signingPropertiesFile.inputStream().use { load(it) }
    }

    signingConfigs {
        create("release") {
            if (signingPropertiesFile.exists()) {
                storeFile = rootProject.file(signingProperties["storeFile"] as String)
                storePassword = signingProperties["storePassword"] as String
                keyAlias = signingProperties["keyAlias"] as String
                keyPassword = signingProperties["keyPassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "app.fadhkur"
        // Android 8.0+ requirement for the production ARM64 release.
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Restrict bundled plugin JNI libraries as well as Flutter's native output.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            if (signingPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            // Keep these paired. AGP rejects resource shrinking when code
            // shrinking is disabled, and Phase 3 does not change R8 behavior.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}


googleServices {
    // CI and local source checkouts intentionally do not contain the real
    // google-services.json. Production Firebase options are injected outside
    // source control; missing config must not make a debug compile impossible.
    missingGoogleServicesStrategy =
        GoogleServicesPlugin.MissingGoogleServicesStrategy.WARN
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation(platform("com.google.firebase:firebase-bom:34.17.0"))
    implementation("com.google.firebase:firebase-messaging")
}
