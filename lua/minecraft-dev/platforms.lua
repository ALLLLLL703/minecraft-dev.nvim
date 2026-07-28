local M = {}

local registry = {
	architectury = {
		build_systems = { "gradle" },
		generator = "minecraft-dev.generators.architectury",
		command = false,
	},
	bungeecord = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.plugin",
		command = true,
	},
	fabric = {
		build_systems = { "gradle" },
		generator = "minecraft-dev.generators.fabric",
		command = true,
	},
	forge = {
		build_systems = { "gradle" },
		generator = "minecraft-dev.generators.forge",
		command = false,
	},
	neoforge = {
		build_systems = { "gradle" },
		generator = "minecraft-dev.generators.forge",
		command = false,
	},
	paper = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.paper",
		command = true,
	},
	spigot = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.paper",
		command = true,
	},
	sponge = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.plugin",
		command = true,
	},
	velocity = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.plugin",
		command = true,
	},
	waterfall = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.plugin",
		command = true,
	},
}

---@return string[]
function M.names()
	local names = vim.tbl_keys(registry)
	table.sort(names)
	return names
end

---@return string[]
function M.command_names()
	local names = {}
	for name, platform in pairs(registry) do
		if platform.command then table.insert(names, name) end
	end
	table.sort(names)
	return names
end

---@param name string
---@return boolean
function M.supports_command(name)
	local platform = M.get(name)
	return platform ~= nil and platform.command == true
end

---@param name string
---@return table?
function M.get(name)
	return registry[name]
end

---@param name string
---@return string[]
function M.build_systems(name)
	local platform = M.get(name)
	if not platform then
		return {}
	end
	return vim.deepcopy(platform.build_systems)
end

---@param name string
---@param build_system string
---@return boolean
function M.supports(name, build_system)
	for _, candidate in ipairs(M.build_systems(name)) do
		if candidate == build_system then
			return true
		end
	end
	return false
end

return M
