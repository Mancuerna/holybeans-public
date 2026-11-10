plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// patrol_cli 4.7+ passes this property to its Android Gradle invocations.
// Keep Patrol data in a separate app sandbox without changing regular builds.
val isPatrolBuild = providers.gradleProperty("patrol-enabled").orNull == "true"
val holyBeansApplicationId = "com.caffeinateddev.holybeans"

val releaseSigning = listOf(
    "HOLYBEANS_KEYSTORE",
    "HOLYBEANS_KEYSTORE_PASSWORD",
    "HOLYBEANS_KEY_ALIAS",
    "HOLYBEANS_KEY_PASSWORD",
).associateWith { providers.environmentVariable(it).orNull?.takeIf(String::isNotBlank) }
val missingSigning = releaseSigning.filterValues { it == null }.keys
val allowDebugSigning = providers.gradleProperty("allowDebugSigning").orNull == "true"

// Inspect resolved tasks so abbreviations and aggregate tasks cannot bypass this.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release") } &&
        missingSigning.isNotEmpty() && !allowDebugSigning) {
        throw GradleException(
            "Release signing requires ${missingSigning.joinToString()}. " +
                "For local testing only, explicitly set -PallowDebugSigning=true.",
        )
    }
}

android {
    namespace = "com.caffeinateddev.holybeans"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    androidResources {
        // Keep local dependency-cache paths out of the bundle's resource table.
        additionalParameters += "--exclude-sources"
    }

    compileOptions {
        // flutter_local_notifications needs java.time on older Android.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (isPatrolBuild) "$holyBeansApplicationId.patrol" else holyBeansApplicationId
        manifestPlaceholders["holyBeansLabel"] = "HolyBeans"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Keep Android 7 support independent of Flutter's default minimum.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        if (isPatrolBuild) {
            testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"
            testInstrumentationRunnerArguments["clearPackageData"] = "true"
        }
    }

    if (isPatrolBuild) {
        testOptions {
            execution = "ANDROIDX_TEST_ORCHESTRATOR"
        }
        // `patrol test --profile` needs the instrumented tests built in that
        // mode too, for timings of compiled code. Set this to "profile".
        System.getenv("HOLYBEANS_PATROL_BUILD_TYPE")?.let { testBuildType = it }
    }

    // Complete upload-key credentials take precedence over the local test opt-in.
    signingConfigs {
        if (missingSigning.isEmpty()) {
            create("release") {
                storeFile = file(releaseSigning.getValue("HOLYBEANS_KEYSTORE")!!)
                storePassword = releaseSigning.getValue("HOLYBEANS_KEYSTORE_PASSWORD")
                keyAlias = releaseSigning.getValue("HOLYBEANS_KEY_ALIAS")
                keyPassword = releaseSigning.getValue("HOLYBEANS_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (missingSigning.isEmpty()) "release" else "debug",
            )
            proguardFiles("proguard-rules.pro")
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

if (isPatrolBuild) {
    dependencies {
        androidTestUtil("androidx.test:orchestrator:1.5.1")
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-auth:22.0.0")
    testImplementation("junit:junit:4.13.2")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Google's QR scanner screen: Play services draws the camera view, so
    // the app needs no camera permission.
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
}
