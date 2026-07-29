import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    kotlin("jvm") version "__KOTLIN_VERSION__"
    id("__LOOM_PLUGIN__") version "__LOOM_VERSION__"
    id("maven-publish")
}

version = project.property("mod_version") as String
group = project.property("maven_group") as String
val minecraftVersion = project.property("minecraft_version") as String
val loaderVersion = project.property("loader_version") as String

base {
    archivesName.set(project.property("archives_base_name") as String)
}

val targetJavaVersion = __JAVA_VERSION__
java {
    toolchain.languageVersion = JavaLanguageVersion.of(targetJavaVersion)
    withSourcesJar()
}

__LOOM_BLOCK__

__DATAGEN_BLOCK__

repositories {
    mavenCentral()
}

dependencies {
    minecraft("com.mojang:minecraft:$minecraftVersion")
__MAPPINGS_DEPENDENCY__
    __LOADER_CONFIGURATION__("net.fabricmc:fabric-loader:$loaderVersion")
    __LOADER_CONFIGURATION__("net.fabricmc:fabric-language-kotlin:__KOTLIN_LOADER_VERSION__")
__FABRIC_API_DEPENDENCY__
}

tasks.processResources {
    inputs.property("version", project.version)
    inputs.property("minecraft_version", minecraftVersion)
    inputs.property("loader_version", loaderVersion)
    filteringCharset = "UTF-8"

    filesMatching("fabric.mod.json") {
        expand(
            "version" to project.version.toString(),
            "minecraft_version" to minecraftVersion,
            "loader_version" to loaderVersion,
        )
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
    options.release.set(targetJavaVersion)
}

tasks.withType<KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(JvmTarget.fromTarget(targetJavaVersion.toString()))
}

tasks.jar {
    from("LICENSE") {
        rename { "${it}_${project.base.archivesName.get()}" }
    }
}

publishing {
    publications {
        create<MavenPublication>("mavenJava") {
            artifactId = project.property("archives_base_name") as String
            from(components["java"])
        }
    }
}
