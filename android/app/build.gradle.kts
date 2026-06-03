import java.util.Properties
import java.io.FileInputStream

plugins {

    id("com.android.application")

    id("com.google.gms.google-services")

    id("kotlin-android")

    id("dev.flutter.flutter-gradle-plugin")

}



val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}



android {

    namespace = "com.marwadiuniversity.smartsociety"

    compileSdk = flutter.compileSdkVersion

    ndkVersion = flutter.ndkVersion



    compileOptions {

// In Kotlin, use assignment (=)

        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17 // Update from 1_8 to 17

        targetCompatibility = JavaVersion.VERSION_17

    }



    kotlinOptions {

        jvmTarget = "17"

    }



    defaultConfig {

        applicationId = "com.marwadiuniversity.smartsociety"

// Use = for assignment in Kotlin

        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode

        versionName = flutter.versionName



        multiDexEnabled = true

    }



    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        getByName("release") {
            // Keep your other settings here (like minifyEnabled if you have them)
            signingConfig = signingConfigs.getByName("release")
        }
    }

}



flutter {

    source = "../.."

}



dependencies {

// In Kotlin, function calls require parentheses and double quotes

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

}