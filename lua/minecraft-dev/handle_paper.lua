local M = {}

local util = require("minecraft-dev.util")

function M.generate_basic(path) end

function M.handle_paper_maven(path)
	-- Validate path
	if not path or path == "" then
		print("Error: Invalid path")
		return nil
	end

	local root_src = "/src/main/java/"

	-- Get user inputs with validation
	local groupId = vim.fn.input("GroupId:", "com.example")
	if not groupId or groupId == "" then
		groupId = "com.example"
	end

	local artifactId = vim.fn.input("artifactId:", "artifact")
	if not artifactId or artifactId == "" then
		artifactId = "artifact"
	end

	local main_file = vim.fn.input("main file name:", "Main")
	if not main_file or main_file == "" then
		main_file = "Main"
	end

	---@type string projectId
	local projectId = groupId .. "." .. artifactId
	local second_src = projectId:gsub("%.", "/")
	-- local archetype_dir = util.get_archetype_dir()
	local full_src = path .. root_src .. second_src

	-- if not archetype_dir then
	-- 	error("archetype_dir not found")
	-- 	return nil
	-- end

	-- Create directory structure with error handling
	local mkdir_result = vim.fn.mkdir(full_src, "p")
	if mkdir_result == 0 then
		print("Error: Failed to create directory: " .. full_src)
		return nil
	end

	-- Generate pom.xml with actual groupId and artifactId
	local pom_path = path .. "/pom.xml"
	local pom_content = string.format(
		[[<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>%s</groupId>
  <artifactId>%s</artifactId>
  <version>1.0-SNAPSHOT</version>
  <packaging>jar</packaging>
  <name>%s</name>
  <properties>
    <java.version>21</java.version>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
  <build>
    <defaultGoal>clean package</defaultGoal>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-compiler-plugin</artifactId>
        <version>3.13.0</version>
        <configuration>
          <source>${java.version}</source>
          <target>${java.version}</target>
        </configuration>
      </plugin>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-shade-plugin</artifactId>
        <version>3.5.3</version>
        <executions>
          <execution>
            <phase>package</phase>
            <goals>
              <goal>shade</goal>
            </goals>
          </execution>
        </executions>
      </plugin>
    </plugins>
    <resources>
      <resource>
        <directory>src/main/resources</directory>
        <filtering>true</filtering>
      </resource>
    </resources>
  </build>
  <repositories>
    <repository>
      <id>papermc-repo</id>
      <url>https://repo.papermc.io/repository/maven-public/</url>
    </repository>
  </repositories>
  <dependencies>
    <dependency>
      <groupId>io.papermc.paper</groupId>
      <artifactId>paper-api</artifactId>
      <version>1.21.1-R0.1-SNAPSHOT</version>
      <scope>provided</scope>
    </dependency>
  </dependencies>
</project>]],
		groupId,
		artifactId,
		artifactId
	)
	local pom_file = io.open(pom_path, "w")
	if pom_file then
		pom_file:write(pom_content)
		pom_file:close()
	else
		print("Error: Failed to create pom.xml")
		return nil
	end

	-- Create plugin.yml
	local resources_dir = path .. "/src/main/resources/"
	vim.fn.mkdir(resources_dir, "p")
	local plugin_yml_path = resources_dir .. "plugin.yml"
	local plugin_yml_content = string.format(
		"name: %s\nversion: '1.0-SNAPSHOT'\nmain: %s.%s\napi-version: '1.21'\n",
		artifactId,
		projectId,
		main_file
	)
	local plugin_file = io.open(plugin_yml_path, "w")
	if plugin_file then
		plugin_file:write(plugin_yml_content)
		plugin_file:close()
	else
		print("Error: Failed to create plugin.yml")
		return nil
	end

	-- Create main Java file
	local main_java_path = full_src .. "/" .. main_file .. ".java"
	local main_java_content = string.format(
		'package %s;\n\nimport org.bukkit.plugin.java.JavaPlugin;\n\npublic class %s extends JavaPlugin {\n\n    @Override\n    public void onEnable() {\n        getLogger().info("%s has been enabled!");\n    }\n\n    @Override\n    public void onDisable() {\n        getLogger().info("%s has been disabled!");\n    }\n}\n',
		projectId,
		main_file,
		main_file,
		main_file
	)
	local main_file_handle = io.open(main_java_path, "w")
	if main_file_handle then
		main_file_handle:write(main_java_content)
		main_file_handle:close()
	else
		print("Error: Failed to create main Java file")
		return nil
	end

	print("Successfully created project structure at: " .. path)
	print("GroupId: " .. groupId)
	print("ArtifactId: " .. artifactId)
	print("Main class: " .. main_file)
	print("Files created:")
	print("  - " .. pom_path)
	print("  - " .. plugin_yml_path)
	print("  - " .. main_java_path)
end

function M.handle_paper_gradle(path) end

function M.handle_paper(pkm, path)
	if not pkm then
		print("please specify maven or gradle")
		return nil
	end
	if not path then
		path = vim.fn.getcwd()
	end
	print(pkm)
	print(path)
	if pkm == "maven" then
		M.handle_paper_maven(path)
	end
end

return M
