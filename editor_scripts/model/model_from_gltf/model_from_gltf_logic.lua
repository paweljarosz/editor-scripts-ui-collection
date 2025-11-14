local file_helper = require "editor_scripts.helpers.file_helper"
local string_helper = require "editor_scripts.helpers.string_helper"
local log_helper = require "editor_scripts.helpers.log_helper"
local generator = require "editor_scripts.model.resources.gltf_model_generator"
local ui = require "editor_scripts.model.model_from_gltf.model_from_gltf_ui"

local L = {}

local function extract_gltf_paths(selection)
	local paths = {}
	if type(selection) ~= "table" then
		return paths
	end

	for _, node in ipairs(selection) do
		local ok, path = pcall(editor.get, node, "path")
		if ok and path and file_helper.is_file_extension(path, "gltf") then
			paths[#paths + 1] = string_helper.path_with_leading_slash(path)
		end
	end

	return paths
end

local function show_dialog(initial_paths)
	local entries = generator.create_entries_from_paths(initial_paths)
	return ui.show({
		entries = entries,
		initial_paths = initial_paths,
		default_create_go_bones = false,
	})
end

local function create_models(state)
	local validation = generator.validate(state.entries, state.output_dir, state.material)
	if not validation.ok then
		log_helper.error("Validation failed. Please resolve the issues highlighted in the dialog.")
		return false
	end

	local ok, err = pcall(generator.create_files, state.entries, state.output_dir, state.material)
	if not ok then
		log_helper.error("Failed to create model files", state.output_dir, err)
		return false
	end

	local count = state.entries and #state.entries or 0
	log_helper.info(string.format("Created %d model file(s)", count), state.output_dir)
	return true
end

local function run_with_paths(initial_paths)
	local confirmed, state = show_dialog(initial_paths or {})
	if not confirmed then
		log_helper.info("Model creation canceled.")
		return
	end

	create_models(state)
end

function L.has_gltf_selection(selection)
	return file_helper.selection_any(selection, function(path)
		return file_helper.is_file_extension(path, "gltf")
	end)
end

function L.run_with_selection(selection)
	local paths = extract_gltf_paths(selection)
	if #paths == 0 then
		log_helper.error("Select at least one GLTF resource before running this command.")
		return
	end
	run_with_paths(paths)
end

function L.run_project_command()
	run_with_paths({})
end

return L
