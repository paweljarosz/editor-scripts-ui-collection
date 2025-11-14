local string_helper = require "editor_scripts.helpers.string_helper"
local file_helper = require "editor_scripts.helpers.file_helper"
local log_helper = require "editor_scripts.helpers.log_helper"
local gui_resources = require "editor_scripts.gui.resources.gui_resources_helper"

local function ensure_gui_script_file(gui_script_path)
	local ok, normalized_path, created_or_err = gui_resources.ensure_gui_script(gui_script_path)
	if not ok then
		log_helper.error("Unable to create GUI script file at", normalized_path, created_or_err)
		return false
	end

	if created_or_err then
		log_helper.info("Created GUI script at", normalized_path)
	else
		log_helper.info("GUI script already exists at", normalized_path)
	end

	return true
end

local function attach_gui_script_to_gui(normalized_gui_path, gui_script_path)
	-- Read gui file
		local gui_text, error = file_helper.read_all(normalized_gui_path)
		if not gui_text then
			log_helper.error("Unable to read GUI file at", normalized_gui_path, error)
		return false
	end

	-- Replace or add the script reference in the .gui file
	gui_text = string_helper.replace_or_append_property(gui_text, "script", gui_script_path)

	local updated
	updated, error = file_helper.write_all(normalized_gui_path, gui_text)
		if updated then
			log_helper.info("Attached GUI script to", normalized_gui_path)
		else
			log_helper.error("Unable to update GUI file at", normalized_gui_path, error)
	end
end

local function add_gui_script(gui_path)
	local normalized_gui_path = string_helper.path_with_leading_slash(gui_path)
	local gui_script_path = string_helper.replace_extension(normalized_gui_path, ".gui_script")

	if not ensure_gui_script_file(gui_script_path) then
		return
	end

	attach_gui_script_to_gui(normalized_gui_path, gui_script_path)
end

local L = {}

function L.run(selection)
	-- Create GUI scripts for selected gui files
	for _, id in ipairs(selection) do
		local file_path = editor.get(id, "path") or ""
		if file_helper.is_gui_file(file_path) then
			add_gui_script(file_path)
		end
	end
end

return L
