local ui = editor.ui

local ui_helper = require "editor_scripts.helpers.ui_helper"
local generator = require "editor_scripts.model.resources.gltf_model_generator"
local string_helper = require "editor_scripts.helpers.string_helper"

local M = {}

local texture_extensions = { "png", "jpg", "jpeg" }
local MAX_VISIBLE_ENTRY_COUNT = 10 -- cap entries rendered before scroll is ready
local ENTRY_ROW_HEIGHT_PX = 42 -- approx height of a resource row, used to cap the scroll area
local MAX_PICKER_VISIBLE_COUNT = MAX_VISIBLE_ENTRY_COUNT

local normalize_directory_path = string_helper.normalize_directory_path

local function safe_resource_attributes(path)
    if not path or path == "" then
        return nil
    end
    local ok, attrs = pcall(editor.resource_attributes, path)
    if not ok then
        return nil
    end
    return attrs
end

local function directory_status_issue(path)
    path = normalize_directory_path(path)
    if path == "" or path == "/" then
        return nil
    end
    local attrs = safe_resource_attributes(path)
    if not attrs or not attrs.exists then
        return {
            severity = ui.ISSUE_SEVERITY.WARNING,
            message = "Folder does not exist yet; it will be created when generating models.",
        }
    end
    if not attrs.is_directory then
        return {
            severity = ui.ISSUE_SEVERITY.ERROR,
            message = "Resource exists but is not a folder.",
        }
    end
    return nil
end

local function collect_child_directories(path, accumulator, visited)
    local ok, children = pcall(editor.get, path, "children")
    if not ok or not children then
        return false
    end
    for _, child in ipairs(children) do
        local ok_path, child_path = pcall(editor.get, child, "path")
        if ok_path and child_path then
            local attrs = safe_resource_attributes(child_path)
            if attrs and attrs.is_directory and not visited[child_path] then
                visited[child_path] = true
                accumulator[#accumulator + 1] = child_path
                collect_child_directories(child_path, accumulator, visited)
            end
        end
    end
    return true
end

local function collect_project_directories()
    local directories = { "/" }
    local visited = { ["/"] = true }
    if not collect_child_directories("/", directories, visited) then
        collect_child_directories("", directories, visited)
    end
    table.sort(directories, function(a, b)
        if a == b then
            return false
        elseif a == "/" then
            return true
        elseif b == "/" then
            return false
        end
        return a < b
    end)
    return directories
end

local function collect_gltf_resources()
    local resources = {}
    local visited = {}

    local function visit(path)
        local ok, children = pcall(editor.get, path, "children")
        if not ok or not children then
            return false
        end
        for _, child in ipairs(children) do
            local ok_path, child_path = pcall(editor.get, child, "path")
            if ok_path and child_path and not visited[child_path] then
                visited[child_path] = true
                local attrs = safe_resource_attributes(child_path)
                if attrs and attrs.is_directory then
                    visit(child_path)
                else
                    if child_path:match("%.gltf$") then
                        resources[#resources + 1] = child_path
                    end
                end
            end
        end
        return true
    end

    if not visit("/") then
        visit("")
    end

    table.sort(resources)
    return resources
end

local function clone_entry(entry)
	return {
		mesh_path = entry.mesh_path or "",
		display_name = entry.display_name or "",
		output_name = entry.output_name or "",
		create_go_bones = entry.create_go_bones == true,
	}
end

local function clone_entries(entries)
    local copy = {}
    for index, entry in ipairs(entries or {}) do
        copy[index] = clone_entry(entry)
    end
    return copy
end

local function clone_string_list(list)
    local copy = {}
    for index, value in ipairs(list or {}) do
        copy[index] = value
    end
    return copy
end

local function build_selected_list(selection_map, ordered_paths, disabled_lookup)
    local selected = {}
    if not selection_map or not ordered_paths then
        return selected
    end
    for _, path in ipairs(ordered_paths) do
        if selection_map[path] and not (disabled_lookup and disabled_lookup[path]) then
            selected[#selected + 1] = path
        end
    end
    return selected
end

local function count_selected(selection_map, ordered_paths, disabled_lookup)
    if not selection_map or not ordered_paths then
        return 0
    end
    local count = 0
    for _, path in ipairs(ordered_paths) do
        if selection_map[path] and not (disabled_lookup and disabled_lookup[path]) then
            count = count + 1
        end
    end
    return count
end

local gltf_picker_dialog = ui.component(function(props)
    local gltf_paths = props.paths or {}
    local disabled = props.disabled or {}
    local state = props.state or {}
    state.selection_map = state.selection_map or {}

    local redraw_token, set_redraw_token = ui.use_state(0)
    local display_paths, set_display_paths = ui.use_state(function()
        return clone_string_list(gltf_paths)
    end)
    state.display_paths = display_paths

    local function commit_display_paths(next_paths)
        state.display_paths = next_paths
        display_paths = next_paths
        set_display_paths(next_paths)
    end

    ui_helper.apply_lazy_scroll({
        container = state,
        key = "gltf_picker_paths",
        list = display_paths,
        max_visible = MAX_PICKER_VISIBLE_COUNT,
        clone_item = function(path)
            return path
        end,
        clone_list = clone_string_list,
        commit = commit_display_paths,
    })

    local available_lookup = {}
    for _, path in ipairs(gltf_paths) do
        available_lookup[path] = true
    end
    for path in pairs(state.selection_map) do
        if not available_lookup[path] or disabled[path] then
            state.selection_map[path] = nil
        end
    end

    local function bump_redraw()
        set_redraw_token(redraw_token + 1)
    end

    local function toggle_path(path, checked)
        if disabled[path] then
            return
        end
        if checked then
            state.selection_map[path] = true
        else
            state.selection_map[path] = nil
        end
        bump_redraw()
    end

    local function set_all(value)
        for _, path in ipairs(gltf_paths) do
            if not disabled[path] then
                if value then
                    state.selection_map[path] = true
                else
                    state.selection_map[path] = nil
                end
            end
        end
        bump_redraw()
    end

    local selectable_total = 0
    for _, path in ipairs(gltf_paths) do
        if not disabled[path] then
            selectable_total = selectable_total + 1
        end
    end

    local selected_count = count_selected(state.selection_map, gltf_paths, disabled)

    local list_items = {}
    if #gltf_paths == 0 then
        list_items[1] = ui.label({
            text = "No GLTF resources (.gltf) were found in this project.",
            alignment = ui.ALIGNMENT.LEFT,
            word_wrap = true,
        })
    else
        for index, path in ipairs(display_paths) do
            local already_added = disabled[path]
            local label_text = already_added and (path .. " (already added)") or path
            list_items[index] = ui.horizontal({
                spacing = ui.SPACING.SMALL,
                children = {
                    ui.check_box({
                        value = state.selection_map[path] == true,
                        enabled = not already_added,
                        on_value_changed = function(value)
                            toggle_path(path, value)
                        end,
                    }),
                    ui.label({
                        text = label_text,
                        alignment = ui.ALIGNMENT.LEFT,
                        grow = true,
                    }),
                },
            })
        end
    end

    local selection_actions = nil
    if #gltf_paths > 0 and selectable_total > 0 then
        selection_actions = ui.horizontal({
            spacing = ui.SPACING.SMALL,
            alignment = ui.ALIGNMENT.RIGHT,
            children = {
                ui.button({
                    text = "Select All",
                    enabled = selected_count < selectable_total,
                    on_pressed = function()
                        set_all(true)
                    end,
                }),
                ui.button({
                    text = "Clear",
                    enabled = selected_count > 0,
                    on_pressed = function()
                        set_all(false)
                    end,
                }),
            },
        })
    end

    local add_label = "Add Selected"
    if selected_count > 0 then
        if selected_count == 1 then
            add_label = "Add 1 File"
        else
            add_label = string.format("Add %d Files", selected_count)
        end
    end

    return ui.dialog({
        title = "Select GLTF Files",
        content = ui.vertical({
            padding = ui.PADDING.MEDIUM,
            spacing = ui.SPACING.MEDIUM,
            children = {
                ui.label({
                    text = #gltf_paths == 0 and "Add GLTF files to the project to enable multi-selection." or "Pick the GLTF resources you want to add to the generator.",
                    alignment = ui.ALIGNMENT.LEFT,
                    word_wrap = true,
                }),
                selection_actions,
                ui.scroll({
                    grow = true,
                    content = ui.vertical({
                        spacing = ui.SPACING.SMALL,
                        padding = ui.PADDING.SMALL,
                        children = list_items,
                    }),
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
                text = add_label,
                default = true,
                enabled = selected_count > 0,
                result = {
                    action = "add",
                    paths = build_selected_list(state.selection_map, gltf_paths, disabled),
                },
            }),
        },
    })
end)

local directory_picker_dialog = ui.component(function(props)
    local directories = props.directories or {}
    local state = props.state or {}
    local initial = state.selected or directories[1] or "/"
    local selected, set_selected = ui.use_state(initial)
    state.selected = selected

    local function on_value_changed(value)
        if value == nil then
            return
        end
        state.selected = value
        set_selected(value)
    end

    local selector = nil
    if #directories == 0 then
        selector = ui.label({
            text = "No folders found. Create a directory first.",
            alignment = ui.ALIGNMENT.LEFT,
            grow = true,
            word_wrap = true,
        })
    else
        selector = ui.select_box({
            options = directories,
            value = selected,
            on_value_changed = on_value_changed,
            grow = true,
            alignment = ui.ALIGNMENT.LEFT,
        })
    end

    return ui.dialog({
        title = props.title or "Select Directory",
        content = ui.vertical({
            padding = ui.PADDING.MEDIUM,
            spacing = ui.SPACING.MEDIUM,
            children = {
                ui.label({
                    text = props.description or "Choose an existing folder inside the project.",
                    alignment = ui.ALIGNMENT.LEFT,
                    word_wrap = true,
                }),
                selector,
            },
        }),
        buttons = {
            ui.dialog_button({
                text = "Cancel",
                cancel = true,
                result = { action = "cancel" },
            }),
            ui.dialog_button({
                text = "Use Folder",
                default = true,
                enabled = #directories > 0,
                result = {
                    action = "select",
                    directory = selected or directories[1] or initial or "/",
                },
            }),
        },
    })
end)

local function show_directory_picker(current_dir)
    local directories = collect_project_directories()
    current_dir = normalize_directory_path(current_dir)
    if current_dir ~= "" then
        local found = false
        for _, dir in ipairs(directories) do
            if dir == current_dir then
                found = true
                break
            end
        end
        if not found then
            directories[#directories + 1] = current_dir
        end
    end
    table.sort(directories, function(a, b)
        if a == b then
            return false
        elseif a == "/" then
            return true
        elseif b == "/" then
            return false
        end
        return a < b
    end)
    local initial = current_dir ~= "" and current_dir or directories[1] or "/"
    local state = { selected = initial }
    local dialog = directory_picker_dialog({
        directories = directories,
        state = state,
        title = "Select Output Directory",
        description = "Pick an existing folder inside the project.",
    })
    local result = ui.show_dialog(dialog)
    if result and result.action == "select" then
        return result.directory or state.selected
    end
    return nil
end

local function optional_resource(path)
    if path == nil or path == "" then
        return nil
    end
    return path
end

local function build_issue(message)
    if not message or message == "" then
        return nil
    end
    return {
        severity = ui.ISSUE_SEVERITY.ERROR,
        message = message,
    }
end

local function texture_issue(issues, index, field)
    if not issues or not issues[index] then
        return nil
    end
    return build_issue(issues[index][field])
end

local function entry_issue(issues, index, field)
    if not issues or not issues[index] then
        return nil
    end
    return build_issue(issues[index][field])
end

local function material_issue(issues, field)
    if not issues then
        return nil
    end
    return build_issue(issues[field])
end

local function general_issue_list(messages)
    if not messages or #messages == 0 then
        return nil
    end
    local children = {}
    for index, text in ipairs(messages) do
        children[index] = ui.label({
            text = "- " .. text,
            alignment = ui.ALIGNMENT.LEFT,
        })
    end
    return ui.vertical({
        spacing = ui.SPACING.SMALL,
        padding = ui.PADDING.SMALL,
        children = children,
    })
end

local function merge_issue(base_issue, extra_message)
    if not extra_message or extra_message == "" then
        return base_issue
    end
    if base_issue then
        return {
            severity = base_issue.severity or ui.ISSUE_SEVERITY.ERROR,
            message = base_issue.message .. " " .. extra_message,
        }
    end
    return build_issue(extra_message)
end

local function derive_primary_material_name(entries, analysis_cache)
    analysis_cache = analysis_cache or {}
    for _, entry in ipairs(entries or {}) do
        local mesh_path = entry.mesh_path
        if mesh_path and mesh_path ~= "" then
            local cached = analysis_cache[mesh_path]
            if cached == nil then
                local analysis = generator.inspect_gltf(mesh_path)
                analysis_cache[mesh_path] = analysis or false
                cached = analysis_cache[mesh_path]
            end
            if cached and cached ~= false then
                local name = cached.primary_material_name
                if name and name ~= "" then
                    return name
                end
            end
        end
    end
    return nil
end

local dialog_component = ui.component(function(props)
    local shared_state = props.state

    shared_state.output_dir = normalize_directory_path(shared_state.output_dir or "/kay_assets")

    local entries, set_entries = ui.use_state(function()
        return clone_entries(shared_state.entries or {})
    end)
    local material, set_material = ui.use_state(generator.clone_material(shared_state.material))
    local output_dir, set_output_dir = ui.use_state(shared_state.output_dir)
    local texture_suggestions, set_texture_suggestions = ui.use_state(shared_state.texture_suggestions or {})
   local samplers, set_samplers = ui.use_state(shared_state.samplers or generator.samplers_from_textures(material.textures))
   shared_state.analysis_cache = shared_state.analysis_cache or {}
   shared_state.material_name_manual = shared_state.material_name_manual or false
   shared_state.scroll_initialized = shared_state.scroll_initialized or false
    shared_state.add_many_state = shared_state.add_many_state or {}
    if shared_state.default_create_go_bones == nil then
        shared_state.default_create_go_bones = false
    end

    local function set_texture_suggestions_state(values)
        shared_state.texture_suggestions = values
        texture_suggestions = values
        set_texture_suggestions(values)
    end

    local function set_samplers_state(values)
        shared_state.samplers = values
        samplers = values
        set_samplers(values)
    end

    local function commit_entries(new_entries)
        shared_state.entries = new_entries
        entries = new_entries
        set_entries(new_entries)
    end

    if not shared_state.scroll_initialized then
        shared_state.scroll_initialized = true
        commit_entries(clone_entries(entries))
    end

    local function commit_output_dir(new_dir)
        local normalized = normalize_directory_path(new_dir)
        shared_state.output_dir = normalized
        output_dir = normalized
        set_output_dir(normalized)
    end

    local function ensure_analysis(mesh_path)
        if not mesh_path or mesh_path == "" then
            return nil
        end
        local cache = shared_state.analysis_cache
        local cached = cache[mesh_path]
        if cached == nil then
            local analysis = generator.inspect_gltf(mesh_path)
            cache[mesh_path] = analysis or false
            cached = cache[mesh_path]
        end
        if cached == false then
            return nil
        end
        return cached
    end

    local function update_material(changes, opts)
        opts = opts or {}
        local next_material = generator.clone_material(material)
        for key, value in pairs(changes) do
            next_material[key] = value
        end
        if opts.manual and changes.display_name ~= nil then
            shared_state.material_name_manual = true
        end
        shared_state.material = next_material
        set_material(next_material)
        material = next_material
    end

    local function refresh_inferred_defaults(current_entries)
        local first_material_name = nil
        local suggestions = {}
        local seen = {}
        for _, entry in ipairs(current_entries) do
            local analysis = ensure_analysis(entry.mesh_path)
            if analysis then
                if not first_material_name and analysis.primary_material_name then
                    first_material_name = analysis.primary_material_name
                end
                for _, image_path in ipairs(analysis.image_paths or {}) do
                    if not seen[image_path] then
                        seen[image_path] = true
                        suggestions[#suggestions + 1] = image_path
                    end
                end
            end
        end
        if first_material_name and not shared_state.material_name_manual then
            update_material({ display_name = first_material_name })
        end
        set_texture_suggestions_state(suggestions)
        update_material({
            textures = generator.align_textures(samplers, material.textures, suggestions),
        })
    end

    ui_helper.apply_lazy_scroll({
        container = shared_state,
        key = "gltf_entries",
        list = entries,
        max_visible = MAX_VISIBLE_ENTRY_COUNT,
        clone_item = clone_entry,
        clone_list = clone_entries,
        commit = commit_entries,
        on_flush = refresh_inferred_defaults,
    })

    local function new_entry_template()
        return {
            mesh_path = "",
            display_name = "",
            output_name = "",
            create_go_bones = shared_state.default_create_go_bones == true,
        }
    end

    local function update_entry(index, changes)
        local next_entries = clone_entries(entries)
        local entry = next_entries[index] or new_entry_template()
        if entry.create_go_bones == nil then
            entry.create_go_bones = shared_state.default_create_go_bones == true
        end
        for key, value in pairs(changes) do
            entry[key] = value
        end
        next_entries[index] = entry
        commit_entries(next_entries)
        if changes.mesh_path ~= nil then
            refresh_inferred_defaults(next_entries)
        end
    end

    local function remove_entry(index)
        local next_entries = clone_entries(entries)
        table.remove(next_entries, index)
        if #next_entries == 0 then
            next_entries[1] = new_entry_template()
        end
        commit_entries(next_entries)
        refresh_inferred_defaults(next_entries)
    end

    local function is_blank_entry(entry)
        if not entry then
            return true
        end
        local mesh_empty = not entry.mesh_path or entry.mesh_path == ""
        local display_empty = not entry.display_name or entry.display_name == ""
        local output_empty = not entry.output_name or entry.output_name == ""
        return mesh_empty and display_empty and output_empty
    end

    local function add_entry()
        local next_entries = clone_entries(entries)
        next_entries[#next_entries + 1] = new_entry_template()
        commit_entries(next_entries)
        refresh_inferred_defaults(next_entries)
    end

    local function add_many()
        local gltf_paths = collect_gltf_resources()
        local existing = {}
        for _, entry in ipairs(entries) do
            if entry.mesh_path and entry.mesh_path ~= "" then
                existing[entry.mesh_path] = true
            end
        end

        local picker_state = shared_state.add_many_state
        picker_state.selection_map = picker_state.selection_map or {}
        ui_helper.reset_lazy_scroll(picker_state, "gltf_picker_paths")

        local dialog = gltf_picker_dialog({
            paths = gltf_paths,
            disabled = existing,
            state = picker_state,
        })
        local result = ui.show_dialog(dialog)
        if not result or result.action ~= "add" then
            return
        end

        local selected_paths = result.paths or {}
        if #selected_paths == 0 then
            return
        end

        local defaults = generator.create_entries_from_paths(selected_paths)
        local desired_go_bones = shared_state.default_create_go_bones == true
        for _, entry in ipairs(defaults) do
            entry.create_go_bones = desired_go_bones
        end
        if #defaults == 0 then
            return
        end

        local next_entries = clone_entries(entries)
        local existing_map = {}
        for _, entry in ipairs(next_entries) do
            if entry.mesh_path and entry.mesh_path ~= "" then
                existing_map[entry.mesh_path] = true
            end
        end

        local changed = false
        for _, default_entry in ipairs(defaults) do
            local mesh_path = default_entry.mesh_path
            if mesh_path and mesh_path ~= "" and not existing_map[mesh_path] then
                local inserted = false
                for index, entry in ipairs(next_entries) do
                    if is_blank_entry(entry) then
                        next_entries[index] = {
                            mesh_path = mesh_path,
                            display_name = default_entry.display_name,
                            output_name = default_entry.output_name,
                            create_go_bones = desired_go_bones,
                        }
                        inserted = true
                        break
                    end
                end
                if not inserted then
                    next_entries[#next_entries + 1] = {
                        mesh_path = mesh_path,
                        display_name = default_entry.display_name,
                        output_name = default_entry.output_name,
                        create_go_bones = desired_go_bones,
                    }
                end
                existing_map[mesh_path] = true
                changed = true
            end
            picker_state.selection_map[mesh_path] = nil
        end

        if changed then
            commit_entries(next_entries)
            refresh_inferred_defaults(next_entries)
        end
    end

    local function set_all_go_bones(value)
        shared_state.default_create_go_bones = value == true
        local next_entries = clone_entries(entries)
        for index, entry in ipairs(next_entries) do
            entry.create_go_bones = value == true
        end
        commit_entries(next_entries)
    end

    local function are_all_go_bones_enabled(list)
        if not list or #list == 0 then
            return shared_state.default_create_go_bones == true
        end
        for _, entry in ipairs(list) do
            if entry.create_go_bones ~= true then
                return false
            end
        end
        return true
    end

    local function normalize_mesh_selection(selection)
        if type(selection) == "table" then
            local result = {}
            local function append_paths(source)
                if type(source) ~= "table" then
                    return
                end
                for _, path in ipairs(source) do
                    if type(path) == "string" and path ~= "" then
                        result[#result + 1] = path
                    end
                end
            end
            append_paths(selection.paths)
            append_paths(selection.values)
            if type(selection.value) == "string" and selection.value ~= "" then
                result[#result + 1] = selection.value
            end
            if #result > 0 then
                return result
            end
            if #selection > 0 then
                append_paths(selection)
            end
            return result
        elseif type(selection) == "string" and selection ~= "" then
            return { selection }
        end
        return {}
    end

    local function apply_mesh_selection(index, selection)
        local selected_paths = normalize_mesh_selection(selection)
        if #selected_paths == 0 then
            local cleared = type(selection) == "string" and selection or ""
            update_entry(index, {
                mesh_path = cleared,
            })
            return
        end

        local defaults = generator.create_entries_from_paths(selected_paths)
        local desired_go_bones = shared_state.default_create_go_bones == true
        for _, default_entry in ipairs(defaults) do
            default_entry.create_go_bones = desired_go_bones
        end
        if #defaults == 0 then
            update_entry(index, { mesh_path = "" })
            return
        end

        local next_entries = clone_entries(entries)
        local target = next_entries[index] or new_entry_template()
        local first_defaults = defaults[1]
        target.mesh_path = first_defaults.mesh_path
        if not target.display_name or target.display_name == "" then
            target.display_name = first_defaults.display_name
        end
        if not target.output_name or target.output_name == "" then
            target.output_name = first_defaults.output_name
        end
        next_entries[index] = target

        local insert_position = index + 1
        for i = 2, #defaults do
            table.insert(next_entries, insert_position, defaults[i])
            insert_position = insert_position + 1
        end

        commit_entries(next_entries)
        refresh_inferred_defaults(next_entries)
    end

    local function update_texture(index, changes, opts)
        opts = opts or {}
        local next_textures = generator.clone_textures(material.textures)
        next_textures[index] = next_textures[index] or { sampler = samplers[index] or ("tex" .. index), texture = "" }
        for key, value in pairs(changes) do
            next_textures[index][key] = value
        end
        update_material({ textures = next_textures }, opts)
    end

    local function apply_material_resource(value)
        local info = generator.read_material_info(value)
        local sampler_list = info.samplers or {}
        if #sampler_list == 0 then
            sampler_list = generator.samplers_from_textures(material.textures)
        end
        set_samplers_state(sampler_list)
        local changes = {
            material_path = value,
            textures = generator.align_textures(sampler_list, material.textures, texture_suggestions),
        }
        local can_autofill = generator.should_autofill_material_name(material.display_name)
        if info.display_name and not shared_state.material_name_manual and can_autofill then
            changes.display_name = info.display_name
        end
        update_material(changes)
    end

    local validation = generator.validate(entries, output_dir, material)

    local analysis_by_entry = {}
    local entry_conflicts = {}
    local unique_material_names = {}
    local material_name_order = {}
    local base_gltf_material_name = nil
    for index, entry in ipairs(entries) do
        local analysis = ensure_analysis(entry.mesh_path)
        analysis_by_entry[index] = analysis
        local gltf_material_name = analysis and analysis.primary_material_name or nil
        if gltf_material_name and gltf_material_name ~= "" then
            if not unique_material_names[gltf_material_name] then
                unique_material_names[gltf_material_name] = true
                material_name_order[#material_name_order + 1] = gltf_material_name
            end
            if not base_gltf_material_name then
                base_gltf_material_name = gltf_material_name
            elseif gltf_material_name ~= base_gltf_material_name then
                entry_conflicts[index] = string.format("GLTF material \"%s\" conflicts with \"%s\".", gltf_material_name, base_gltf_material_name)
            end
        end
    end

    local entry_cards = {}
    for index, entry in ipairs(entries) do
        local target_path = generator.target_path(output_dir, entry.output_name or "")
        local analysis = analysis_by_entry[index]
        local gltf_material_name = analysis and analysis.primary_material_name or ""
        local mesh_issue = merge_issue(entry_issue(validation.entries, index, "mesh_path"), entry_conflicts[index])

        entry_cards[index] = ui.vertical({
            padding = ui.PADDING.NONE,
            spacing = ui.SPACING.LARGE,
            grow = false,
            children = {
                ui.vertical({
                    spacing = ui.SPACING.LARGE,
                    padding = ui.PADDING.NONE,
                    children = {
                        ui.horizontal({
                            spacing = ui.SPACING.LARGE,
                            children = {
                                ui.label({
                                    text = string.format("%d", index),
                                    alignment = ui.ALIGNMENT.LEFT,
                                }),
                                ui.resource_field({
                                    value = optional_resource(entry.mesh_path),
                                    extensions = { "gltf" },
                                    on_value_changed = function(value)
                                        apply_mesh_selection(index, value)
                                    end,
                                    issue = mesh_issue,
                                    alignment = ui.ALIGNMENT.CENTER,
                                    grow = true,
                                }),
                                ui.check_box({
                                    value = entry.create_go_bones == true,
                                    alignment = ui.ALIGNMENT.CENTER,
                                    on_value_changed = function(value)
                                        update_entry(index, { create_go_bones = value })
                                    end,
                                }),
                                ui.button({
                                    icon = ui.ICON.MINUS,
                                    alignment = ui.ALIGNMENT.CENTER,
                                    on_pressed = function()
                                        remove_entry(index)
                                    end,
                                }),
                            },
                        }),
                    },
                }),
            },
        })
    end
    local entry_list_height = nil
    if #entry_cards > MAX_VISIBLE_ENTRY_COUNT then
        entry_list_height = MAX_VISIBLE_ENTRY_COUNT * ENTRY_ROW_HEIGHT_PX
    end
    local texture_rows = {}
    for index, sampler_name in ipairs(samplers) do
        local texture = material.textures[index] or { texture = "" }
        texture_rows[index] = ui.horizontal({
            spacing = ui.SPACING.SMALL,
            children = {
                ui.label({
                    text = sampler_name,
                    alignment = ui.ALIGNMENT.LEFT,
                }),
                ui.resource_field({
                    value = optional_resource(texture.texture),
                    on_value_changed = function(value)
                        update_texture(index, { texture = value }, { manual = true })
                    end,
                    extensions = texture_extensions,
                    issue = texture_issue(validation.textures, index, "texture"),
                    grow = true,
                }),
            },
        })
    end
    if #texture_rows == 0 then
        texture_rows[1] = ui.label({
            text = "Select a material resource to load sampler textures.",
            alignment = ui.ALIGNMENT.LEFT,
        })
    end

    local material_section = ui.vertical({
        spacing = ui.SPACING.MEDIUM,
        padding = ui.PADDING.SMALL,
        children = {
            ui_helper.heading("Material"),
            ui.horizontal({
                spacing = ui.SPACING.SMALL,
                children = {
                    ui.label({ text = "Path:"}),
                    ui.resource_field({
                        value = optional_resource(material.material_path),
                        extensions = { "material" },
                        on_value_changed = function(value)
                            apply_material_resource(value)
                        end,
                        issue = material_issue(validation.material, "material_path"),
                        grow = true,
                    }),
                },
            }),
            ui.label({
                text = "Textures for samplers required by this material:",
                alignment = ui.ALIGNMENT.LEFT,
            }),
            ui.vertical({
                spacing = ui.SPACING.SMALL,
                children = texture_rows,
            }),
            validation.material.textures and ui.label({
                text = validation.material.textures,
                alignment = ui.ALIGNMENT.LEFT,
            }) or nil,
        },
    })

    local all_go_bones_enabled = are_all_go_bones_enabled(entries)
    local toggle_label = all_go_bones_enabled and "Mark All Create GO Bones Disabled" or "Mark All Create GO Bones Enabled"

    local entries_section = ui.vertical({
        spacing = ui.SPACING.MEDIUM,
        padding = ui.PADDING.MEDIUM,
        children = {
            ui_helper.heading("GLTF Files"),
            ui.scroll({
                grow = true,
                height = entry_list_height,
                content = ui.vertical({
                    padding = ui.PADDING.SMALL,
                    spacing = ui.SPACING.MEDIUM,
                    children = entry_cards,
                }),
            }),
            ui.horizontal({
                spacing = ui.SPACING.MEDIUM,
                alignment = ui.ALIGNMENT.LEFT,
                children = {
                    ui_helper.labeled_checkbox({
                        label = toggle_label,
                        value = all_go_bones_enabled,
                        on_value_changed = function(value)
                            set_all_go_bones(value)
                        end,
                        grow = true,
                    }),
                    ui.horizontal({
                        spacing = ui.SPACING.MEDIUM,
                        alignment = ui.ALIGNMENT.RIGHT,
                        children = {
                            ui.button({
                                icon = ui.ICON.PLUS,
                                text = "Add Many",
                                alignment = ui.ALIGNMENT.RIGHT,
                                on_pressed = add_many,
                            }),
                            ui.button({
                                icon = ui.ICON.PLUS,
                                text = "Add",
                                alignment = ui.ALIGNMENT.RIGHT,
                                on_pressed = add_entry,
                            }),
                        }
                    }),
                }
            })
        },
    })

    local general_messages = {}
    for _, msg in ipairs(validation.general or {}) do
        general_messages[#general_messages + 1] = msg
    end
    if #material_name_order > 1 then
        general_messages[#general_messages + 1] = "Selected GLTF files use different material names: " .. table.concat(material_name_order, ", ")
    end
    local issues_section = general_issue_list(general_messages)

    local output_issue = build_issue(validation.output_dir) or directory_status_issue(output_dir)

    local output_section = ui.vertical({
        padding = ui.PADDING.SMALL,
        children = {
            ui_helper.heading("Output"),
            ui.horizontal({
                spacing = ui.SPACING.LARGE,
                alignment = ui.ALIGNMENT.LEFT,
                children = {
                    ui.label({ text = "Directory where all models will be created: " }),
                    ui.horizontal({
                        grow = true,
                        spacing = ui.SPACING.SMALL,
                        children = {
                            ui.string_field({
                                text = output_dir or "",
                                on_value_changed = commit_output_dir,
                                issue = output_issue,
                                grow = true,
                            })
                        },
                    }),
                },
            })
        },
    })

    local grid_rows = {}
    local row_defs = {}

    local function append_row(component, opts)
        if not component then
            return
        end
        grid_rows[#grid_rows + 1] = { component }
        row_defs[#row_defs + 1] = opts or {}
    end

    append_row(output_section)
    append_row(ui_helper.separator())
    append_row(material_section)
    append_row(ui_helper.separator())
    append_row(entries_section, { grow = true })
    if issues_section then
        append_row(ui_helper.separator())
        append_row(issues_section)
    end

    local dialog_content = ui.grid({
        padding = ui.PADDING.MEDIUM,
        spacing = ui.SPACING.MEDIUM,
        columns = { { grow = true } },
        rows = row_defs,
        children = grid_rows,
    })

    return ui.dialog({
        title = "Create Models From GLTF",
        resizable = false,
        grow = false,
        content = dialog_content,
        buttons = {
            ui.dialog_button({
                text = "Cancel",
                cancel = true,
                result = { action = "cancel" },
            }),
            ui.dialog_button({
                text = "Create Models",
                default = true,
                enabled = validation.ok == true,
                result = { action = "create" },
            }),
        },
    })
end)

function M.show(opts)
    local state = {
        entries = clone_entries(opts.entries or {}),
        material = generator.clone_material(opts.material or generator.default_material_config()),
        output_dir = normalize_directory_path(opts.output_dir or generator.derive_default_output_dir(opts.initial_paths or {})),
        default_create_go_bones = opts.default_create_go_bones == true,
    }

    if #state.entries == 0 then
        state.entries[1] = {
            mesh_path = "",
            display_name = "",
            output_name = "",
            create_go_bones = state.default_create_go_bones,
        }
    end

    local analysis_cache = {}
    local suggestions = {}
    local seen = {}
    local derived_material_name = nil
    for _, entry in ipairs(state.entries) do
        local analysis = generator.inspect_gltf(entry.mesh_path)
        if analysis then
            analysis_cache[entry.mesh_path] = analysis
            if not derived_material_name and analysis.primary_material_name then
                derived_material_name = analysis.primary_material_name
            end
            for _, image_path in ipairs(analysis.image_paths or {}) do
                if not seen[image_path] then
                    seen[image_path] = true
                    suggestions[#suggestions + 1] = image_path
                end
            end
        end
    end

    local material_info = nil
    local sampler_list = {}
    if state.material.material_path and state.material.material_path ~= "" then
        material_info = generator.read_material_info(state.material.material_path)
        sampler_list = material_info.samplers or {}
    end
    if #sampler_list == 0 then
        sampler_list = generator.samplers_from_textures(state.material.textures)
    end

    local allow_autofill = generator.should_autofill_material_name(state.material.display_name)
    if derived_material_name and allow_autofill then
        state.material.display_name = derived_material_name
    elseif material_info and material_info.display_name and material_info.display_name ~= "" and allow_autofill then
        state.material.display_name = material_info.display_name
    end

    state.material.textures = generator.align_textures(sampler_list, state.material.textures, suggestions)
    state.analysis_cache = analysis_cache
    state.texture_suggestions = suggestions
    state.samplers = sampler_list
    state.material_name_manual = not allow_autofill

    local dialog = dialog_component({
        state = state,
    })

    local result = ui.show_dialog(dialog)
    if result and result.action == "create" then
        if not state.material_name_manual and generator.should_autofill_material_name(state.material.display_name) then
            local inferred_name = derive_primary_material_name(state.entries, state.analysis_cache)
            if inferred_name and inferred_name ~= "" then
                state.material.display_name = inferred_name
            end
        end
        return true, state
    end
    return false
end

function M.open_dialog(initial_paths)
    initial_paths = initial_paths or {}
    local entries = generator.create_entries_from_paths(initial_paths)
    local confirmed, state = M.show({
        entries = entries,
        initial_paths = initial_paths,
    })
    if not confirmed then
        return
    end

    local validation = generator.validate(state.entries, state.output_dir, state.material)
    if not validation.ok then
        print("[GLTF Models] Please resolve the highlighted issues before creating files.")
        return
    end

    local ok, err = pcall(generator.create_files, state.entries, state.output_dir, state.material)
    if not ok then
        print("[GLTF Models] Failed to create model files: " .. tostring(err))
        return
    end

    print(string.format("[GLTF Models] Created %d model file(s) in %s", #state.entries, state.output_dir))
end

return M
