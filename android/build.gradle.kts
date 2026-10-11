allprojects { repositories {
    google()
    mavenCentral()
    maven { url = uri("https://jitpack.io"); content { includeGroup("com.github.teamnewpipe"); includeGroup("com.github.TeamNewPipe") } }
} }
val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)
subprojects { layout.buildDirectory.value(newBuildDir.dir(project.name)); evaluationDependsOn(":app") }
tasks.register<Delete>("clean") { delete(rootProject.layout.buildDirectory) }
