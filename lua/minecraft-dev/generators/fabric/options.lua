local choices = require("minecraft-dev.util.make_your_choice")
local version = require("minecraft-dev.version")

local M = {}

---@param minecraft_version string
---@param callback fun(options: FabricGenerationOptions)
function M.collect(minecraft_version, callback)
	local config = require("minecraft-dev").config
	choices.which_fabric_language(function(language)
		choices.which_fabric_side(function(side)
			choices.confirm(config.prompts.fabric.use_official_mappings, config.defaults.fabric.use_official_mappings, function(use_official_mappings)
				choices.confirm(config.prompts.fabric.use_fabric_api, config.defaults.fabric.use_fabric_api, function(use_fabric_api)
					local function collect_features(split_sources)
						local function collect_mixins(generate_datagen)
							choices.confirm(config.prompts.fabric.use_mixins, config.defaults.fabric.use_mixins, function(use_mixins)
								local function complete(client_mixins)
									callback({
										language = language,
										side = side,
										use_official_mappings = use_official_mappings,
										use_fabric_api = use_fabric_api,
										split_sources = split_sources,
										generate_datagen = generate_datagen,
										use_mixins = use_mixins,
										client_mixins = client_mixins,
									})
								end
								if use_mixins and split_sources and side ~= "server" then
									choices.confirm(config.prompts.fabric.client_mixins, config.defaults.fabric.client_mixins, complete)
								else complete(false) end
							end)
						end
						if use_fabric_api then
							choices.confirm(config.prompts.fabric.generate_datagen, config.defaults.fabric.generate_datagen, collect_mixins)
						else collect_mixins(false) end
					end
					if version.at_least(minecraft_version, 1, 18) then
						choices.confirm(config.prompts.fabric.split_sources, config.defaults.fabric.split_sources, collect_features)
					else collect_features(false) end
				end)
			end)
		end)
	end)
end

return M
