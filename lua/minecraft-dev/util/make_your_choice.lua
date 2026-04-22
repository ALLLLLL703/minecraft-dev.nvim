local M = {}
local ok, pickers = pcall(require, "telescope.pickers")

---@generic T
---@param val table<T>
---@return T[]
local function table_to_list(val)
	local result = { "java", "kotlin" }
	print(val)
	for _, value in ipairs(val) do
		table.insert(result, value)
		print(value)
	end

	print(result)
	return result
end
---@param callback fun(select_value: ProgrammingLanguage)
function M.which_language(callback)
	local languages = { "java", "kotlin" }
	if ok then
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values
		local actions = require("telescope.actions")
		local state = require("telescope.actions.state")
		local themes = require("telescope.themes")
		pickers
			.new(themes.get_dropdown({ previewer = false }), {
				prompt_title = "select language",
				finder = finders.new_table({
					results = languages,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr)
					actions.select_default:replace(function()
						local selection = state.get_selected_entry()
						actions.close(prompt_bufnr)
						if selection then
							callback(selection[1])
						end
					end)
					return true
				end,
			})
			:find()
		return
	end
	vim.ui.select(languages, { prompt = "Select language" }, function(choiece)
		if choiece then
			callback(choiece)
		end
	end)
end

return M
