plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.lain.lain_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lain.lain_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Dos motores, dos APK instalables en paralelo:
    //  - prod: bibliotecas originales (CPU estático) en src/prod/jniLibs.
    //  - experimental: 7 variantes GGML + puente DL en src/experimental/jniLibs
    //    y solo arm64-v8a.
    flavorDimensions += "engine"
    productFlavors {
        create("prod") {
            dimension = "engine"
            // Solo ABIs con las .so compiladas. Sin este filtro, --split-per-abi
            // genera un APK armeabi-v7a sin liblain_llm.so.
            ndk {
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
        create("experimental") {
            dimension = "engine"
            applicationIdSuffix = ".exp"
            versionNameSuffix = "-exp"
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    // Las .so de llama.cpp se extraen al instalar: dart:ffi las abre por nombre.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // Sin GGUF en el APK: los modelos viven en el almacenamiento privado de la
    // app y se importan con ModelManager, así que no hay reglas de compresión
    // de assets grandes.

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// El experimental es exclusivamente arm64-v8a. `--target-platform android-arm64`
// quita las libs de Flutter de otras ABIs, pero dependencias como `jni` siguen
// aportando libdartjni.so para armv7/x86: se excluyen del empaquetado.
androidComponents {
    onVariants(selector().withFlavor("engine" to "experimental")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(
            listOf("lib/armeabi-v7a/**", "lib/x86_64/**"),
        )
    }
}
