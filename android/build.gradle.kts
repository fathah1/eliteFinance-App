allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Workaround for old plugins that do not declare `namespace` (required by AGP 8+).
subprojects {
    if (name == "blue_thermal_printer") {
        pluginManager.withPlugin("com.android.library") {
            val androidExt = extensions.findByName("android") ?: return@withPlugin
            val extClass = androidExt.javaClass
            val getNamespace = extClass.methods.firstOrNull { it.name == "getNamespace" }
            val setNamespace = extClass.methods.firstOrNull {
                it.name == "setNamespace" && it.parameterTypes.size == 1
            }
            val current = getNamespace?.invoke(androidExt) as? String
            if (current.isNullOrBlank()) {
                setNamespace?.invoke(androidExt, "id.kakzaki.blue_thermal_printer")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
