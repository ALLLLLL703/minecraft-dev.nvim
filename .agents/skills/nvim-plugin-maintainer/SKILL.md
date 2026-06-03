---
name: nvim-plugin-maintainer
description: Maintain and extend Neovim plugins in this repository. Use when working on plugin features, commands, configuration, UI selection, runtime behavior, help-facing APIs, or dependency decisions for this project. Always consult official Neovim documentation first for APIs, defaults, and behavior. Add optional plugin dependencies only when the built-in Neovim API is not enough or when the project already benefits from the integration, especially picker-related dependencies such as telescope.nvim.
---

# Neovim Plugin Workflow

Follow this workflow when changing the plugin.

1. Inspect the existing Lua modules, README, and user-facing commands before changing behavior.
2. Check official Neovim documentation before assuming API behavior.
3. Prefer built-in Neovim APIs first.
4. Keep optional dependencies optional unless the feature cannot work without them.
5. Match the repository's current patterns for module layout, config, and command registration.

# Documentation First

Consult official Neovim docs before editing code that touches:

- `vim.api`
- `vim.ui`
- `vim.fs`
- user commands
- notifications
- Lua runtime behavior inside Neovim
- package/module reloading
- picker or UI fallback behavior

Start with these help targets when relevant:

- `:help lua`
- `:help api`
- `:help vim.ui`
- `:help vim.fs`
- `:help user-commands`
- `:help packages`
- `:help runtimepath`
- `:help health`

If local help is not enough, consult the official Neovim docs site or source documentation for the exact version the project targets.

# Dependency Rules

Prefer no new dependency when one of these is sufficient:

- `vim.ui.select`
- `vim.notify`
- built-in Lua
- core Neovim file/path APIs

Add a plugin dependency only when it clearly improves the feature and the built-in fallback is not enough.

Use these rules.

- Add `nvim-telescope/telescope.nvim` when the feature needs a richer picker UX than `vim.ui.select` can reasonably provide.
- If `telescope.nvim` is added as a real dependency in plugin specs, also ensure its required dependency `nvim-lua/plenary.nvim` is present.
- Keep Telescope optional when the feature can still work with `vim.ui.select` fallback.
- Do not add broad utility dependencies just for convenience if the logic is small enough to keep local.

# Repository-Specific Guidance

This repository already uses an optional Telescope path in `lua/minecraft-dev/util/make_your_choice.lua` and falls back to `vim.ui.select`.

Preserve that style unless there is a strong reason to change it:

- keep core functionality working without Telescope
- gate optional integrations with `pcall(require, ...)`
- provide a built-in fallback path

When adding dependency examples to docs or plugin specs, prefer concise examples that show optional integration clearly.

Example `lazy.nvim` shape:

```lua
{
  "ALLLLLL703/minecraft-dev.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  opts = {},
}
```

Example optional runtime integration pattern:

```lua
local ok, telescope = pcall(require, "telescope.pickers")

if ok then
  -- Telescope path
else
  vim.ui.select(items, { prompt = "Select item" }, callback)
end
```

# Change Standards

When implementing changes:

- keep edits minimal
- preserve public commands unless the task requires changing them
- update README when installation, requirements, or behavior changes
- prefer clear fallback behavior over hard failure for optional integrations
- avoid hidden dependency coupling

# Done Criteria

Before finishing:

1. Re-check the relevant Neovim docs for the touched API surface.
2. Verify optional dependencies are truly optional unless intentionally required.
3. Verify README or install docs if dependency expectations changed.
4. Verify the feature still works without optional picker plugins when fallback behavior is expected.
