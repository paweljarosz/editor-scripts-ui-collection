local file_helper = require "editor_scripts.helpers.file_helper"
local string_helper = require "editor_scripts.helpers.string_helper"
local log_helper = require "editor_scripts.helpers.log_helper"
local ui = require "editor_scripts.sound.sound_component.sound_component_ui"

local L = {}

local function build_entry_from_path(path)
	local normalized = string_helper.path_with_leading_slash(path or "")
	if normalized == "" then
		return nil
	end
	local base_dir = string_helper.path_dirname(normalized)
	local base_name = string_helper.path_remove_extension(string_helper.path_basename(normalized))

	return {
		sound_path = normalized,
		output_name = base_name,
		loop = false,
		loopcount = 0,
		group = "master",
		gain = 1.0,
		pan = 0.0,
		speed = 1.0,
		directory = base_dir,
	}
end

local function filter_supported_paths(selection)
	local filtered = {}
	for _, node in ipairs(selection or {}) do
		local path = editor.get(node, "path")
		if path and file_helper.is_sound_file(path) then
			filtered[#filtered + 1] = node
		end
	end
	return filtered
end

local function build_entries_from_selection(selection)
	local entries = {}
	local seen = {}
	for _, node in ipairs(filter_supported_paths(selection)) do
		local path = editor.get(node, "path")
		if path and not seen[path] then
			local entry = build_entry_from_path(path)
			if entry then
				entries[#entries + 1] = entry
				seen[path] = true
			end
		end
	end

	if #entries == 0 then
		entries[1] = {
			sound_path = "",
			output_name = "new_sound",
			loop = false,
			loopcount = 0,
			group = "master",
			gain = 1.0,
			pan = 0.0,
			speed = 1.0,
			directory = "/",
		}
	end

	return entries
end

local function build_sound_content(entry)
	local sound_path = string_helper.path_with_leading_slash(entry.sound_path or "")
	local group = entry.group or "master"
	local gain = tonumber(entry.gain) or 1.0
	local pan = tonumber(entry.pan) or 0.0
	local speed = tonumber(entry.speed) or 1.0
	local loopcount = tonumber(entry.loopcount) or 0

	return string.format([[
sound: "%s"
looping: %d
group: "%s"
gain: %f
pan: %f
speed: %f
loopcount: %d
]], sound_path, entry.loop and 1 or 0, group, gain, pan, speed, loopcount)
end

local function ensure_directory(dir)
	if dir and dir ~= "" and dir ~= "/" then
		file_helper.ensure_directory(dir)
	end
end

local function create_sound_resource(entry)
	local sound_path = string_helper.path_with_leading_slash(entry.sound_path or "")
	if sound_path == "" then
		return false, "Missing source sound path."
	end

	local dir = string_helper.path_dirname(sound_path)
	local name = entry.output_name
	if not name or name == "" then
		name = string_helper.path_remove_extension(string_helper.path_basename(sound_path))
	end
	local file_name = string_helper.add_extension(name, "sound")
	if not dir or dir == "" then
		dir = "/"
	end
	local target_path = dir == "/" and ("/" .. file_name) or (dir .. "/" .. file_name)

	local content = build_sound_content(entry)
	ensure_directory(dir)
	local ok, err = file_helper.write_all(target_path, content)
	if not ok then
		return false, err or "Failed to write file."
	end
	return true
end

local function create_components(entries)
	for _, entry in ipairs(entries or {}) do
		local ok, err = create_sound_resource(entry)
		if not ok then
			log_helper.error("Failed to create sound component", entry.sound_path or "-", err)
			return false
		end
		log_helper.info("Created sound component", entry.sound_path or "-")
	end
	return true
end

function L.run(selection)
	local entries = build_entries_from_selection(selection)
	local confirmed, state = ui.show({
		entries = entries,
	})

	if not confirmed or not state or not state.entries or #state.entries == 0 then
		log_helper.info("Sound component creation canceled.")
		return
	end

	if create_components(state.entries) then
		editor.save()
	end
end

function L.has_sound_selection(selection)
	return file_helper.selection_any(selection, function(path)
		return file_helper.is_sound_file(path)
	end)
end

return L
