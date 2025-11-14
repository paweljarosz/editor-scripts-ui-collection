local string_helper = require "editor_scripts.helpers.string_helper"
local file_helper = require "editor_scripts.helpers.file_helper"
local log_helper = require "editor_scripts.helpers.log_helper"
local gui_resources_helper = require "editor_scripts.gui.resources.gui_resources_helper"
local embedded_instance_helper = require "editor_scripts.gui.resources.gui_embedded_instance_helper"

local ui = require "editor_scripts.gui.gui_add_to_collection.gui_add_to_collection_ui"

local function ensure_gui_assets(gui_path, gui_script_path)
	local ok, result = gui_resources_helper.ensure_gui_assets(gui_path, gui_script_path)
	if not ok then
		log_helper.error("Unable to create GUI resources", result.path, result.err)
		return false
	end

	local gui_info = result.gui
	if gui_info.created then
		log_helper.info("Created GUI file at", gui_info.path)
	else
		log_helper.info("GUI already exists at", gui_info.path)
	end

	local script_info = result.gui_script
	if script_info.created then
		log_helper.info("Created GUI script at", script_info.path)
	else
		log_helper.info("GUI script already exists at", script_info.path)
	end

	return true
end

local function append_gui_instance(collection_path, gui_path, go_name)
	local normalized_collection_path = string_helper.path_with_leading_slash(collection_path)
	local normalized_gui_path = string_helper.path_with_leading_slash(gui_path)

	local collection_text, err = file_helper.read_all(normalized_collection_path)
	if not collection_text then
		log_helper.error("Unable to read collection file at", normalized_collection_path, err)
		return false
	end

	local escaped_go_name = string_helper.escape_quotes(go_name or "")
	local escaped_gui_path = string_helper.escape_quotes(normalized_gui_path)
	local new_instance = embedded_instance_helper.build(escaped_go_name, escaped_gui_path)
	local updated_text = collection_text .. "\n" .. new_instance

	local updated, write_err = file_helper.write_all(normalized_collection_path, updated_text)
	if not updated then
		log_helper.error("Unable to update collection file at", normalized_collection_path, write_err)
		return false
	end

	log_helper.info("Game object with GUI added to collection", normalized_collection_path)
	return true
end

local function add_gui_to_collection(collection_path)

	-- Create UI prompt to ask for GUI name
	local normalized_collection_path = string_helper.path_with_leading_slash(collection_path)
	local gui_name = ui.prompt_for_gui_name({ title = "New GUI Name" })
	if not gui_name or gui_name == "" then
		log_helper.info("GUI creation canceled.")
		return
	end

	-- After name is given create proper files and attach to collection
	local base_dir = string_helper.path_dirname(normalized_collection_path)
	local gui_file_name = string_helper.add_extension(gui_name, "gui")
	local gui_script_file_name = string_helper.add_extension(gui_name, "gui_script")

	local gui_path = string_helper.build_resource_path(base_dir, gui_file_name)
	local gui_script_path = string_helper.build_resource_path(base_dir, gui_script_file_name)

	if not ensure_gui_assets(gui_path, gui_script_path) then
		return
	end

	append_gui_instance(normalized_collection_path, gui_path, gui_name)
end

local L = {}

function L.run(selection)
	local collection_path = editor.get(selection, "path")
	if not collection_path then
		log_helper.error("No collection selected.")
		return
	end

	add_gui_to_collection(collection_path)
end

return L
