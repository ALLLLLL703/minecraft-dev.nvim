local choices = require("minecraft-dev.util.make_your_choice")

local M = {}

---@param callback fun(options: FabricGenerationOptions)
function M.collect(callback)
	local config = require("minecraft-dev").config
	choices.which_fabric_language(function(language)
		choices.which_fabric_side(function(side)
			choices.confirm(config.prompts.fabric.generate_datagen, config.defaults.fabric.generate_datagen, function(generate_datagen)
				choices.confirm(config.prompts.fabric.use_mixins, config.defaults.fabric.use_mixins, function(use_mixins)
					callback({
						language = language,
						side = side,
						generate_datagen = generate_datagen,
						use_mixins = use_mixins,
					})
				end)
			end)
		end)
	end)
end

return M
