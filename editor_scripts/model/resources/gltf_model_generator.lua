local file_helper = require "editor_scripts.helpers.file_helper"
local string_helper = require "editor_scripts.helpers.string_helper"
local model_helper = require "editor_scripts.model.resources.model_helper"

local DEFAULT_MATERIAL = "/builtins/materials/model.material"
local DEFAULT_MATERIAL_SAMPLER = "tex0"
local DEFAULT_OUTPUT = "/"

local M = {}

local path_with_leading_slash = string_helper.path_with_leading_slash
local path_remove_extension = string_helper.path_remove_extension
local path_basename = string_helper.path_basename
local path_dirname = string_helper.path_dirname
local ensure_extension = string_helper.ensure_extension
local resolve_relative_path = string_helper.resolve_relative_path

local function clone_textures(textures)
    local cloned = {}
    for index, tex in ipairs(textures or {}) do
        cloned[index] = {
            sampler = tex.sampler,
            texture = tex.texture,
        }
    end
    return cloned
end

function M.create_entries_from_paths(paths)
    local entries = {}
    for _, path in ipairs(paths or {}) do
        local clean_path = path_with_leading_slash(path)
        local default_name = path_remove_extension(path_basename(clean_path))
        entries[#entries + 1] = {
            mesh_path = clean_path,
            display_name = default_name,
            output_name = default_name,
            create_go_bones = false,
        }
    end
    return entries
end

function M.default_material_config()
    return {
        display_name = "material",
        material_path = DEFAULT_MATERIAL,
        textures = {
            { sampler = DEFAULT_MATERIAL_SAMPLER, texture = "" },
        },
    }
end

function M.derive_default_output_dir(paths)
    if not paths or #paths == 0 then
        return DEFAULT_OUTPUT
    end
    return path_dirname(path_with_leading_slash(paths[1]))
end

local function build_target_path(output_dir, output_name)
    local dir = path_with_leading_slash(output_dir or "")
    if dir == "" then
        return ""
    end
    if dir ~= "/" and dir:sub(-1) == "/" then
        dir = dir:sub(1, -2)
    end
    return string.format("%s/%s", dir, ensure_extension(output_name, ".model"))
end

function M.target_path(output_dir, output_name)
    return build_target_path(output_dir, output_name)
end

function M.validate(entries, output_dir, material)
    local result = {
        ok = true,
        general = {},
        entries = {},
        material = {},
        textures = {},
        output_dir = nil,
    }

    if not entries or #entries == 0 then
        result.ok = false
        result.general[#result.general + 1] = "Add at least one GLTF file."
    end

    local dir = path_with_leading_slash(output_dir or "")
    if dir == "" then
        result.ok = false
        result.output_dir = "Output directory is required."
        result.general[#result.general + 1] = result.output_dir
    end

    local material_display = material and material.display_name or ""
    if material_display == "" then
        result.ok = false
        result.material.display_name = "Material name is required."
    end

    local material_path = material and path_with_leading_slash(material.material_path or "") or ""
    if material_path == "" then
        result.ok = false
        result.material.material_path = "Material resource is required."
    end

    local textures = material and material.textures or {}
    if #textures == 0 then
        result.ok = false
        result.material.textures = "Add at least one texture for the material."
    end

    local sampler_usage = {}
    for index, texture in ipairs(textures) do
        local tex_issue = {}
        if not texture.sampler or texture.sampler == "" then
            tex_issue.sampler = "Sampler name is required."
        elseif sampler_usage[texture.sampler] then
            tex_issue.sampler = "Sampler names must be unique."
        else
            sampler_usage[texture.sampler] = true
        end

        if not texture.texture or texture.texture == "" then
            tex_issue.texture = "Texture path is required."
        end

        if next(tex_issue) then
            result.textures[index] = tex_issue
            result.ok = false
        end
    end

    local targets = {}
    for index, entry in ipairs(entries or {}) do
        local entry_issue = {}
        if not entry.mesh_path or entry.mesh_path == "" then
            entry_issue.mesh_path = "GLTF resource is required."
        end

        if not entry.display_name or entry.display_name == "" then
            entry_issue.display_name = "Model name cannot be empty."
        end

        if not entry.output_name or entry.output_name == "" then
            entry_issue.output_name = "Output file name is required."
        end

        local target = build_target_path(dir, entry.output_name or "")
        if target == "" then
            entry_issue.output_name = entry_issue.output_name or "Invalid output path."
        elseif targets[target] then
            entry_issue.output_name = "Duplicate target path."
        else
            targets[target] = index
            if file_helper.exists(target) then
                entry_issue.output_name = string.format("Target %s already exists.", target)
            end
        end

        if next(entry_issue) then
            result.entries[index] = entry_issue
            result.ok = false
        end
    end

    return result
end

function M.build_resources(entries, output_dir, material)
    local resources = {}
    local dir = path_with_leading_slash(output_dir or "")
    for _, entry in ipairs(entries or {}) do
        local target = build_target_path(dir, entry.output_name or "")
        resources[#resources + 1] = { target, model_helper.build_model_content(entry, material) }
    end
    return resources
end

function M.create_files(entries, output_dir, material)
    local dir = path_with_leading_slash(output_dir or "")
    for _, entry in ipairs(entries or {}) do
        local target = build_target_path(dir, entry.output_name or "")
        local target_dir = path_dirname(target)
        if target_dir and target_dir ~= "" and target_dir ~= "/" then
            file_helper.ensure_directory(target_dir)
        end
    end
    local resources = M.build_resources(entries, dir, material)
    editor.create_resources(resources)
end

function M.clone_material(material)
    return {
        display_name = material and material.display_name or "",
        material_path = material and material.material_path or "",
        textures = clone_textures(material and material.textures or {}),
    }
end

function M.clone_textures(textures)
    return clone_textures(textures)
end

local function json_decode(content)
    local ok, decoded = pcall(json.decode, content)
    if not ok then
        return nil, decoded
    end
    return decoded
end

local function extract_array_block(content, key)
    if not content or not key then
        return nil
    end
    local key_pos = content:find('"' .. key .. '"')
    if not key_pos then
        return nil
    end
    local array_start = content:find("%[", key_pos)
    if not array_start then
        return nil
    end
    local depth = 0
    local in_string = false
    local escape = false
    for i = array_start, #content do
        local ch = content:sub(i, i)
        if in_string then
            if escape then
                escape = false
            elseif ch == "\\" then
                escape = true
            elseif ch == '"' then
                in_string = false
            end
        else
            if ch == '"' then
                in_string = true
            elseif ch == "[" then
                depth = depth + 1
            elseif ch == "]" then
                depth = depth - 1
                if depth == 0 then
                    return content:sub(array_start, i)
                end
            end
        end
    end
    return nil
end

local function heuristic_gltf_analysis(content, resource_path)
    if not content then
        return nil
    end
    local analysis = {
        material_names = {},
        primary_material_name = nil,
        image_paths = {},
    }
    local seen_material = {}
    local materials_block = extract_array_block(content, "materials")
    if materials_block then
        for name in materials_block:gmatch('"name"%s*:%s*"(.-)"') do
            if name ~= "" and not seen_material[name] then
                seen_material[name] = true
                analysis.material_names[#analysis.material_names + 1] = name
                if not analysis.primary_material_name then
                    analysis.primary_material_name = name
                end
            end
        end
    end
    local base_dir = path_dirname(resource_path)
    local seen_images = {}
    local images_block = extract_array_block(content, "images")
    if images_block then
        for uri in images_block:gmatch('"uri"%s*:%s*"(.-)"') do
            local resolved = resolve_relative_path(base_dir, uri)
            if not seen_images[resolved] then
                seen_images[resolved] = true
                analysis.image_paths[#analysis.image_paths + 1] = resolved
            end
        end
    end
    if analysis.primary_material_name or #analysis.image_paths > 0 then
        return analysis
    end
    return nil
end

local function get_zero_based(list, index)
    if not list or index == nil then
        return nil
    end
    return list[index + 1]
end

local function collect_texture_path(texture_info, textures, images, base_dir)
    if not texture_info or texture_info.index == nil then
        return nil
    end
    local texture_entry = get_zero_based(textures, texture_info.index)
    if not texture_entry or texture_entry.source == nil then
        return nil
    end
    local image_entry = get_zero_based(images, texture_entry.source)
    if not image_entry or not image_entry.uri then
        return nil
    end
    return resolve_relative_path(base_dir, image_entry.uri)
end

function M.inspect_gltf(resource_path)
    if not resource_path or resource_path == "" then
        return nil, "missing gltf path"
    end
    local content, read_err = file_helper.read_all(resource_path)
    if not content then
        return nil, read_err
    end
    local data, decode_err = json_decode(content)
    if not data then
        local fallback = heuristic_gltf_analysis(content, resource_path)
        if fallback then
            return fallback
        end
        return nil, decode_err
    end

    local analysis = {
        material_names = {},
        primary_material_name = nil,
        image_paths = {},
    }

    for index, material in ipairs(data.materials or {}) do
        if material.name and material.name ~= "" then
            analysis.material_names[#analysis.material_names + 1] = material.name
            if not analysis.primary_material_name then
                analysis.primary_material_name = material.name
            end
        else
            analysis.material_names[#analysis.material_names + 1] = string.format("material_%d", index)
        end
    end

    local base_dir = path_dirname(resource_path)
    local textures = data.textures or {}
    local images = data.images or {}
    local image_lookup = {}
    local function add_texture_path(path)
        if path and not image_lookup[path] then
            image_lookup[path] = true
            analysis.image_paths[#analysis.image_paths + 1] = path
        end
    end

    for _, material in ipairs(data.materials or {}) do
        local pbr = material.pbrMetallicRoughness or {}
        add_texture_path(collect_texture_path(pbr.baseColorTexture, textures, images, base_dir))
        add_texture_path(collect_texture_path(pbr.metallicRoughnessTexture, textures, images, base_dir))
        add_texture_path(collect_texture_path(material.normalTexture, textures, images, base_dir))
        add_texture_path(collect_texture_path(material.occlusionTexture, textures, images, base_dir))
        add_texture_path(collect_texture_path(material.emissiveTexture, textures, images, base_dir))
    end

    if #analysis.image_paths == 0 then
        for _, image in ipairs(images) do
            if image.uri then
                add_texture_path(resolve_relative_path(base_dir, image.uri))
            end
        end
    end

    return analysis
end

local function parse_sampler_names(material_text)
    local names = {}
    if not material_text then
        return names
    end
    for block in material_text:gmatch("samplers%s*{%s*([^}]*)}") do
        local name = block:match('name:%s*"([^"]+)"')
        if name then
            names[#names + 1] = name
        end
    end
    return names
end

local function parse_material_display_name(content)
    if not content then
        return nil
    end
    local name = content:match("^%s*name:%s*\"([^\"]+)\"")
    if not name then
        name = content:match("\nname:%s*\"([^\"]+)\"")
    end
    return name
end

function M.samplers_from_textures(textures)
    local samplers = {}
    local seen = {}
    for _, texture in ipairs(textures or {}) do
        if texture.sampler and not seen[texture.sampler] then
            seen[texture.sampler] = true
            samplers[#samplers + 1] = texture.sampler
        end
    end
    if #samplers == 0 then
        samplers[1] = "tex0"
    end
    return samplers
end

function M.read_material_info(material_path)
    local info = {
        display_name = nil,
        samplers = {},
    }
    if not material_path or material_path == "" then
        info.samplers = M.samplers_from_textures()
        return info
    end
    local content = file_helper.read_all(material_path)
    if content then
        info.display_name = parse_material_display_name(content)
        info.samplers = parse_sampler_names(content)
    end
    if #info.samplers == 0 then
        info.samplers = M.samplers_from_textures()
    end
    return info
end

function M.read_material_samplers(material_path)
    return M.read_material_info(material_path).samplers
end

function M.material_name_from_resource(material_path)
    return M.read_material_info(material_path).display_name
end

local function textures_by_sampler(textures)
    local map = {}
    for _, texture in ipairs(textures or {}) do
        if texture.sampler then
            map[texture.sampler] = texture.texture or ""
        end
    end
    return map
end

function M.align_textures(samplers, current_textures, suggestions)
    local aligned = {}
    local by_sampler = textures_by_sampler(current_textures)
    for index, sampler in ipairs(samplers or {}) do
        local suggestion = ""
        if suggestions and suggestions[index] then
            suggestion = suggestions[index]
        end
        aligned[index] = {
            sampler = sampler,
            texture = by_sampler[sampler] or suggestion,
        }
    end
    return aligned
end

function M.merge_texture_suggestions(existing, new_values)
    local merged = {}
    local seen = {}
    for _, value in ipairs(existing or {}) do
        if not seen[value] then
            seen[value] = true
            merged[#merged + 1] = value
        end
    end
    for _, value in ipairs(new_values or {}) do
        if not seen[value] then
            seen[value] = true
            merged[#merged + 1] = value
        end
    end
    return merged
end

function M.should_autofill_material_name(current_name)
    if not current_name or current_name == "" then
        return true
    end
    return current_name == M.default_material_config().display_name
end

return M
