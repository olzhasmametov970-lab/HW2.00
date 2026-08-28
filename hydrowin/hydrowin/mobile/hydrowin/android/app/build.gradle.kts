plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ru.hydrowin.hydrowin"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ru.hydrowin.hydrowin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // full = облако; lite = только Bluetooth (отдельный applicationId).
    flavorDimensions += "variant"
    productFlavors {
        create("full") {
            dimension = "variant"
            resValue("string", "app_name", "ГидроВин")
        }
        create("lite") {
            dimension = "variant"
            applicationIdSuffix = ".lite"
            resValue("string", "app_name", "ГидроВин Lite")
        }
    }

    buildTypes {
        release {
            // ВАЖНО: для Google Play настройте release keystore (см. docs/SECURITY.md).
            // Временно debug-подпись — только для локальных release-сборок.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
