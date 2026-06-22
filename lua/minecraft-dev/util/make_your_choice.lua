local M = {}
local ok, pickers = pcall(require, "telescope.pickers")

---@param items string[]
---@param prompt string
---@param default string
---@param callback fun(selection: string)
local function select_with_default(items, prompt, default, callback)
	vim.ui.select(items, { prompt = prompt }, function(choice)
		callback(choice or default)
	end)
end

local function language_order(config_key)
	local config = require("minecraft-dev").config
	local languages = { "java", "kotlin" }
	if config.defaults[config_key].language == "kotlin" then
		languages = { "kotlin", "java" }
	end
	return languages
end

local function select_language(items, prompt, title, default, callback)
	if ok then
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values
		local actions = require("telescope.actions")
		local state = require("telescope.actions.state")
		local themes = require("telescope.themes")
		local selected = false
		pickers
			.new(themes.get_dropdown({ previewer = false }), {
				prompt_title = title,
				finder = finders.new_table({
					results = items,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr)
					actions.select_default:replace(function()
						local selection = state.get_selected_entry()
						selected = true
						actions.close(prompt_bufnr)
						if selection then
							callback(selection[1])
						else
							callback(default)
						end
					end)
					actions.close:enhance({
						post = function()
							if selected then
								return
							end
							selected = true
							callback(default)
						end,
					})
					return true
				end,
			})
			:find()
		return
	end
	vim.ui.select(items, { prompt = prompt }, function(choice)
		callback(choice or default)
	end)
end

---@param callback fun(select_value: ProgrammingLanguage)
function M.which_fabric_language(callback)
	local config = require("minecraft-dev").config
	select_language(
		language_order("fabric"),
		config.prompts.fabric.select_language,
		config.prompts.fabric.telescope_title,
		config.defaults.fabric.language,
		callback
	)
end

---@param callback fun(select_value: ProgrammingLanguage)
function M.which_paper_language(callback)
	local config = require("minecraft-dev").config
	select_language(
		language_order("paper"),
		config.prompts.paper.select_language,
		config.prompts.paper.telescope_title,
		config.defaults.paper.language,
		callback
	)
end

M.which_language = M.which_fabric_language

---@param callback fun(select_value: "client"|"server"|"both")
function M.which_fabric_side(callback)
	local config = require("minecraft-dev").config
	select_with_default({ "client", "server", "both" }, config.prompts.fabric.select_side, config.defaults.fabric.side, callback)
end

---@param prompt string
---@param default boolean
---@param callback fun(selection: boolean)
function M.confirm(prompt, default, callback)
	local default_label = default and "yes" or "no"
	select_with_default({ "yes", "no" }, prompt, default_label, function(choice)
		callback(choice == "yes")
	end)
end

return M
