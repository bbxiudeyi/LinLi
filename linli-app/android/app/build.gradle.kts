import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// P0-5：正式签名配置从 android/key.properties 读取（不入库）。
// 生成方式见 android/key.properties.example 与整改文档。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "top.bbtech.linli"
    // maplibre_gl 0.26+ 要求 compileSdk 36
    compileSdk = 36
    // 对齐 maplibre_gl 要求的 NDK 版本（向后兼容）
    ndkVersion = "28.1.13356709"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = "21"
    }

    defaultConfig {
        // P0-5：唯一正式包名（基于自有域名 bbtech.top 倒序）。
        // 与旧包 com.example.linli 不兼容：升级需卸载重装（发布前无正式用户，可接受）。
        applicationId = "top.bbtech.linli"
        // maplibre_gl 13.x (android-sdk-opengl) 要求 minSdk 至少 23
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 地图 SDK 方法数较多，启用 multidex 避免 ClassNotFoundException
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["key.alias"] as String
                keyPassword = keystoreProperties["key.password"] as String
                storeFile = file(keystoreProperties["store.file"] as String)
                storePassword = keystoreProperties["store.password"] as String
            }
        }
    }

    buildTypes {
        release {
            // P0-5：不再回退 debug 签名。缺少 key.properties 时产出未签名包
            //（无法安装/上架），必须按 key.properties.example 生成正式密钥。
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
