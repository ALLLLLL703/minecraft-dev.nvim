plugins {
    kotlin("jvm") version "%s"
    id("com.gradleup.shadow") version "%s"
}

group = "%s"
version = "%s"

repositories {
    mavenCentral()
    maven { url = uri("https://repo.papermc.io/repository/maven-public/") }
}

dependencies {
    compileOnly("io.papermc.paper:paper-api:%s-R0.1-SNAPSHOT")
    implementation(kotlin("stdlib"))
}

kotlin {
    jvmToolchain(%d)
}

tasks.build {
    dependsOn(tasks.shadowJar)
}
