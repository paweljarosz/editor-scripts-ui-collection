local ui = editor.ui

local ui_helper = require "editor_scripts.helpers.ui_helper"
local file_helper = require "editor_scripts.helpers.file_helper"
local string_helper = require "editor_scripts.helpers.string_helper"

local M = {}

local MAX_VISIBLE_ROWS = 6
local ROW_HEIGHT = 120

local function clone_entry(entry)
	return {
		sound_path = entry.sound_path or "",
		output_name = entry.output_name or "",
		loop = entry.loop == true,
		loopcount = entry.loopcount or 0,
		group = entry.group or "master",
		gain = entry.gain or 1.0,
		pan = entry.pan or 0.0,
		speed = entry.speed or 1.0,
	}
end

local function clone_entries(entries)
	local list = {}
	for index, entry in ipairs(entries or {}) do
		list[index] = clone_entry(entry)
	end
	return list
end

local function normalize_sound_path(path)
	local normalized = string_helper.path_with_leading_slash(path or "")
	if normalized == "" then
		return ""
	end
	return normalized
end

local function validate_entry(entry)
	local issues = {}
	if not entry.sound_path or entry.sound_path == "" then
		issues.sound_path = "Sound resource is required."
	elseif not file_helper.is_sound_file(entry.sound_path) then
		issues.sound_path = "Select a .wav or .ogg resource."
	end

	local gain = tonumber(entry.gain)
	if not gain or gain < 0 or gain > 1 then
		issues.gain = "Gain must be between 0.0 and 1.0."
	end

	local pan = tonumber(entry.pan)
	if not pan or pan < -1 or pan > 1 then
		issues.pan = "Pan must be between -1.0 and 1.0."
	end

	local speed = tonumber(entry.speed)
	if not speed or speed <= 0 then
		issues.speed = "Speed must be greater than 0."
	end

	local loopcount = tonumber(entry.loopcount)
	if not loopcount or loopcount < 0 then
		issues.loopcount = "Loop count must be zero or positive."
	end

	return issues
end

local function validate_entries(entries)
	local result = {
		ok = true,
		per_entry = {},
	}

	for index, entry in ipairs(entries or {}) do
		local issues = validate_entry(entry)
		if next(issues) then
			result.ok = false
			result.per_entry[index] = issues
		end
	end

	return result
end

local dialog_component = ui.component(function(props)
	local shared_state = props.state or {}
	local entries, set_entries = ui.use_state(clone_entries(shared_state.entries or {}))

	local function commit_entries(next_entries)
		entries = clone_entries(next_entries)
		shared_state.entries = entries
		set_entries(entries)
	end

	local function update_entry(index, changes)
		local next_entries = clone_entries(entries)
		local entry = next_entries[index] or clone_entry({})
		for key, value in pairs(changes) do
			entry[key] = value
		end
		next_entries[index] = entry
		commit_entries(next_entries)
	end

	local function remove_entry(index)
		local next_entries = clone_entries(entries)
		table.remove(next_entries, index)
		if #next_entries == 0 then
			next_entries[1] = clone_entry({})
		end
		commit_entries(next_entries)
	end

	local function add_entry()
		local next_entries = clone_entries(entries)
		next_entries[#next_entries + 1] = clone_entry({})
		commit_entries(next_entries)
	end

	ui_helper.apply_lazy_scroll({
		container = shared_state,
		key = "sound_component_entries",
		list = entries,
		max_visible = MAX_VISIBLE_ROWS,
		clone_item = clone_entry,
		clone_list = clone_entries,
		commit = commit_entries,
	})

	local validation = validate_entries(entries)

	local property_columns = {
		{ grow = true },
		{ grow = true },
		{ grow = true },
		{ grow = true },
		{ grow = true },
		{ grow = true },
	}

	local property_header = ui.grid({
		columns = property_columns,
		spacing = ui.SPACING.LARGE,
		children = {
			{
				ui_helper.label("Loop", { alignment = ui.ALIGNMENT.LEFT }),
				ui_helper.label("Count", { alignment = ui.ALIGNMENT.LEFT }),
				ui_helper.label("Group", { alignment = ui.ALIGNMENT.LEFT }),
				ui_helper.label("Gain", { alignment = ui.ALIGNMENT.LEFT }),
				ui_helper.label("Pan", { alignment = ui.ALIGNMENT.LEFT }),
				ui_helper.label("Speed", { alignment = ui.ALIGNMENT.LEFT }),
			}
		}
	})

	local entry_groups = {}
	for index, entry in ipairs(entries) do
		local issues = (validation.per_entry and validation.per_entry[index]) or {}
		entry_groups[#entry_groups + 1] = ui.vertical({
			spacing = ui.SPACING.MEDIUM,
			padding = ui.PADDING.SMALL,
			children = {
				ui.grid({
					columns = {
						{ grow = false },
						{ grow = true },
						{ grow = false },
					},
					children = {
						{
							ui.label({ text = tostring(index), alignment = ui.ALIGNMENT.LEFT, grow = true }),
							ui.resource_field({
								value = entry.sound_path ~= "" and entry.sound_path or nil,
								extensions = { "wav", "ogg" },
								on_value_changed = function(value)
									update_entry(index, {
										sound_path = normalize_sound_path(value),
										output_name = entry.output_name ~= "" and entry.output_name or string_helper.path_remove_extension(string_helper.path_basename(value or "")),
									})
								end,
								issue = issues.sound_path and {
									severity = ui.ISSUE_SEVERITY.ERROR,
									message = issues.sound_path,
								} or nil,
								grow = true,
							}),
							ui.button({
					icon = ui.ICON.MINUS,
					on_pressed = function()
						remove_entry(index)
					end,
					alignment = ui.ALIGNMENT.RIGHT,
					grow = true,
				}),
						},
					},
				}),
				ui.grid({
					columns = property_columns,
					spacing = ui.SPACING.LARGE,
					children = {
						{
							ui.check_box({
								value = entry.loop == true,
								on_value_changed = function(value)
									update_entry(index, { loop = value })
								end,
								alignment = ui.ALIGNMENT.CENTER,
							}),
							ui.integer_field({
								value = entry.loopcount or 0,
								on_value_changed = function(value)
									update_entry(index, { loopcount = value })
								end,
								issue = issues.loopcount and {
									severity = ui.ISSUE_SEVERITY.ERROR,
									message = issues.loopcount,
								} or nil,
								min = 0,
								alignment = ui.ALIGNMENT.CENTER,
							}),
							ui.string_field({
								value = entry.group or "master",
								on_value_changed = function(value)
									update_entry(index, { group = value })
								end,
								alignment = ui.ALIGNMENT.CENTER,
							}),
							ui.number_field({
								value = entry.gain or 1.0,
								on_value_changed = function(value)
									update_entry(index, { gain = value })
								end,
								issue = issues.gain and {
									severity = ui.ISSUE_SEVERITY.ERROR,
									message = issues.gain,
								} or nil,
								alignment = ui.ALIGNMENT.CENTER,
							}),
							ui.number_field({
								value = entry.pan or 0.0,
								on_value_changed = function(value)
									update_entry(index, { pan = value })
								end,
								issue = issues.pan and {
									severity = ui.ISSUE_SEVERITY.ERROR,
									message = issues.pan,
								} or nil,
								alignment = ui.ALIGNMENT.CENTER,
							}),
							ui.number_field({
								value = entry.speed or 1.0,
								on_value_changed = function(value)
									update_entry(index, { speed = value })
								end,
								issue = issues.speed and {
									severity = ui.ISSUE_SEVERITY.ERROR,
									message = issues.speed,
								} or nil,
								alignment = ui.ALIGNMENT.CENTER,
							}),
						},
					},
				}),
			},
		})
	end

	local entry_list = ui.vertical({
		spacing = ui.SPACING.SMALL,
		children = entry_groups,
	})

	local rows_container = ui.scroll({
		height = (#entries > MAX_VISIBLE_ROWS) and (MAX_VISIBLE_ROWS * ROW_HEIGHT) or nil,
		content = entry_list,
	})

	return ui.dialog({
		title = "Create Sound Components",
		resizable = true,
		content = ui.vertical({
			padding = ui.PADDING.MEDIUM,
			spacing = ui.SPACING.MEDIUM,
			children = {
				property_header,
				ui_helper.separator(),
				rows_container,
				ui.button({
					icon = ui.ICON.PLUS,
					text = "Add Sound",
					on_pressed = add_entry,
					alignment = ui.ALIGNMENT.RIGHT,
				}),
			},
		}),
		buttons = {
			ui.dialog_button({
				text = "Cancel",
				cancel = true,
				result = { action = "cancel" },
			}),
			ui.dialog_button({
				text = "Create Sound Components",
				default = true,
				enabled = validation.ok,
				result = {
					action = "create",
					entries = entries,
				},
			}),
		},
	})
end)

function M.show(opts)
	local state = {
		entries = clone_entries(opts.entries or {}),
	}

	local dialog = dialog_component({
		state = state,
	})
	local result = ui.show_dialog(dialog)
	if result and result.action == "create" then
		return true, { entries = state.entries }
	end
	return false
end

return M
