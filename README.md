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
			generate_datagen = true,
			use_mixins = false,
		},
	},
})

```
and use the command
```vim
GmcPro [fabric|paper] [gradle|maven] version_minecraft [path/to/the/place/your/want/to/init/your/project]
```

When generating a Fabric project, the plugin now asks for:

- language: `java` or `kotlin`
- environment side: `client`, `server`, or `both`
- whether to generate datagen entrypoints
- whether to generate a mixin config and example mixin class

If you cancel a selection with `Esc`, the configured default is used.

When generating a Paper project, the plugin asks for `java` or `kotlin` and uses `defaults.paper.language` when cancelled.

### Lua API

Use the non-interactive API when another plugin or script already has the complete project specification:

```lua
local ok, err = require("minecraft-dev").generate({
  platform = "paper", -- paper, spigot, fabric, bungeecord, waterfall, velocity, or sponge
  build_system = "gradle",
  minecraft_version = "1.21.8",
  directory = "/tmp/example",
  group_id = "com.example",
  artifact_id = "example",
  package_name = "com.example.example",
  main_class = "ExamplePlugin",
  language = "java",
})
```

Paper and Spigot specifications also accept `plugin_name`, `plugin_version`, `description`, `authors`, `website`,
`prefix`, `load`, `load_before`, `depend`, and `soft_depend`. Set `paper_manifest = true` to generate the experimental
`paper-plugin.yml` format and its structured server dependencies.

Forge and NeoForge use Gradle and require `loader_version`. They also accept `parchment_version`, `use_mixins`,
`plugin_name`, `plugin_version`, `description`, and `license`.

Architectury uses Gradle and requires `fabric_loader_version`, `fabric_api_version`, `forge_version`, and
`architectury_api_version`. It generates `common`, `fabric`, and `forge` modules.

### Custom Templates

Local MinecraftDev creator descriptors (`.mcdev.template.json`, format versions 1-3) can be generated without UI:

```lua
local result, err = require("minecraft-dev").generate_template({
  provider = "local",
  source = "/path/to/template/repository",
  descriptor = "fabric/.mcdev.template.json",
  directory = "/tmp/example",
  properties = {
    PROJECT_NAME = "example",
    LANGUAGE = "Java",
  },
})
```

Template and destination paths are confined to their configured roots. The evaluator does not execute arbitrary Lua
or shell code.

Available providers are `local`, `archive`, `remote`, and `builtin`. Archive, remote, and builtin providers are
asynchronous and require `callback = function(result, err) ... end`; the returned handle supports `cancel()`.
`builtin` uses the official `minecraft-dev/templates` repository, while `remote` accepts any Git repository URL.

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

### last

im not good at english so plz forgive me T_T
