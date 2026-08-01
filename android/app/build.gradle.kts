import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val knzApplicationId = "com.knzscent.admin"
val firebaseConfigFile = file("google-services.json")
val hasMatchingFirebaseConfig =
    firebaseConfigFile.exists() &&
        firebaseConfigFile.readText().contains("\"package_name\": \"$knzApplicationId\"")

// A Firebase app must be registered for the final application ID. This keeps
// credential-free CI builds working while applying the production plugins as
// soon as a matching google-services.json is supplied.
if (hasMatchingFirebaseConfig) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
} else {
    logger.warn(
        "Firebase plugins were not applied: android/app/google-services.json " +
            "must contain package_name '$knzApplicationId'.",
    )
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? =
    (keystoreProperties.getProperty(propertyName) ?: System.getenv(environmentName))
        ?.trim()
        ?.takeIf { it.isNotEmpty() }

val releaseStoreFilePath = releaseSigningValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = releaseSigningValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseStoreFile = releaseStoreFilePath?.let { rootProject.file(it) }
val releaseSigningReady =
    releaseStoreFile?.isFile == true &&
        releaseStorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null
val releaseTaskRequested =
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

if (releaseTaskRequested && !releaseSigningReady) {
    throw GradleException(
        "Release signing is not configured. Provide android/key.properties or " +
            "ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, " +
            "and ANDROID_KEY_PASSWORD.",
    )
}

android {
    namespace = "com.knzscent.admin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.knzscent.admin"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningReady) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
