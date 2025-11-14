local string_helper = require "editor_scripts.helpers.string_helper"
local file_helper = require "editor_scripts.helpers.file_helper"
local gui_script_helper = require "editor_scripts.gui.resources.gui_script_helper"
local gui_file_helper = require "editor_scripts.gui.resources.gui_file_helper"

local M = {}

---@param path string|nil
---@return boolean,string,boolean|string
function M.ensure_gui_script(gui_script_path)
	local normalized_path = string_helper.path_with_leading_slash(gui_script_path)
	if normalized_path == "" then
		return false, normalized_path, "Invalid GUI script path"
	end

	if file_helper.file_exists(normalized_path) then
		return true, normalized_path, false
	end

	local created, err = file_helper.write_all(normalized_path, gui_script_helper.default_content())
	if not created then
		return false, normalized_path, err
	end

	return true, normalized_path, true
end

---@param gui_path string|nil
---@param gui_script_path string|nil
---@return boolean,string,boolean|string
function M.ensure_gui_file(gui_path, gui_script_path)
	local normalized_gui_path = string_helper.path_with_leading_slash(gui_path)
	if normalized_gui_path == "" then
		return false, normalized_gui_path, "Invalid GUI path"
	end

	if file_helper.file_exists(normalized_gui_path) then
		return true, normalized_gui_path, false
	end

	local normalized_gui_script_path = string_helper.path_with_leading_slash(gui_script_path)
	if normalized_gui_script_path == "" then
		return false, normalized_gui_path, "Invalid GUI script path"
	end

	local escaped_script_path = string_helper.escape_quotes(normalized_gui_script_path)
	local gui_content = gui_file_helper.build(escaped_script_path)
	local created, err = file_helper.write_all(normalized_gui_path, gui_content)
	if not created then
		return false, normalized_gui_path, err
	end

	return true, normalized_gui_path, true
end

function M.ensure_gui_assets(gui_path, gui_script_path)
	local gui_ok, gui_path_normalized, gui_created_or_err = M.ensure_gui_file(gui_path, gui_script_path)
	if not gui_ok then
		return false, {
			path = gui_path_normalized,
			err = gui_created_or_err
		}
	end

	local script_ok, script_path_normalized, script_created_or_err = M.ensure_gui_script(gui_script_path)
	if not script_ok then
		return false, {
			path = script_path_normalized,
			err = script_created_or_err
		}
	end

	return true, {
		gui = {
			path = gui_path_normalized,
			created = gui_created_or_err
		},
		gui_script = {
			path = script_path_normalized,
			created = script_created_or_err
		}
	}
end

return M
