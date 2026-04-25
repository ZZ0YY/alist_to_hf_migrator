allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Ensure all plugin subprojects have compileSdkVersion available.
// Some plugins (e.g. package_info_plus 9.x) reference `flutter.compileSdkVersion`
// which requires the Flutter Gradle plugin to be applied first.
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.findByName("android")
            if (android is com.android.build.gradle.LibraryExtension) {
                if (android.compileSdk == null) {
                    android.compileSdk = 34
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
