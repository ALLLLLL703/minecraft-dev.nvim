local M = {}

local registry = {
	bungeecord = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.plugin",
	},
	fabric = {
		build_systems = { "gradle" },
		generator = "minecraft-dev.generators.fabric",
	},
	forge = {
		build_systems = { "gradle" },
		generator = "minecraft-dev.generators.forge",
	},
	neoforge = {
		build_systems = { "gradle" },
		generator = "minecraft-dev.generators.forge",
	},
	paper = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.paper",
	},
	spigot = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.paper",
	},
	sponge = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.plugin",
	},
	velocity = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.plugin",
	},
	waterfall = {
		build_systems = { "gradle", "maven" },
		generator = "minecraft-dev.generators.plugin",
	},
}

---@return string[]
function M.names()
	local names = vim.tbl_keys(registry)
	table.sort(names)
	return names
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
