local M = {}
local version_util = require("minecraft-dev.version")

local definitions = {
	paper = {
		repository = "https://repo.papermc.io/repository/maven-public/",
		group = "io.papermc.paper",
		artifact = "paper-api",
	},
	spigot = {
		repository = "https://hub.spigotmc.org/nexus/content/repositories/snapshots/",
		group = "org.spigotmc",
		artifact = "spigot-api",
	},
}

local function definition(platform, minecraft_version)
	local selected = vim.deepcopy(assert(definitions[platform], "unsupported Bukkit platform: " .. tostring(platform)))
	if platform == "paper" and not version_util.at_least(minecraft_version, 1, 17) then
		selected.group = "com.destroystokyo.paper"
	end
	return selected
end

local function replace_repositories(content, repository)
	content = content:gsub("https://repo%.papermc%.io/repository/maven%-public/", repository)
	content = content:gsub("https://hub%.spigotmc%.org/nexus/content/repositories/snapshots/", repository)
	return content
end

---@param content string
---@param platform string
---@param minecraft_version string
---@return string
function M.transform_gradle(content, platform, minecraft_version)
	local selected = definition(platform, minecraft_version)
	content = replace_repositories(content, selected.repository)
	content = content:gsub("io%.papermc%.paper:paper%-api", selected.group .. ":" .. selected.artifact)
	content = content:gsub("com%.destroystokyo%.paper:paper%-api", selected.group .. ":" .. selected.artifact)
	content = content:gsub("org%.spigotmc:spigot%-api", selected.group .. ":" .. selected.artifact)
	return content
end

---@param content string
---@param platform string
---@param minecraft_version string
---@return string
function M.transform_maven(content, platform, minecraft_version)
	local selected = definition(platform, minecraft_version)
	content = replace_repositories(content, selected.repository)
	for _, group in ipairs({ "io.papermc.paper", "com.destroystokyo.paper", "org.spigotmc" }) do
		content = content:gsub(
			"<groupId>" .. group:gsub("%.", "%%.") .. "</groupId>(%s*)<artifactId>[%w%-]+%-api</artifactId>",
			"<groupId>" .. selected.group .. "</groupId>%1<artifactId>" .. selected.artifact .. "</artifactId>"
		)
	end
	return content
end

local function quote(value)
	return vim.json.encode(value)
end

local function append_optional(lines, key, value)
	if type(value) == "string" and value ~= "" then
		table.insert(lines, key .. ": " .. quote(value))
	elseif type(value) == "table" and #value > 0 then
		table.insert(lines, key .. ": " .. vim.json.encode(value))
	end
end

local function append_paper_dependencies(lines, spec)
	local dependencies = {}
	for _, name in ipairs(spec.depend or {}) do
		table.insert(dependencies, { name = name, load = "BEFORE", required = true, join_classpath = true })
	end
	for _, name in ipairs(spec.soft_depend or {}) do
		table.insert(dependencies, { name = name, load = "BEFORE", required = false, join_classpath = true })
	end
	for _, name in ipairs(spec.load_before or {}) do
		table.insert(dependencies, { name = name, load = "AFTER", required = false, join_classpath = false })
	end
	if #dependencies == 0 then
		return
	end

	table.insert(lines, "dependencies:")
	table.insert(lines, "  server:")
	for _, dependency in ipairs(dependencies) do
		table.insert(lines, "    " .. quote(dependency.name) .. ":")
		table.insert(lines, "      load: " .. dependency.load)
		table.insert(lines, "      required: " .. tostring(dependency.required))
		table.insert(lines, "      join-classpath: " .. tostring(dependency.join_classpath))
	end
end

---@param ctx ProjectContext
---@param spec? table
---@return string
function M.build_manifest(ctx, spec)
	spec = spec or {}
	local lines = {
		"name: " .. quote(spec.plugin_name or ctx.artifactId),
		"main: " .. quote(ctx.package .. "." .. ctx.main),
		"version: " .. quote(spec.plugin_version or "1.0.0"),
	}

	if version_util.resolve_family(ctx.version) == "v1_13_plus" then
		local api_version = ctx.version:match("^(%d+%.%d+)")
		if api_version then
			table.insert(lines, "api-version: " .. quote(api_version))
		end
	end
	append_optional(lines, "description", spec.description)
	append_optional(lines, "authors", spec.authors)
	append_optional(lines, "website", spec.website)
	if spec.platform == "paper" and spec.paper_manifest then
		append_paper_dependencies(lines, spec)
		return table.concat(lines, "\n") .. "\n"
	end
	append_optional(lines, "prefix", spec.prefix)
	if spec.load and spec.load ~= "POSTWORLD" then
		append_optional(lines, "load", spec.load)
	end
	append_optional(lines, "loadbefore", spec.load_before)
	append_optional(lines, "depend", spec.depend)
	append_optional(lines, "softdepend", spec.soft_depend)
	return table.concat(lines, "\n") .. "\n"
end

---@param spec? table
---@return string
function M.manifest_name(spec)
	if spec and spec.platform == "paper" and spec.paper_manifest then
		return "paper-plugin.yml"
	end
	return "plugin.yml"
end

return M
