val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 自动给老插件（amap_flutter_location 等）补 namespace，
// 解决 AGP 8.x 的 "Namespace not specified" 报错
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.getByType<com.android.build.gradle.LibraryExtension>()
        if (android.namespace.isNullOrEmpty()) {
            val manifestFile = file("${project.projectDir}/src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                val packageName = javax.xml.parsers.DocumentBuilderFactory.newInstance()
                    .newDocumentBuilder()
                    .parse(manifestFile)
                    .documentElement
                    .getAttribute("package")
                if (packageName.isNotEmpty()) {
                    android.namespace = packageName
                    println("[namespace-patch] Set namespace=$packageName for ${project.name}")
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
