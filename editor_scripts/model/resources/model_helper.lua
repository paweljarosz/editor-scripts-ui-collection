local string_helper = require "editor_scripts.helpers.string_helper"

local path_with_slash = string_helper.path_with_leading_slash
local escape_quotes = string_helper.escape_quotes

local M = {}

local function format_material_line(fmt, value)
	return string.format(fmt, escape_quotes(value or ""))
end

local function format_boolean_line(fmt, value)
	return string.format(fmt, value and "true" or "false")
end

function M.build_material_block(material)
	local lines = {}
	lines[#lines + 1] = "materials {"
	lines[#lines + 1] = format_material_line("  name: \"%s\"", material and material.display_name or "")
	lines[#lines + 1] = format_material_line("  material: \"%s\"", path_with_slash(material and material.material_path or ""))

	for _, texture in ipairs(material and material.textures or {}) do
		if texture.sampler and texture.texture then
			lines[#lines + 1] = "  textures {"
			lines[#lines + 1] = format_material_line("    sampler: \"%s\"", texture.sampler)
			lines[#lines + 1] = format_material_line("    texture: \"%s\"", path_with_slash(texture.texture))
			lines[#lines + 1] = "  }"
		end
	end

	lines[#lines + 1] = "}"
	return lines
end

function M.build_model_content(entry, material)
	local lines = {}
	lines[#lines + 1] = format_material_line("mesh: \"%s\"", path_with_slash(entry.mesh_path))
	lines[#lines + 1] = format_material_line("name: \"%s\"", entry.display_name or entry.output_name or "")
	lines[#lines + 1] = format_boolean_line("create_go_bones: %s", entry.create_go_bones == true)
	for _, line in ipairs(M.build_material_block(material)) do
		lines[#lines + 1] = line
	end
	lines[#lines + 1] = ""
	return table.concat(lines, "\n")
end

return M
