# Minecraft-Dev.nvim

A [MinecraftDev](https://github.com/minecraft-dev/MinecraftDev) like plugin
still developing,,,
Now can using to generate 
- fabric kotlin mod
- fabric java mod
- paper kotlin plugin
- paper java plugin


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
