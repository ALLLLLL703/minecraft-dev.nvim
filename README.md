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
- Python 3.10+ for dependency-free binary NBT editing (standard library only)
- YAML, Java, and Kotlin Tree-sitter parsers for metadata and source translation diagnostics (optional):
  `require("nvim-treesitter").install({ "yaml", "java", "kotlin" })`
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
		translations = {
			order = "ascending",
			default_locale = "en_us",
			template_path = "minecraft_localization_template.lang", -- optional
			diagnostics = true,
			source_diagnostics = true,
			source_scan_max_files = 1000,
		},
		metadata = {
			diagnostics = true,
			source_scan_max_files = 1000,
		},
		nbt = {
			python = "python3",
			timeout_ms = 10000,
			max_input_bytes = 32 * 1024 * 1024,
			max_output_bytes = 64 * 1024 * 1024,
			max_depth = 128,
			max_tags = 250000,
			max_array_length = 1000000,
			max_string_bytes = 1024 * 1024,
		},
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
MinecraftDevSortTranslations [ascending|descending|like-default|template]
MinecraftDevGotoTranslation [key]
MinecraftDevFindTranslationUsages [key]
MinecraftDevGotoBukkitMain [fully.qualified.Class]
MinecraftDevGotoForgeMod [mod_id]
MinecraftDevGotoForgeLogo
MinecraftDevGotoFabricEntrypoint [class_or_member]
MinecraftDevGotoFabricResource
MinecraftDevGotoMixinReference [class]
MinecraftDevEditNbt [path]
MinecraftDevSaveNbt
MinecraftDevReloadNbt[!]
```

`:GmcPro` without arguments and `:MinecraftDevNew` open the same builtin Neovim UI wizard backed by the official
MinecraftDev template repository. Forge, NeoForge, and Architectury require this wizard because their complete version
sets do not fit the positional command. Fabric's composite versions use dedicated selectors rather than a JSON prompt;
other unsupported composite property types still use JSON input. Prompts and messages remain configurable through
`setup()`. Cancelling a wizard selection aborts generation without creating a project.

`:MinecraftDevSortTranslations` sorts modern JSON and legacy `.lang` Minecraft translation files under
`assets/<namespace>/lang/`. The default `ascending` mode compares dotted key segments; `descending` reverses that
order, and `like-default` follows the sibling `en_us` file with the same extension before appending locale-only keys
alphabetically. `template` loads `defaults.translations.template_path` and supports MinecraftDev-compatible key
patterns, comments, and empty-line groups. Lua callers may override it with `template_path` or `template_content`.
Legacy sorting keeps attached comments, blank separators, values, and the final newline. Invalid or duplicate entries
fail without rewriting the buffer.

Translation diagnostics are enabled by default for JSON and `.lang` buffers. They report duplicate or malformed
entries, key whitespace, locale-only keys, and format placeholders that differ from the sibling default locale. The
public `require("minecraft-dev").diagnose_translations({ buffer = 0 })` entrypoint runs the same check manually;
setting `defaults.translations.diagnostics = false` disables the automatic buffer events without affecting LSP or
other diagnostic namespaces.

`:MinecraftDevGotoTranslation` opens the matching default-locale entry for an explicit key or the key under the
cursor. Command-line completion is backed by all default locale files under the project root and preserves duplicate
keys from different resource namespaces as multiple navigation targets. Non-default translation buffers receive a
`completefunc` source for `CTRL-X CTRL-U` only when they do not already define one; LSP `omnifunc` is never replaced.
Lua integrations can use `list_translation_keys()`, `complete_translations()`, and `goto_translation({ open = false })`
without opening UI.

With Java/Kotlin Tree-sitter parsers installed, source diagnostics recognize configured Minecraft translation calls
such as `Component.translatable`, `I18n.format`, and legacy `StatCollector` calls. They report missing keys,
missing/superfluous format arguments, and removed or renamed keys from `assets/minecraft/lang/deprecated.json`.
Constant-string calls also work with `MinecraftDevGotoTranslation`; interpolated, concatenated, or dynamic keys are
left to the language server. Set `source_diagnostics = false` to disable automatic source checks, or replace
`defaults.translations.source_calls` with the fully qualified call suffixes used by the project.

`:MinecraftDevFindTranslationUsages [key]` lists matching entries from every locale plus supported constant Java/Kotlin
calls in the quickfix window. Without an explicit key it uses the translation entry or source call under the cursor.
Source scanning is bounded by `defaults.translations.source_scan_max_files`; Lua callers can use
`find_translation_usages({ open = false })` to receive sorted structured locations without changing the UI.

With YAML plus Java/Kotlin Tree-sitter parsers installed, `plugin.yml` and `paper-plugin.yml` diagnose missing,
unresolved, abstract, or provably non-Bukkit `main` classes. Local inheritance chains and unsaved source buffers are
included; incomplete parser or bounded-scan results become warnings instead of false unresolved errors.
`:MinecraftDevGotoBukkitMain` jumps to the class declaration, and manifest buffers receive a `completefunc` containing
concrete Bukkit plugin classes without replacing LSP `omnifunc`. Lua callers can use `diagnose_bukkit_manifest()`,
`complete_bukkit_main()`, and `goto_bukkit_main({ open = false })`.

The same diagnostics validate manifest structure without requiring a running server: required scalar fields,
`api-version`, command and permission mappings, legacy dependency lists, duplicate or self dependencies, and Paper
`bootstrap`/`server` dependency options. Paper `load` accepts `BEFORE`, `AFTER`, or `OMIT`; `required` and
`join-classpath` must be YAML booleans. Unknown extension fields remain allowed.

With the TOML Tree-sitter parser installed, `mods.toml` and `neoforge.mods.toml` validate required loader metadata,
field types, mod IDs, Maven-style version ranges, known `displayTest`/`ordering`/`side` values, dependency table owners,
and `logoFile` resource paths, plus local Java/Kotlin `@Mod` declarations. Their buffer-local `completefunc` suggests
schema keys, known values, dependency owners, and constant `@Mod` IDs; completion items carry field documentation.
`:MinecraftDevGotoForgeMod` resolves a `[[dependencies.<modid>]]` owner to its `[[mods]]` declaration and a `modId`
value to the matching source class, while
`:MinecraftDevGotoForgeLogo` opens the resource under the manifest's resource root. Lua callers can use
`diagnose_forge_manifest()`, `complete_forge_manifest()`, `goto_forge_mod()`, and `goto_forge_logo()`.

`fabric.mod.json` diagnostics validate required metadata, mod IDs, schema ordering/version, environment and dependency
values, Java/Kotlin entrypoint classes and `Class::member` rules, plus mixin config, access widener, icon, and project
license references. Entrypoint checks cover initializer inheritance, public/no-argument methods, static fields, and empty
constructors where required. `:MinecraftDevGotoFabricEntrypoint` and `:MinecraftDevGotoFabricResource` provide source
and resource navigation; Lua callers can use `diagnose_fabric_manifest()`, `complete_fabric_entrypoints()`,
`complete_fabric_resources()`, `goto_fabric_entrypoint()`, and `goto_fabric_resource()`.

Mixin config files matching `mixin*.json`, `mixins*.json`, or dotted variants validate package/type structure,
compatibility levels, duplicate class entries, local Java/Kotlin `@Mixin` classes, and concrete
`IMixinConfigPlugin` implementations. `:MinecraftDevGotoMixinReference` navigates package-relative Mixin classes or
plugin classes. Lua callers can use `diagnose_mixin_config()`, `complete_mixin_config()`, and
`goto_mixin_reference()`. JSON5 is supported when a `json5` Tree-sitter parser is installed; a missing parser is
reported structurally without falling back to lossy text matching.

`:MinecraftDevEditNbt` opens gzip, zlib, or uncompressed binary NBT as an editable typed JSON buffer. Every node keeps
its exact NBT `type`; signed 64-bit `long` values use decimal strings, lists declare `element_type`, and compounds use
an ordered array of named children. `:write` or `:MinecraftDevSaveNbt` validates the complete structure and atomically
replaces the backing file while preserving its compression and permissions. `:MinecraftDevReloadNbt` refuses to
discard unsaved edits; use `:MinecraftDevReloadNbt!` to force it. Lua callers can use `open_nbt()`, `save_nbt()`, and
`reload_nbt()`; asynchronous opens return a cancellable operation. Input, expanded output, depth, tag count, array,
string, and timeout limits are configurable under `defaults.nbt`.

NBT uses the repository's small Python standard-library codec instead of an optional Lua compression module or an
external NBT package. This keeps gzip/zlib and IEEE numeric handling consistent without adding a package-manager
dependency. Missing Python, malformed input, unknown tags, limit violations, timeouts, and cancellation are reported
as structured failures; the original file is never replaced after validation or encoding failure.

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

Translation sorting is also available as a structured Lua API:

```lua
local result = require("minecraft-dev").sort_translations({
  buffer = 0,
  order = "like-default",
})

if result.status == "failed" then
  vim.notify(vim.inspect(result.error), vim.log.levels.ERROR)
end
```

Its defaults are configured through `defaults.translations.order`, `default_locale`, and `indent` in `setup()`.

Paper and Spigot specifications also accept `plugin_name`, `plugin_version`, `description`, `authors`, `website`,
`prefix`, `load`, `load_before`, `depend`, and `soft_depend`. Set `paper_manifest = true` to generate the experimental
`paper-plugin.yml` format and its structured server dependencies.

Waterfall specifications accept a Minecraft version such as `1.21` or `1.21.1` and asynchronously resolve the newest
matching Waterfall API version. Set `waterfall_version` to a complete artifact version to bypass online resolution.
BungeeCord and Waterfall target Java 8; Kotlin projects shade the Kotlin runtime into the generated plugin JAR.
Sponge derives Java 16/17/21 from API 8/9-10/11+, uses SpongeGradle metadata for Gradle, and writes
`META-INF/sponge_plugins.json` for Maven.

Forge and NeoForge use Gradle and resolve compatible versions from official Maven metadata when their version fields
are omitted. Explicit version fields bypass online resolution, so callers are responsible for compatible coordinates.
The ForgeGradle 6 generator supports Minecraft 1.16 through 1.21.1 and also accepts
`parchment_version`, `use_mixins`, `plugin_name`, `plugin_version`, `description`, `authors`, `website`, `update_url`,
and `license`. Generated Forge projects include version-specific entry and Config sources, a compilable Mixin example
when enabled, a license file, and client/server/data/build runs in `.nvim/minecraft-dev-runs.json`.

NeoForge supports Java and Kotlin projects for Minecraft 1.20.5 through 1.21.4. Minecraft 1.21+ uses
ModDevGradle through `moddev_version`; older projects use NeoGradle through `neogradle_version`. Kotlin projects use
the matching KotlinForForge release. NeoForge also accepts `parchment_version` and
`parchment_minecraft_version`, writes expandable metadata under `src/main/templates`, and generates version-specific
Config, datagen, Mixin, language, license, pack metadata, and Neovim run files.

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
Forge's `genIntellijRuns` task is translated into Neovim client, server, and data Gradle runs instead of generating
IntelliJ configuration files.

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

The matrix covers Paper, Velocity, BungeeCord, Waterfall, Sponge, Fabric Java/Kotlin with Mixin and datagen, Forge
1.16.5/1.20.1/1.20.6/1.21.1, NeoForge, and Architectury. It
reuses `~/.gradle` and `~/.m2/repository` by default and writes a JSON report to a temporary path. Use
`MINECRAFT_DEV_MATRIX_CASES=paper-java-gradle,fabric-kotlin-gradle` to select cases,
`MINECRAFT_DEV_MATRIX_TIMEOUT_MS` to change each build timeout, `MINECRAFT_DEV_MATRIX_REPORT` to choose the report,
and `MINECRAFT_DEV_MATRIX_KEEP=1` to preserve generated projects. Failures are classified as timeout, network,
dependency resolution, missing tool, process startup, generation, JDK mismatch, or ordinary build failures.
Reports also include the Git commit, dirty-worktree state, actual Java/Gradle/Maven versions, pinned per-case toolchains,
cache paths, commands, durations, and the final status of every case. Unknown or empty case filters are rejected.

### last

im not good at english so plz forgive me T_T
