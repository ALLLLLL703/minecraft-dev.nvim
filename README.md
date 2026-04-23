# Minecraft-Dev.nvim

A [MinecraftDev](https://github.com/minecraft-dev/MinecraftDev) like plugin
still developing,,,
Now can using to generate 
- fabric kotlin mod
- fabric java mod
- paper java plugin


<!-- TOC -->

- [Requirements](#Requirements)
- [Installation](#Installation)
- [Quick start](#QuickStart)
- [Contribute](#Contribute)

<!-- /TOC -->

## Requirements

- Neovim 0.12+
- Picker installed
    - [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (Optional) for language(kotlin/java) pick

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
    debug = true | false,
})

```
and use the command
```vim
GmcPro [fabric|paper] [gradle|maven] version_minecraft path/to/the/place/your/want/to/init/your/project
```

## Contribute

if you are interested with minecraft dev in Neovim and wants the template setup like MinecraftDev in intellij-idea
feel free to commit a PR
I'll check it as soon as possible
At last, thank you all for the using or contributing this plugin :D
♥️

### last

im not good at english so plz forgive me T_T


