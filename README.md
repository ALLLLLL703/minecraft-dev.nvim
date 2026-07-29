# Minecraft-Dev.nvim

A [MinecraftDev](https://github.com/minecraft-dev/MinecraftDev) like plugin
still developing,,,
Now can using to generate 
- fabric kotlin mod
- fabric java mod
- paper kotlin plugin
- paper java plugin
- spigot kotlin plugin
- spigot java plugin
- bungeecord and waterfall plugins
- velocity plugins
- sponge plugins
- forge and neoforge mods
- architectury Fabric/Forge multi-loader mods


<!-- TOC -->

- [Requirements](#Requirements)
- [Installation](#Installation)
- [Quick start](#QuickStart)
- [Contribute](#Contribute)

<!-- /TOC -->

## Requirements

- Neovim 0.12+
- Picker support
    - built-in `vim.ui.select` works by default
    - [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) is optional for a richer language picker experience

## Installation

minecraft-dev.nvim supports all the usual plugin managers (maybe)

<details>
  <summary>nvim native package manager</summary>

```lua
      vim.pack.add({src = "https://github.com/ALLLLLL703/minecraft-dev.nvim"}) 

```
</details>


## QuickStart

all your need is to setup this plugin manualy

```lua
require("minecraft-dev").setup({
	logging = {
		debug = true, -- optional
	},
	defaults = {
		paper = {
			version = "1.21",
			language = "java",
		},
		fabric = {
			version = "1.21.11",
			side = "both",
			use_official_mappings = true,
			use_fabric_api = true,
			split_sources = true,
			generate_datagen = true,
			use_mixins = false,
			client_mixins = true,
			cache_ttl = 24 * 60 * 60,
			version_data = {
				gradle_version = "9.6.1",
				kotlin_loader = "1.13.13+kotlin.2.4.10",
			},
		},
	},
})

```
and use the command
```vim
GmcPro
GmcPro [bungeecord|fabric|paper|spigot|sponge|velocity|waterfall] [gradle|maven] minecraft_version [path]
MinecraftDevNew
```

`:GmcPro` without arguments and `:MinecraftDevNew` open the same builtin Neovim UI wizard backed by the official
MinecraftDev template repository. Forge, NeoForge, and Architectury require this wizard because their complete version
sets do not fit the positional command. Fabric's composite versions use dedicated selectors rather than a JSON prompt;
other unsupported composite property types still use JSON input. Prompts and messages remain configurable through
`setup()`. Cancelling a wizard selection aborts generation without creating a project.

When generating a Fabric project, the plugin now asks for:

- language: `java` or `kotlin`
- environment side: `client`, `server`, or `both`
- Yarn or official Mojang mappings (26.1+ always uses the new Loom mapping behavior)
- whether to include Fabric API
- whether Minecraft 1.18+ projects split client sources
- whether to generate datagen entrypoints; this is disabled without Fabric API
- whether to generate main and separate client Mixin configs and example classes

If you cancel a selection with `Esc`, the configured default is used.

When generating a Paper project, the plugin asks for `java` or `kotlin` and uses `defaults.paper.language` when cancelled.

### Lua API

Use the non-interactive API when another plugin or script already has the complete project specification:

```lua
local operation = require("minecraft-dev").generate({
  platform = "paper", -- paper, spigot, fabric, bungeecord, waterfall, velocity, or sponge
  build_system = "gradle",
  minecraft_version = "1.21.8",
  directory = "/tmp/example",
  group_id = "com.example",
  artifact_id = "example",
  package_name = "com.example.example",
  main_class = "ExamplePlugin",
  language = "java",
}, function(result)
  if result.status == "generated" then
    print("Generated at " .. result.path)
  elseif result.status == "failed" then
    vim.notify(vim.inspect(result.error), vim.log.levels.ERROR)
  end
end)

-- Requests cancellation and remains pending until active child processes exit.
-- operation.cancel()
```

`generate()` and `generate_async()` use the same asynchronous contract. They return an operation whose `status` is
`pending`, `generated`, `failed`, or `cancelled`; the optional callback runs exactly once with the final result.
Projects are prepared in a sibling staging directory and only moved into `directory` after wrapper and network work
finishes. Failed and cancelled generations remove staging output. The destination must be absent or empty.
Concurrent generation of the same destination returns `generation_in_progress`. A lock left by a crashed process returns
`stale_generation_lock`; verify that its recorded PID is no longer running before removing the adjacent lock file.

Paper and Spigot specifications also accept `plugin_name`, `plugin_version`, `description`, `authors`, `website`,
`prefix`, `load`, `load_before`, `depend`, and `soft_depend`. Set `paper_manifest = true` to generate the experimental
`paper-plugin.yml` format and its structured server dependencies.

Waterfall specifications accept a Minecraft version such as `1.21` or `1.21.1` and asynchronously resolve the newest
matching Waterfall API version. Set `waterfall_version` to a complete artifact version to bypass online resolution.
BungeeCord and Waterfall target Java 8; Kotlin projects shade the Kotlin runtime into the generated plugin JAR.
Sponge derives Java 16/17/21 from API 8/9-10/11+, uses SpongeGradle metadata for Gradle, and writes
`META-INF/sponge_plugins.json` for Maven.

Forge and NeoForge use Gradle and require `loader_version`. They also accept `parchment_version`, `use_mixins`,
`plugin_name`, `plugin_version`, `description`, and `license`.

Architectury uses Gradle and requires `fabric_loader_version`, `fabric_api_version`, `forge_version`, and
`architectury_api_version`. It generates `common`, `fabric`, and `forge` modules.

Fabric Kotlin projects generate Kotlin Gradle DSL files and use Fabric Language Kotlin. Set `kotlin_loader_version`
on an individual specification, or `defaults.fabric.version_data.kotlin_loader` globally. The Kotlin compiler plugin
version is derived from the Fabric Language Kotlin version, and asynchronous Fabric version refreshes update both.
Fabric specifications also accept `use_official_mappings`, `yarn_version`, `use_fabric_api`, `fabric_api_version`,
`split_sources`, `generate_datagen`, `use_mixins`, and `client_mixins`. Fabric version catalogs cache for
`defaults.fabric.cache_ttl` seconds and use stale data with a warning when refresh fails.

### Custom Templates

Local MinecraftDev creator descriptors (`.mcdev.template.json`, format versions 1-3) can be generated without UI:

```lua
local operation = require("minecraft-dev").generate_template({
  provider = "local",
  source = "/path/to/template/repository",
  descriptor = "fabric/.mcdev.template.json",
  directory = "/tmp/example",
  properties = {
    PROJECT_NAME = "example",
    LANGUAGE = "Java",
  },
  callback = function(result)
    if result.status == "generated" then
      print("Generated " .. #result.files .. " files")
    end
  end,
})
```

Template and destination paths are confined to their configured roots. The evaluator does not execute arbitrary Lua
or shell code.

The compatibility evaluator supports the Velocity directives and object expressions used by the official Java and
Kotlin templates, including semantic version comparisons, class FQN subpackages, property derivations, and inline
conditionals.

Available providers are `local`, `archive`, `remote`, and `builtin`. Every provider returns the same asynchronous
operation and accepts `callback = function(result) ... end`; the operation supports `cancel()`.
`builtin` uses the official `minecraft-dev/templates` repository, while `remote` accepts any Git repository URL.
Use `list_templates(options)` with the same provider options to discover descriptors before generation.

Supported finalizers are `run_gradle_tasks`, `import_gradle_project`, `import_maven_project`, `add_gradle_run`,
`add_maven_run`, and `git_add_all`. Import finalizers emit `User MinecraftDevProjectGenerated`; reusable run definitions
are written to `.nvim/minecraft-dev-runs.json`. External commands remain asynchronous, and template generation only
becomes `generated` after every finalizer succeeds.

Fabric generation refreshes Loader and Yarn versions from Fabric Meta and the Fabric API version from Modrinth before
generation. Successful responses are cached under Neovim's cache directory; network or response failures fall back to
bundled version data and are reported through the generated result's `warnings` field.

## Contribute

if you are interested with minecraft dev in Neovim and wants the template setup like MinecraftDev in intellij-idea
feel free to commit a PR
I'll check it as soon as possible
At last, thank you all for the using or contributing this plugin :D
♥️

### Dev Check

Run the lightweight refactor checks with:

```bash
nvim --headless --clean -u NONE \
  "+set rtp+=." \
  "+lua dofile('test/test_refactor.lua')" \
  +qa
```

Run the optional network-backed build matrix with JDK 17, 21, and 25, plus Gradle and Maven installed:

```bash
MINECRAFT_DEV_JAVA_17_HOME=/path/to/jdk-17 \
MINECRAFT_DEV_JAVA_21_HOME=/path/to/jdk-21 \
MINECRAFT_DEV_JAVA_25_HOME=/path/to/jdk-25 \
nvim --headless --clean -u NONE \
  "+set rtp+=." \
  "+lua dofile('test/integration_build_matrix.lua')"
```

The matrix covers Paper, Velocity, BungeeCord, Waterfall, Sponge, Fabric Java/Kotlin with Mixin and datagen, Forge,
NeoForge, and Architectury. It
reuses `~/.gradle` and `~/.m2/repository` by default and writes a JSON report to a temporary path. Use
`MINECRAFT_DEV_MATRIX_CASES=paper-java-gradle,fabric-kotlin-gradle` to select cases,
`MINECRAFT_DEV_MATRIX_TIMEOUT_MS` to change each build timeout, `MINECRAFT_DEV_MATRIX_REPORT` to choose the report,
and `MINECRAFT_DEV_MATRIX_KEEP=1` to preserve generated projects. Failures are classified as timeout, network,
dependency resolution, missing tool, process startup, generation, JDK mismatch, or ordinary build failures.
Reports also include the Git commit, dirty-worktree state, actual Java/Gradle/Maven versions, pinned per-case toolchains,
cache paths, commands, durations, and the final status of every case. Unknown or empty case filters are rejected.

### last

im not good at english so plz forgive me T_T
