---
title: Editor scripts
brief: This manual explains how to extend editor using Lua
---

# Editor scripts

You can create custom menu items and editor lifecycle hooks using Lua files with special extension: `.editor_script`. Using this system, you can tweak editor to enhance your development workflow.

## Editor script runtime

Editor scripts run inside an editor, in a Lua VM emulated by Java VM. All scripts share the same single environment, which means they can interact with each other. You can require Lua modules, just as with `.script` files, but Lua version that is running inside the editor is different, so make sure your shared code is compatible. Editor uses Lua version 5.2.x, more specifically [luaj](https://github.com/luaj/luaj) runtime, which is currently the only viable solution to run Lua on JVM. Besides that, there are some restrictions:
- there is no `debug` package;
- there is no `os.execute`, though we provide a similar `editor.execute()`;
- there is no `os.tmpname` and `io.tmpfile` — currently editor scripts can access files only inside the project directory;
- there is currently no `os.rename`, although we want to add it;
- there is no `os.exit` and `os.setlocale`.
- it's not allowed to use some long-running functions in contexts where the editor needs an immediate response from the script, see [Execution Modes](#execution-modes) for more details.

All editor extensions defined in editor scripts are loaded when you open a project. When you fetch libraries, extensions are reloaded, since there might be new editor scripts in a libraries you depend on. During this reload, no changes in your own editor scripts are picked up, since you might be in the middle of changing them. To reload them as well, you should run **Project → Reload Editor Scripts** command.

## Anatomy of `.editor_script`

Every editor script should return a module, like that:
```lua
local M = {}

function M.get_commands()
  -- TODO - define editor commands
end

function M.get_language_servers()
  -- TODO - define language servers
end

function M.get_prefs_schema()
  -- TODO - define preferences
end

return M
```
Editor then collects all editor scripts defined in project and libraries, loads them into single Lua VM and calls into them when needed (more on that in [commands](#commands) and [lifecycle hooks](#lifecycle-hooks) sections).

## Editor API

You can interact with the editor using `editor` package that defines this API:
- `editor.platform` — a string, either `"x86_64-win32"` for Windows, `"x86_64-macos"` for macOS or `"x86_64-linux"` for Linux.
- `editor.version` — a string, version name of Defold, e.g. `"1.4.8"`
- `editor.engine_sha1` — a string, SHA1 of Defold engine
- `editor.editor_sha1` — a string, SHA1 of Defold editor
- `editor.get(node_id, property)` — get a value of some node inside the editor. Nodes in the editor are various entities, such as script or collection files, game objects inside collections, json files loaded as resources, etc. `node_id` is a userdata that is passed to the editor script by the editor. Alternatively, you can pass resource path instead of node id, for example `"/main/game.script"`. `property` is a string. Currently these properties are supported:
  - `"path"` — file path from the project folder for *resources* — entities that exist as files or directories. Example of returned value: `"/main/game.script"`
  - `"children"` — list of children resource paths for directory resources
  - `"text"` — text content of a resource editable as text (such as script files or json). Example of returned value: `"function init(self)\nend"`. Please note that this is not the same as reading file with `io.open()`, because you can edit a file without saving it, and these edits are available only when accessing `"text"` property.
  - for atlases: `images` (list of editor nodes for images in the atlas) and `animations` (list of animation nodes)
  - for atlas animations: `images` (same as `images` in atlas)
  - for tilemaps: `layers` (list of editor nodes for layers in the tilemap)
  - for tilemap layers: `tiles` (an unbounded 2d grid of tiles), see `tilemap.tiles.*` for more info
  - for particlefx: `emitters` (list of emitter editor nodes) and `modifiers` (list of modifier editor nodes)
  - for particlefx emitters: `modifiers` (list of modifier editor nodes)
  - for collision objects: `shapes` (list of collision shape editor nodes)
  - for GUI files: `layers` (list of layer editor nodes)
  - some properties that are shown in the Properties view when you have selected something in the Outline view. These types of outline properties supported:
    - `strings`
    - `booleans`
    - `numbers`
    - `vec2`/`vec3`/`vec4`
    - `resources`
    - `curves`
    Please note that some of these properties might be read-only, and some might be unavailable in different contexts, so you should use `editor.can_get` before reading them and `editor.can_set` before making editor set them. Hover over property name in Properties view to see a tooltip with information about how this property is named in editor scripts. You can set resource properties to `nil` by supplying `""` value.
- `editor.can_get(node_id, property)` — check if you can get this property so `editor.get()` won't throw an error.
- `editor.can_set(node_id, property)` — check if `editor.tx.set()` transaction step with this property won't throw an error.
- `editor.create_directory(resource_path)` — create a directory if it does not exist, and all non-existent parent directories.
- `editor.create_resources(resources)` — create 1 or more resources, either from templates or with custom content
- `editor.delete_directory(resource_path)` — delete a directory if it exists, and all existent child directories and files.
- `editor.execute(cmd, [...args], [options])` — run a shell command, optionally capturing its output.
- `editor.save()` — persist all unsaved changed to disk.
- `editor.transact(txs)` — modify the editor in-memory state using 1 or more transaction steps created with `editor.tx.*` functions.
- `editor.ui.*` — various UI-related functions, see [UI manual](/manuals/editor-scripts-ui).
- `editor.prefs.*` — functions for interacting with editor preferences, see [preferences](#preferences).

You can find the full editor API reference [here](https://defold.com/ref/alpha/editor/).

## Commands

If editor script module defines function `get_commands`, it will be called on extension reload, and returned commands will be available for use inside the editor in menu bar or in context menus in Assets and Outline panes. Example:
```lua
local M = {}

function M.get_commands()
  return {
    {
      label = "Remove Comments",
      locations = {"Edit", "Assets"},
      query = {
        selection = {type = "resource", cardinality = "one"}
      },
      active = function(opts)
        local path = editor.get(opts.selection, "path")
        return ends_with(path, ".lua") or ends_with(path, ".script")
      end,
      run = function(opts)
        local text = editor.get(opts.selection, "text")
        editor.transact({
          editor.tx.set(opts.selection, "text", strip_comments(text))
        })
      end
    },
    {
      label = "Minify JSON",
      locations = {"Assets"},
      query = {
        selection = {type = "resource", cardinality = "one"}
      },
      active = function(opts)
        return ends_with(editor.get(opts.selection, "path"), ".json")
      end,
      run = function(opts)
        local path = editor.get(opts.selection, "path")
        editor.execute("./scripts/minify-json.sh", path:sub(2))
      end
    }
  }
end

return M
```
Editor expects `get_commands()` to return an array of tables, each describing a separate command. Command description consists of:

- `label` (required) — text on a menu item that will be displayed to the user
- `locations` (required) — an array of either `"Edit"`, `"View"`, `"Project"`, `"Debug"`, `"Assets"`, `"Bundle"`, `"Scene"` or `"Outline"`, describes a place where this command should be available. `"Edit"`, `"View"`, `"Project"` and `"Debug"` mean menu bar at the top, `"Assets"` means context menu in Assets pane, `"Outline"` means context menu in Outline pane, and `"Bundle"` means **Project → Bundle** submenu.
- `query` — a way for command to ask editor for relevant information and define what data it operates on. For every key in `query` table there will be corresponding key in `opts` table that `active` and `run` callbacks receive as argument. Supported keys:
  - `selection` means this command is valid when there is something selected, and it operates on this selection.
    - `type` is a type of selected nodes command is interested in, currently these types are allowed:
      - `"resource"` — in Assets and Outline, resource is selected item that has a corresponding file. In menu bar (Edit or View), resource is a currently open file;
      - `"outline"` — something that can be shown in the Outline. In Outline it's a selected item, in menu bar it's a currently open file;
      - `"scene"` — something that can be rendered to the Scene.
    - `cardinality` defines how many selected items there should be. If `"one"`, selection passed to command callback will be a single node id. If `"many"`, selection passed to command callback will be an array of one or more node ids.
  - `argument` — command argument. Currently, only commands in `"Bundle"` location receive an argument, which is `true` when the bundle command is selected explicitly and `false` on rebundle.
- `id` - command identifier string, used e.g. for persisting the last used bundle command in `prefs`
- `active` - a callback that is executed to check that command is active, expected to return boolean. If `locations` include `"Assets"`, `"Scene"` or `"Outline"`, `active` will be called when showing context menu. If locations include `"Edit"` or `"View"`, active will be called on every user interaction, such as typing on keyboard or clicking with mouse, so be sure that `active` is relatively fast.
- `run` - a callback that is executed when user selects the menu item.

### Use commands to change the in-memory editor state

Inside the `run` handler, you can query and change the in-memory editor state. Querying is done using `editor.get()` function, where you can ask the editor about the current state of files and selection (if using `query = {selection = ...}`). You can get the `"text"` property of script files, and also some properties shown in the Properties view — hover over property name to see a tooltip with information about how this property is named in editor scripts. Changing the editor state is done using `editor.transact()`, where you bundle 1 or more modifications in a single undoable step. For example, if you want to be able to reset transform of a game object, you could write a command like that:
```lua
{
  label = "Reset transform",
  locations = {"Outline"},
  query = {selection = {type = "outline", cardinality = "one"}},
  active = function(opts)
    local node = opts.selection
    return editor.can_set(node, "position") 
       and editor.can_set(node, "rotation") 
       and editor.can_set(node, "scale")
  end,
  run = function(opts)
    local node = opts.selection
    editor.transact({
      editor.tx.set(node, "position", {0, 0, 0}),
      editor.tx.set(node, "rotation", {0, 0, 0}),
      editor.tx.set(node, "scale", {1, 1, 1})
    })
  end
}
```

#### Editing atlases

In addition to reading and writing properties of an atlas, you can read and modify atlas images and animations. Atlas defines `images` and `animations` node list properties, and animations define `images` node list property: you can use `editor.tx.add`, `editor.tx.remove` and `editor.tx.clear` transaction steps with these properties.

For example, to add an image to an atlas, execute the following code in the command's `run` handler:
```lua
editor.transact({
    editor.tx.add("/main.atlas", "images", {image="/assets/hero.png"})
})
```
To find a set of all images in an atlas, execute the following code:
```lua
local all_images = {} ---@type table<string, true>
-- first, collect all "bare" images
local image_nodes = editor.get("/main.atlas", "images")
for i = 1, #image_nodes do
    all_images[editor.get(image_nodes[i], "image")] = true
end
-- second, collect all images used in animations
local animation_nodes = editor.get("/main.atlas", "animations")
for i = 1, #animation_nodes do
    local animation_image_nodes = editor.get(animation_nodes[i], "images")
    for j = 1, #animation_image_nodes do
        all_images[editor.get(animation_image_nodes[j], "image")] = true
    end
end
pprint(all_images)
-- {
--     ["/assets/hero.png"] = true,
--     ["/assets/enemy.png"] = true,
-- }}
```
To replace all animations in an atlas:
```lua
editor.transact({
    editor.tx.clear("/main.atlas", "animations"),
    editor.tx.add("/main.atlas", "animations", {
        id = "hero_run",
        images = {
            {image = "/assets/hero_run_1.png"},
            {image = "/assets/hero_run_2.png"},
            {image = "/assets/hero_run_3.png"},
            {image = "/assets/hero_run_4.png"}
        }
    })
})
```

#### Editing tilesources

In addition to outline properties, tilesources define the following properties:
- `animations` - a list of animation nodes of the tilesource
- `collision_groups` - a list of collision group nodes of the tilesource
- `tile_collision_groups` - a table of collision group assignments for tiles in the tilesource

For example, here is how you can setup a tilesource:
```lua
local tilesource = "/game/world.tilesource"
editor.transact({
    editor.tx.add(tilesource, "animations", {id = "idle", start_tile = 1, end_tile = 1}),
    editor.tx.add(tilesource, "animations", {id = "walk", start_tile = 2, end_tile = 6, fps = 10}),
    editor.tx.add(tilesource, "collision_groups", {id = "player"}),
    editor.tx.add(tilesource, "collision_groups", {id = "obstacle"}),
    editor.tx.set(tilesource, "tile_collision_groups", {
        [1] = "player",
        [7] = "obstacle",
        [8] = "obstacle"
    })
})
```

#### Editing tilemaps

Tilemaps define `layers` property, a node list of tilemap layers. Each layer also defines a `tiles` property that holds an unbounded 2d grid of tiles on this layer. This is different from the engine: tiles have no bounds and may be added anywhere, including negative coordinates. To edit tiles, the editor script API defines a `tilemap.tiles` module with the following functions:
- `tilemap.tiles.new()` to create a fresh data structure that holds an unbounded 2d tile grid (in the editor, contrary to the engine, the tilemap is unbounded, and coordinates may be negative)
- `tilemap.tiles.get_tile(tiles, x, y)` to get a tile index at a specific coordinate
- `tilemap.tiles.get_info(tiles, x, y)` to get full tile information at a specific coordinate (the data shape is the same as in the engine's `tilemap.get_tile_info` function)
- `tilemap.tiles.iterator(tiles)` to create an iterator over all tiles in the tilemap
- `tilemap.tiles.clear(tiles)` to remove all tiles from the tilemap
- `tilemap.tiles.set(tiles, x, y, tile_or_info)` to set a tile at a specific coordinate
- `tilemap.tiles.remove(tiles, x, y)` to remove a tile at a specific coordinate

For example, here is how you can print the contents of the whole tilemap:
```lua
local layers = editor.get("/level.tilemap", "layers")
for i = 1, #layers do
    local layer = layers[i]
    local id = editor.get(layer, "id")
    local tiles = editor.get(layer, "tiles")
    print("layer " .. id .. ": {")
    for x, y, tile in tilemap.tiles.iterator(tiles) do
        print("  [" .. x .. ", " .. y .. "] = " .. tile)
    end
    print("}")
end
```

Here is an example that shows how to add a layer with tiles to a tilemap:
```lua
local tiles = tilemap.tiles.new()
tilemap.tiles.set(tiles, 1, 1, 2)
editor.transact({
    editor.tx.add("/level.tilemap", "layers", {
        id = "new_layer",
        tiles = tiles
    })
})
```

#### Editing particlefx

You can edit particlefx using `modifiers` and `emitters` properties. For example, adding a circle emitter with acceleration modifier is done like this:
```lua
editor.transact({
    editor.tx.add("/fire.particlefx", "emitters", {
        type = "emitter-type-circle",
        modifiers = {
          {type = "modifier-type-acceleration"}
        }
    })
})
```
Many particlefx properties are curves or curve spreads (i.e. curve + some randomizer value). Curves are represented as a table with a non-empty list of `points`, where each point is a table with the following properties:
- `x` - the x coordinate of the point, should start at 0 and end at 1
- `y` - the value of the point
- `tx` (0 to 1) and `ty` (-1 to 1) - tangents of the point. E.g., for an 80-degree angle, `tx` should be `math.cos(math.rad(80))` and `ty` should be `math.sin(math.rad(80))`.
Curve spreads additionally have a `spread` number property. 

For example, setting a particle lifetime alpha curve for an already existing emitter might look like this:
```lua
local emitter = editor.get("/fire.particlefx", "emitters")[1]
editor.transact({
    editor.tx.set(emitter, "particle_key_alpha", { points = {
        {x = 0,   y = 0, tx = 0.1, ty = 1}, -- start at 0, go up quickly
        {x = 0.2, y = 1, tx = 1,   ty = 0}, -- reach 1 at 20% of a lifetime
        {x = 1,   y = 0, tx = 1,   ty = 0}  -- slowly go down to 0
    }})
})
```
Of course, it's also possible to use the `particle_key_alpha` key in a table when creating an emitter. Additionally, you can use a single number instead to represent a "static" curve.

#### Editing collision objects

In addition to default outline properties, collision objects define `shapes` node list property. Adding new collision shapes is done like this:
```lua
editor.transact({
    editor.tx.add("/hero.collisionobject", "shapes", {
        type = "shape-type-box" -- or "shape-type-sphere", "shape-type-capsule"
    })
})
```
Shape's `type` property is required during creation and cannot be changed after the shape is added. There are 3 shape types:
- `shape-type-box` - box shape with `dimensions` property
- `shape-type-sphere` - sphere shape with `diameter` property
- `shape-type-capsule` - capsule shape with `diameter` and `height` properties

#### Editing GUI files

In addition to outline properties, GUI nodes defines the following properties:
- `layers` — list of layer editor nodes (reorderable)
- `materials` — list of material editor nodes

It's possible to edit GUI layers using editor `layers` property, e.g.:
```lua
editor.transact({
    editor.tx.add("/main.gui", "layers", {name = "foreground"}),
    editor.tx.add("/main.gui", "layers", {name = "background"})
})
```
Additionally, it's possible to reorder layers:
```lua
local fg, bg = table.unpack(editor.get("/main.gui", "layers"))
editor.transact({
    editor.tx.reorder("/main.gui", "layers", {bg, fg})
})
```
Similarly, fonts, materials, textures, and particlefxs are edited using `fonts`, `materials`, `textures`, and `particlefxs` properties:
```lua
editor.transact({
    editor.tx.add("/main.gui", "fonts", {font = "/main.font"}),
    editor.tx.add("/main.gui", "materials", {name = "shine", material = "/shine.material"}),
    editor.tx.add("/main.gui", "particlefxs", {particlefx = "/confetti.material"}),
    editor.tx.add("/main.gui", "textures", {texture = "/ui.atlas"})
})
```
These properties don't support reordering.

Finally, you can edit GUI nodes using `nodes` list property, e.g.:
```lua
editor.transact({
    editor.tx.add("/main.gui", "nodes", {
        type = "gui-node-type-box",
        position = {20, 20, 20}
    }),
    editor.tx.add("/main.gui", "nodes", {
        type = "gui-node-type-template",
        template = "/button.gui"
    }),
})
```
Built-in node types are:
- `gui-node-type-box`
- `gui-node-type-particlefx`
- `gui-node-type-pie`
- `gui-node-type-template`
- `gui-node-type-text`

If you are using spine extension, you can also use `gui-node-type-spine` node type.

If the GUI file defines layouts, you can get and set the values from layouts using `layout:property` syntax, e.g.:
```lua
local node = editor.get("/main.gui", "nodes")[1]

-- GET:
local position = editor.get(node, "position")
pprint(position) -- {20, 20, 20}
local landscape_position = editor.get(node, "Landscape:position")
pprint(landscape_position) -- {20, 20, 20}

-- SET:
editor.transact({
    editor.tx.set(node, "Landscape:position", {30, 30, 30})
})
pprint(editor.get(node, "Landscape:position")) -- {30, 30, 30}
```

Layout properties that were set can be reset to their default values using `editor.tx.reset`:
```lua
print(editor.can_reset(node, "Landscape:position")) -- true
editor.transact({
    editor.tx.reset(node, "Landscape:position")
})
```
Template node trees can be read, but not edited — you can only set node properties of the template node tree:
```lua
local template = editor.get("/main.gui", "nodes")[2]
print(editor.can_add(template, "nodes")) -- false
local node_in_template = editor.get(template, "nodes")[1]
editor.transact({
    editor.tx.set(node_in_template, "text", "Button text")
})
print(editor.can_reset(node_in_template, "text")) -- true (overrides a value in the template)
```

#### Editing game objects

It's possible to edit components of a game object file using editor scripts. The components come in 2 flavors: referenced and embedded. Referenced components use type `component-reference` and act as references to other resources, only allowing overrides of go properties defined in scripts. Embedded components use types like `sprite`, `label`, etc., and allow editing of all properties defined in the component type, as well as adding sub-components like shapes of collision objects. For example, you can use the following code to set up a game object:
```lua
editor.transact({
    editor.tx.add("/npc.go", "components", {
        type = "sprite",
        id = "view"
    }),
    editor.tx.add("/npc.go", "components", {
        type = "collisionobject",
        id = "collision",
        shapes = {
            {
                type = "shape-type-box",
                dimensions = {32, 32, 32}
            }
        }
    }),
    editor.tx.add("/npc.go", "components", {
        type = "component-reference",
        path = "/npc.script"
        id = "controller",
        __hp = 100 -- set a go property defined in the script
    })
})
```

#### Editing collections
It's possible to edit collections using editor scripts. You can add game objects (embedded or referenced) and collections (referenced). For example:
```lua
local coll = "/char.collection"
editor.transact({
    editor.tx.add(coll, "children", {
        -- embbedded game object
        type = "go",
        id = "root",
        children = {
            {
                -- referenced game object
                type = "go-reference",
                path = "/char-view.go"
                id = "view"
            },
            {
                -- referenced collection
                type = "collection-reference",
                path = "/body-attachments.collection"
                id = "attachments"
            }
        },
        -- embedded gos can also have components
        components = {
            {
                type = "collisionobject",
                id = "collision",
                shapes = {
                    {type = "shape-type-box", dimensions = {2.5, 2.5, 2.5}}
                }
            },
            {
                type = "component-reference",
                id = "controller",
                path = "/char.script",
                __hp = 100 -- set a go property defined in the script
            }
        }
    })
})
```

Like in the editor, referenced collections can only be added to the root of the edited collection, and game objects can only be added to embedded or referenced game objects, but not to referenced collections or game objects within these referenced collections.

### Use shell commands

Inside the `run` handler, you can write to files (using `io` module) and execute shell commands (using `editor.execute()` command). When executing shell commands, it's possible to capture the output of a shell command as a string and then use it in code. For example, if you want to make a command for formatting JSON that shells out to globally installed [`jq`](https://jqlang.github.io/jq/), you can write the following command:
```lua
{
  label = "Format JSON",
  locations = {"Assets"},
  query = {selection = {type = "resource", cardinality = "one"}},
  action = function(opts)
    local path = editor.get(opts.selection, "path")
    return path:match(".json$") ~= nil
  end,
  run = function(opts)
    local text = editor.get(opts.selection, "text")
    local new_text = editor.execute("jq", "-n", "--argjson", "data", text, "$data", {
      reload_resources = false, -- don't reload resources since jq does not touch disk
      out = "capture" -- return text output instead of nothing
    })
    editor.transact({ editor.tx.set(opts.selection, "text", new_text) })
  end
}
```
Since this command invokes shell program in a read-only way (and notifies the editor about it using `reload_resources = false`), you get the benefit of making this action undoable.

::: sidenote
If you want to distribute your editor script as a library, you might want to bundle the binary program for editor platforms within the dependency. See [Editor scripts in libraries](#editor-scripts-in-libraries) for more details on how to do it.
:::

## Lifecycle hooks

There is a specially treated editor script file: `hooks.editor_script`, located in a root of your project, in the same directory as *game.project*. This and only this editor script will receive lifecycle events from the editor. Example of such file:
```lua
local M = {}

function M.on_build_started(opts)
  local file = io.open("assets/build.json", "w")
  file:write('{"build_time": "' .. os.date() .. '"}')
  file:close()
end

return M
```
We decided to limit lifecycle hooks to single editor script file because order in which build hooks happen is more important than how easy it is to add another build step. Commands are independent from each other, so it does not really matter in what order they are shown in the menu, in the end user executes a particular command they selected. If it was possible to specify build hooks in different editor scripts, it would create a problem: in which order do hooks execute? You probably want to create a checksums of content after you compress it... And having a single file that establishes order of build steps by calling each step function explicitly is a way to solve this problem.

Existing lifecycle hooks that `/hooks.editor_script` may specify:
- `on_build_started(opts)` — executed when game is Built to run locally or on some remote target using either the Project Build or Debug Start options. Your changes will appear in the built game. Raising an error from this hook will abort a build. `opts` is a table that contains following keys:
  - `platform` — a string in `%arch%-%os%` format describing what platform it's built for, currently always the same value as in `editor.platform`.
- `on_build_finished(opts)` — executed when build is finished, be it successful or failed. `opts` is a table with following keys:
  - `platform` — same as in `on_build_started`
  - `success` — whether build is successful, either `true` or `false`
- `on_bundle_started(opts)` — executed when you create a bundle or Build HTML5 version of a game. As with `on_build_started`, changes triggered by this hook will appear in a bundle, and errors will abort a bundle. `opts` will have these keys:
  - `output_directory` — a file path pointing to a directory with bundle output, for example `"/path/to/project/build/default/__htmlLaunchDir"`
  - `platform` — platform the game is bundled for. See a list of possible platform values in [Bob manual](/manuals/bob).
  - `variant` — bundle variant, either `"debug"`, `"release"` or `"headless"`
- `on_bundle_finished(opts)` — executed when bundle is finished, be it successful or not. `opts` is a table with the same data as `opts` in `on_bundle_started`, plus `success` key indicating whether build is successful.
- `on_target_launched(opts)` — executed when user launched a game and it successfully started. `opts` contains an `url` key pointing to a launched engine service, for example, `"http://127.0.0.1:35405"`
- `on_target_terminated(opts)` — executed when launched game is closed, has same opts as `on_target_launched`

Please note that lifecycle hooks currently are an editor-only feature, and they are not executed by Bob when bundling from command line.

## Language servers

The editor supports a subset [Language Server Protocol](https://microsoft.github.io/language-server-protocol/). While we aim to expand the editor's support for LSP features in the future, currently it can only show diagnostics (i.e. lints) in the edited files and provide completions.

To define the language server, you need to edit your editor script's `get_language_servers` function like so:

```lua
function M.get_language_servers()
  local command = 'build/plugins/my-ext/plugins/bin/' .. editor.platform .. '/lua-lsp'
  if editor.platform == 'x86_64-win32' then
    command = command .. '.exe'
  end
  return {
    {
      languages = {'lua'},
      watched_files = {
        { pattern = '**/.luacheckrc' }
      },
      command = {command, '--stdio'}
    }
  }
end
```
The editor will start the language server using the specified `command`, using the server process's standard input and output for communication.

Language server definition table may specify:
- `languages` (required) — a list of languages the server is interested in, as defined [here](https://code.visualstudio.com/docs/languages/identifiers#_known-language-identifiers) (file extensions also work);
- `command` (required) - an array of command and its arguments
- `watched_files` - an array of tables with `pattern` keys (a glob) that will trigger the server's [watched files changed](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#workspace_didChangeWatchedFiles) notification.

## HTTP server

Every running instance of the editor has an HTTP server running. The server can be extended using editor scripts. To extend the editor HTTP server, you need to add `get_http_server_routes` editor script function — it should return the additional routes:
```lua
print("My route: " .. http.server.url .. "/my-extension")

function M.get_http_server_routes()
  return {
    http.server.route("/my-extension", "GET", function(request)
      return http.server.response(200, "Hello world!")
    end)
  }
end
```
After reloading the editor scripts, you'll see the following output in the console: `My route: http://0.0.0.0:12345/my-extension`. If you open this link in the browser, you'll see your `"Hello world!"` message.

The input `request` argument is a simple Lua table with information about the request. It contains keys such as `path` (URL path segment that starts with `/`), request `method` (e.g. `"GET"`), `headers` (a table with lower-case header names), and optionally `query` (the query string) and `body` (if the route defines how to interpret the body). For example, if you want to make a route that accepts JSON body, you define it with a `"json"` converter parameter:
```lua
http.server.route("/my-extension/echo-request", "POST", "json", function(request)
  return http.server.json_response(request)
end)
```
You can test this endpoint in the command line using `curl` and `jq`:
```sh
curl 'http://0.0.0.0:12345/my-extension/echo-request?q=1' -X POST --data '{"input": "json"}' | jq
{
  "path": "/my-extension/echo-request",
  "method": "POST",
  "query": "q=1",
  "headers": {
    "host": "0.0.0.0:12345",
    "content-type": "application/x-www-form-urlencoded",
    "accept": "*/*",
    "user-agent": "curl/8.7.1",
    "content-length": "17"
  },
  "body": {
    "input": "json"
  }
}
```
The route path supports patterns that can be extracted from the request path and provided to the handler function as a part of the request, e.g.:
```lua
http.server.route("/my-extension/setting/{category}.{key}", function(request)
  return http.server.response(200, tostring(editor.get("/game.project", request.category .. "." .. request.key)))
end)
```
Now, if you open e.g. `http://0.0.0.0:12345/my-extension/setting/project.title`, you'll see the title of your game taken from the `/game.project` file.

In addition to a single segment paths pattern, you can also match the rest of the URL path using `{*name}` syntax. For example, here is a simple file server endpoint that serves files from the project root:
```lua
http.server.route("/my-extension/files/{*file}", function(request)
  local attrs = editor.external_file_attributes(request.file)
  if attrs.is_file then
    return http.server.external_file_response(request.file)
  else
    return 404
  end
end)
```
Now, opening e.g. `http://0.0.0.0:12345/my-extension/files/main/main.collection` in the browser will display the contents of the `main/main.collection` file.

## Editor scripts in libraries

You can publish libraries for other people to use that contain commands, and they will be automatically picked up by the editor. Hooks, on the other hand, can't be picked up automatically, since they have to be defined in a file that is in a root folder of a project, but libraries expose only subfolders. This is intended to give more control over build process: you still can create lifecycle hooks as simple functions in `.lua` files, so users of your library can require and use them in their `/hooks.editor_script`.

Also note that although dependencies are shown in Assets view, they do not exist as files (they are entries in a zip archive). It's possible to make the editor extract some files from the dependencies into `build/plugins/` folder. To do it, you need to create `ext.manifest` file in your library folder, and then create `plugins/bin/${platform}` folder in the same folder where the `ext.manifest` file is located. Files in that folder will be automatically extracted to `/build/plugins/${extension-path}/plugins/bin/${platform}` folder, so your editor scripts can reference them.

## Preferences

Editor scripts can define and use preferences — persistent, uncommitted pieces of data stored on the user's computer. These preferences have three key characteristics:
- typed: every preference has a schema definition that includes the data type and other metadata like default value
- scoped: preferences are scoped either per project or per user
- nested: every preference key is a dot-separated string, where the first path segment identifies an editor script, and the rest 

All preferences must be registered by defining their schema:
```lua
function M.get_prefs_schema()
  return {
    ["my_json_formatter.jq_path"] = editor.prefs.schema.string(),
    ["my_json_formatter.indent.size"] = editor.prefs.schema.integer({default = 2, scope = editor.prefs.SCOPE.PROJECT}),
    ["my_json_formatter.indent.type"] = editor.prefs.schema.enum({values = {"spaces", "tabs"}, scope = editor.prefs.SCOPE.PROJECT}),
  }
end
```
After such editor script is reloaded, the editor registers this schema. Then the editor script can get and set the preferences, e.g.:
```lua
-- Get a specific preference
editor.prefs.get("my_json_formatter.indent.type")
-- Returns: "spaces"

-- Get an entire preference group
editor.prefs.get("my_json_formatter")
-- Returns:
-- {
--   jq_path = "",
--   indent = {
--     size = 2,
--     type = "spaces"
--   }
-- }

-- Set multiple nested preferences at once
editor.prefs.set("my_json_formatter.indent", {
    type = "tabs",
    size = 1
})
```

## Execution modes

The editor script runtime uses 2 execution modes that are mostly transparent to editor scripts: **immediate** and **long-running**. 

**Immediate** mode is used when the editor needs to receive a response from the script as fast as possible. For instance, menu commands' `active` callbacks are executed in immediate mode, because these checks are performed on the editors UI thread in response to user interacting with the editor, and should update the UI within the same frame. 

**Long-running** mode is used when the editor doesn't need an instantaneous response from the script. For example, menu commands' `run` callbacks are executed in a **long-running** mode, allowing the script to take more time to complete its work.

Some of the functions that the editor scripts can use may take a lot of time to run. For example, `editor.execute("git", "status", {reload_resources=false, out="capture"})` can take up to a second on sufficiently large projects. To maintain editor responsiveness and performance, functions that may be time-consuming are not allowed in contexts where the editor needs an immediate response. Attempting to use such a function in an immediate context will result in an error: `Cannot use long-running editor function in immediate context`. To resolve this error, avoid using such functions in immediate contexts.

The following functions are considered long-running and cannot be used in immediate mode:
- `editor.create_directory()`, `editor.create_resources()`, `editor.delete_directory()`, `editor.save()`, `os.remove()` and `file:write()`: these functions modify the files on disc, causing the editor to synchronize its in-memory resource tree with the disc state, which can take seconds in large projects.
- `editor.execute()`: execution of shell commands can take an unpredictable amount of time.
- `editor.transact()`: large transactions on widely-referenced nodes may take hundreds of milliseconds, which is too slow for UI responsiveness.

The following code execution contexts use immediate mode:
- Menu command's `active` callbacks: the editor needs a response from the script within the same UI frame.
- Top-level of editor scripts: we don't expect the act of reloading editor scripts to have any side effects.

## Actions

::: sidenote
Previously, the editor interacted with the Lua VM in a blocking way, so there was a hard requirement for editor scripts to not block, since some interactions have to be done from the editor UI thread. For that reason, there was e.g. no `editor.execute()` and `editor.transact()`. Executing scripts and changing the editor state was instead triggered by returning an array of "actions" from hooks and command `run` handlers.

Now the editor interacts with the Lua VM in a non-blocking way, so there is no need for these actions any more: using functions like `editor.execute()` is more convenient, concise, and powerful. The actions are now **DEPRECATED**, though we have no plans to remove them.
:::

Editor scripts may return an array of actions from a command's `run` function or from `/hooks.editor_script`'s hook functions. These actions will then be performed by the editor.

Action is a table describing what editor should do. Every action has an `action` key. Actions come in 2 flavors: undoable and non-undoable.

### Undoable actions

::: sidenote
Prefer using `editor.transact()`.
:::

Undoable action can be undone after it is executed. If a command returns multiple undoable actions, they are performed together, and get undone together. You should use undoable actions if you can. Their downside is that they are more limited.

Existing undoable actions:
- `"set"` — set a property of a node in the editor to some value. Example:
  ```lua
  {
    action = "set",
    node_id = opts.selection,
    property = "text",
    value = "current time is " .. os.date()
  }
  ```
  `"set"` action requires these keys:
  - `node_id` — node id userdata. Alternatively, you can use resource path here instead of node id you received from the editor, for example `"/main/game.script"`;
  - `property` — a property of a node to set, e.g. `"text"`;
  - `value` — new value for a property. For `"text"` property it should be a string.

### Non-undoable actions

::: sidenote
Prefer using `editor.execute()`.
:::

Non-undoable action clears undo history, so if you want to undo such action, you will have to use other means, such as version control.

Existing non-undoable actions:
- `"shell"` — execute a shell script. Example:
  ```lua
  {
    action = "shell",
    command = {
      "./scripts/minify-json.sh",
      editor.get(opts.selection, "path"):sub(2) -- trim leading "/"
    }
  }
  ```
  `"shell"` action requires `command` key, which is an array of command and it's arguments.

### Mixing actions and side effects

You can mix undoable and non-undoable actions. Actions are executed sequentially, hence depending on an order of actions you will end up losing ability to undo parts of that command.

Instead of returning actions from functions that expect them, you can just read and write to files directly using `io.open()`. This will trigger a resource reload that will clear undo history.

---
title: "Editor scripts: UI"
brief: This manual explains how to create UI elements in the editor using Lua
---

# Editor scripts and UI

This manual explains how to create interactive UI elements in the editor using editor scripts written in Lua. To get started with editor scripts, see [Editor Scripts manual](/manuals/editor-scripts). You can find the full editor API reference [here](/ref/stable/editor-lua/). Currently, it's only possible to create interactive dialogs, though we want to expand the UI scripting support to the rest of the editor in the future.

## Hello world

All UI-related functionality exists in the `editor.ui` module. Here is the simplest example of an editor script with a custom UI to get started:
```lua
local M = {}

function M.get_commands()
    return {
        {
            label = "Do with confirmation",
            locations = {"View"},
            run = function()
                local result = editor.ui.show_dialog(editor.ui.dialog({
                    title = "Perform action?",
                    buttons = {
                        editor.ui.dialog_button({
                            text = "Cancel",
                            cancel = true,
                            result = false
                        }),
                        editor.ui.dialog_button({
                            text = "Perform",
                            default = true,
                            result = true
                        })
                    }
                }))
                print('Perform action:', result)
            end
        }
    }
end

return M

```

This code snippet defines a **View → Do with confirmation** command. When you execute it, you will see the following dialog:

![Hello world dialog](images/editor_scripts/perform_action_dialog.png)

Finally, after pressing <kbd>Enter</kbd> (or clicking on the `Perform` button), you'll see the following line in the editor console:
```
Perform action:	true
```

## Basic concepts

### Components

The editor provides various UI **components** that can be composed to create the desired UI. By convention, all components are configured using a single table called **props**. The components themselves are not tables, but **immutable userdata** used by the editor for creating the UI.

### Props

**Props** are tables that define inputs into components. Props should be treated as immutable: mutating the props table in-place will not cause the component to re-render, but using a different table will. UI is updated when the component instance receives a props table that is not shallow-equal to the previous one.

### Alignment

When the component gets assigned some bounds in the UI, it will consume the whole space, though it does not mean that the visible part of the component will stretch. Instead, the visible part will take the space it needs, and then it will be aligned within the assigned bounds. Therefore, most built-in components define an `alignment` prop.

For example, consider this label component:
```lua
editor.ui.label({
    text = "Hello",
    alignment = editor.ui.ALIGNMENT.RIGHT
})
```
The visible part is the `Hello` text, and it's aligned within the assigned component bounds:

![Alignment](images/editor_scripts/alignment.png)

## Built-in components

The editor defines various built-in components that can be used together to build the UI. Components may be roughly grouped into 3 categories: layout, data presentation and input.

### Layout components

Layout components are used for placing other components next to each other. Main layout components are **`horizontal`**, **`vertical`** and **`grid`**. These components also define props such as **padding** and **spacing**, where padding is an empty space from the edge of the assigned bounds to the content, and spacing is an empty space between children:

![Padding and Spacing](images/editor_scripts/padding_and_spacing.png)

Editor defines `small`, `medium` and `large` padding and spacing constants. When it comes to spacing, `small` is intended for spacing between different sub-elements of an individual UI element, `medium` is for spacing between individual UI elements, and `large` is a spacing between groups of elements. Default spacing is `medium`. A padding value of `large` means padding from the edges of the window to content, `medium` is padding from the edges of a significant UI element, and `small` is a padding from the edges of small UI elements like context menus and tooltips (not implemented yet).

A **`horizontal`** container places its children one after another horizontally, always making the height every child fill the available space. By default, the width of every child is kept to a minimum, though it's possible to make it take as much space as possible by setting `grow` prop to `true` on a child.

A **`vertical`** container is similar to horizontal, but with the axes switched.

Finally, **`grid`** is a container component that lays out its children in a 2D grid, like a table. The `grow` setting in a grid applies to rows or columns, therefore it's set not on a child, but on column configuration table. Also, children in a grid may be configured to span multiple rows or columns with `row_span` and `column_span` props. Grids are useful for creating multi-input forms:
```lua
editor.ui.grid({
    padding = editor.ui.PADDING.LARGE, -- add padding around dialog edges
    columns = {{}, {grow = true}}, -- make 2nd column grow
    children = {
        {
            editor.ui.label({ 
                text = "Level Name",
                alignment = editor.ui.ALIGNMENT.RIGHT
            }),
            editor.ui.string_field({})
        },
        {
            editor.ui.label({ 
                text = "Author",
                alignment = editor.ui.ALIGNMENT.RIGHT
            }),
            editor.ui.string_field({})
        }
    }
})
```
The code above will produce the following dialog form:

![New Level Dialog](images/editor_scripts/new_level_dialog.png)

### Data presentation components

The editor defines 4 data presentation components:
- **`label`** — text label, intended to be used with form inputs.
- **`icon`** — an icon; currently, it can only be used for presenting a small set of predefined icons, but we intend to allow more icons in the future.
- **`heading`** — text element intended for presenting a heading line of text in e.g. a form or a dialog. The `editor.ui.HEADING_STYLE` enum defines various heading styles that include HTML's `H1`-`H6` heading, as well as editor-specific `DIALOG` and `FORM`.
- **`paragraph`** — text element intended for presenting a paragraph of text. The main difference with `label` is that paragraph supports word wrapping: if the assigned bounds are too small horizontally, the text will wrap, and possibly will be shortened with `"..."` if it can't fit in the view.

### Input components

Input components are made for the user to interact with the UI. All input components support `enabled` prop to control if the interaction is enabled or not, and define various callback props that notify the editor script on interaction.

If you create a static UI, it's enough to define callbacks that simply modify locals. For dynamic UIs and more advanced interactions, see [reactivity](#reactivity).

For example, it's possible to create a simple static New File dialog like so:
```lua
-- initial file name, will be replaced by the dialog
local file_name = ""
local create_file = editor.ui.show_dialog(editor.ui.dialog({
    title = "Create New File",
    content = editor.ui.horizontal({
        padding = editor.ui.PADDING.LARGE,
        spacing = editor.ui.SPACING.MEDIUM,
        children = {
            editor.ui.label({
                text = "New File Name",
                alignment = editor.ui.ALIGNMENT.CENTER
            }),
            editor.ui.string_field({
                grow = true,
                text = file_name,
                -- Typing callback:
                on_value_changed = function(new_text)
                    file_name = new_text
                end
            })
        }
    }),
    buttons = {
        editor.ui.dialog_button({ text = "Cancel", cancel = true, result = false }),
        editor.ui.dialog_button({ text = "Create File", default = true, result = true })
    }
}))
if create_file then
    print("create", file_name)
end
```
Here is a list of built-in input components:
- **`string_field`**, **`integer_field`** and **`number_field`** are variations of a single-line text field that allow editing strings, integers, and numbers.
- **`select_box`** is used for selecting an option from predefined array of options with a dropdown control.
- **`check_box`** is a boolean input field with `on_value_changed` callback
- **`button`** with `on_press` callback that gets invoked on button press.
- **`external_file_field`** is a component intended for selecting a file path on the computer. It consists of a text field and a button that opens a file selection dialog.
- **`resource_field`** is a component intended for selecting a resource in the project.

All components except buttons allow setting an `issue` prop that displays the issue related to the component (either `editor.ui.ISSUE_SEVERITY.ERROR` or `editor.ui.ISSUE_SEVERITY.WARNING`), e.g.:
```lua
issue = {severity = editor.ui.ISSUE_SEVERITY.WARNING, message = "This value is deprecated"}
```
When issue is specified, it changes how the input component looks, and adds a tooltip with the issue message.

Here is a demo of all inputs with their issue variants:

![Inputs](images/editor_scripts/inputs_demo.png)

### Dialog-related components

To show a dialog, you need to use `editor.ui.show_dialog` function. It expects a **`dialog`** component that defines the main structure of Defold dialogs: `title`, `header`, `content` and `buttons`. Dialog component is a bit special: you can't use it as a child of another component, because it represents a window, not a UI element. `header` and `content` are usual components though.

Dialog buttons are special too: they are created using **`dialog_button`** component. Unlike usual buttons, dialog buttons don't have `on_pressed` callback. Instead, they define a `result` prop with a value that will be returned by the `editor.ui.show_dialog` function when the dialog is closed. Dialog buttons also define `cancel` and `default` boolean props: button with a `cancel` prop is triggered when user presses <kbd>Escape</kbd> or closes the dialog with the OS close button, and `default` button is triggered when the user presses <kbd>Enter</kbd>. A dialog button may have both `cancel` and `default` props set to `true` at the same time.

### Utility components

Additionally, the editor defines some utility components: 
- **`separator`** is a thin line used for delimiting blocks of content
- **`scroll`** is a wrapper component that shows scroll bars when the wrapped component does not fit in the assigned space

## Reactivity

Since components are **immutable userdata**, it's impossible to change them after they are created. How to make the UI change over time then? The answer: **reactive components**. 

::: sidenote
The editor scripting UI draws inspiration from [React](https://react.dev/) library, so knowing about reactive UI and React hooks will help. 
:::

In the most simple terms, a reactive component is a component with a Lua function that receives data (props) and returns view (another component). Reactive component function may use **hooks**: special functions in the `editor.ui` module that add reactive features to your components. By convention, all hooks have a name that starts with `use_`.

To create a reactive component, use `editor.ui.component()` function. 

Let's have a look at this example — a New File dialog that only allows creating a file if the entered file name is not empty:

```lua
-- 1. dialog is a reactive component
local dialog = editor.ui.component(function(props)
    -- 2. the component defines a local state (file name) that defaults to empty string
    local name, set_name = editor.ui.use_state("")

    return editor.ui.dialog({ 
        title = props.title,
        content = editor.ui.vertical({
            padding = editor.ui.PADDING.LARGE,
            children = { 
                editor.ui.string_field({ 
                    value = name,
                    -- 3. typing + Enter updates the local state
                    on_value_changed = set_name 
                }) 
            }
        }),
        buttons = {
            editor.ui.dialog_button({ 
                text = "Cancel", 
                cancel = true 
            }),
            editor.ui.dialog_button({ 
                text = "Create File",
                -- 4. creation is enabled when the name exists
                enabled = name ~= "",
                default = true,
                -- 5. result is the name
                result = name
            })
        }
    })
end)

-- 6. show_dialog will either return non-empty file name or nil on cancel
local file_name = editor.ui.show_dialog(dialog({ title = "New File Name" }))
if file_name then 
    print("create " .. file_name)
else
    print("cancelled")
end
```

When you execute a menu command that runs this code, the editor will show a dialog with disabled `"Create File"` dialog at the start, but, when you type a name and press <kbd>Enter</kbd>, it will become enabled:

![New File Dialog](images/editor_scripts/reactive_new_file_dialog.png)

So, how does it work? On the very first render, `use_state` hook creates a local state associated with the component and returns it with a setter for the state. When the setter function is invoked, it schedules a component re-render. On subsequent re-renders, the component function is invoked again, and `use_state` returns the updated state. New view component returned by the component function is then diffed against the old one, and the UI is updated where the changes were detected.

This reactive approach greatly simplifies building interactive UIs and keeping them in sync: instead of explicitly updating all affected UI components on user input, the view is defined as a pure function of the input (props and local state), and the editor handles all the updates itself.

### Rules of reactivity

The editor expects reactive function components to behave nicely for them to work:

1. Component functions must be pure. There is no guarantee on when or how often the component function will be invoked. All side-effects should be outside of rendering, e.g. in callbacks
2. Props and local state must be immutable. Don't mutate props. If your local state is a table, don't mutate it in-place, but create a new one and pass it to the setter when the state needs to change.
3. Component functions must call the same hooks in the same order on every invocation. Don't call hooks inside loops, in conditional blocks, after early returns etc. It is a best practice to call hooks in the beginning of the component function, before any other code.
4. Only call hooks from component functions. Hooks work in a context of a reactive component, so it's only allowed to call them in the component function (or another function called directly by the component function).

### Hooks

::: sidenote
If you are familiar with [React](https://react.dev/), you will notice that hooks in the editor have slightly different semantics when it comes to hook dependencies.
:::

The editor defines 2 hooks: **`use_memo`** and **`use_state`**.

### **`use_state`**

Local state can be created in 2 ways: with a default value or with an initializer function:
```lua
-- default value
local enabled, set_enabled = editor.ui.use_state(true)
-- initializer function + args
local id, set_id = editor.ui.use_state(string.lower, props.name)
```
Similarly, setter can be invoked with a new value or with an updater function:
```lua
-- updater function
local function increment_by(n, by)
    return n + by
end

local counter = editor.ui.component(function(props)
    local count, set_count = editor.ui.use_state(0)
    
    return editor.ui.horizontal({
        spacing = editor.ui.SPACING.SMALL,
        children = {
            editor.ui.label({
                text = tostring(count),
                alignment = editor.ui.ALIGNMENT.LEFT,
                grow = true
            }),
            editor.ui.text_button({
                text = "+1",
                on_pressed = function() set_count(increment_by, 1) end
            }),
            editor.ui.text_button({
                text = "+5",
                on_pressed = function() set_count(increment_by, 5) end
            })
        }
    })
end)
```

Finally, the state may be **reset**. The state is reset when any of the arguments to `editor.ui.use_state()` change, checked with `==`. Because of this, you must not use literal tables or literal initializer functions as arguments to `use_state` hook: this will cause the state to reset on every re-render. To illustrate:
```lua
-- ❌ BAD: literal table initializer causes state reset on every re-render
local user, set_user = editor.ui.use_state({ first_name = props.first_name, last_name = props.last_name})

-- ✅ GOOD: use initializer function outside of component function to create table state
local function create_user(first_name, last_name) 
    return { first_name = first_name, last_name = last_name}
end
-- ...later, in component function:
local user, set_user = editor.ui.use_state(create_user, props.first_name, props.last_name)


-- ❌ BAD: literal initializer function causes state reset on every re-render
local id, set_id = editor.ui.use_state(function() return string.lower(props.name) end)

-- ✅ GOOD: use referenced initializer function to create the state
local id, set_id = editor.ui.use_state(string.lower, props.name)
```

### **`use_memo`**

You can use `use_memo` hook to improve performance. It is common to perform some computations in the render functions, e.g. to check if the user input is valid. `use_memo` hook can be used in cases where checking if arguments to the computation function have changed is cheaper than invoking the computation function. The hook will call the computation function on first render, and will re-use the computed value on subsequent re-renders if all the arguments to `use_memo` are unchanged:
```lua
-- validation function outside of component function
local function validate_password(password)
    if #password < 8 then
        return false, "Password must be at least 8 characters long."
    elseif not password:match("%l") then
        return false, "Password must include at least one lowercase letter."
    elseif not password:match("%u") then
        return false, "Password must include at least one uppercase letter."
    elseif not password:match("%d") then
        return false, "Password must include at least one number."
    else
        return true, "Password is valid."
    end
end

-- ...later, in component function
local username, set_username = editor.ui.use_state('')
local password, set_password = editor.ui.use_state('')
local valid, message = editor.ui.use_memo(validate_password, password)
```
In this example, password validation will run on every password change (e.g. on typing in a password field), but not when the username is changed.

Another use-case for `use_memo` is creating callbacks that are then used on input components, or when a locally-created function is used as a prop value for another component — this prevents unnecessary re-renders.


---
title: Editor styling
brief: You can modify the colors, typography and other visual aspects of the editor using a custom stylesheet.
---

# Editor styling

You can modify the colors, typography and other visual aspects of the editor using a custom stylesheet:

* Create a folder named `.defold` in your user home directory.
  * On Windows `C:\Users\**Your Username**\.defold`
  * On macOS `/Users/**Your Username**/.defold`
  * On Linux `~/.defold`
* Create a `editor.css` file in the `.defold` folder

The editor will on startup load your custom stylesheet and apply it on top of the default style. The editor uses JavaFX for the user interface and the stylesheets are almost identical to the CSS files used in a browser to apply style attributes to the elements of a webpage. The default stylesheets for the editor are [available for inspection on GitHub](https://github.com/defold/defold/tree/editor-dev/editor/styling/stylesheets/base).

## Changing color

The default colors are defined in [`_palette.scss`](https://github.com/defold/defold/blob/editor-dev/editor/styling/stylesheets/base/_palette.scss) and look like this:

```
* {
	// Background
	-df-background-darker:    derive(#212428, -10%);
	-df-background-dark:      derive(#212428, -5%);
	-df-background:           #212428;
	-df-background-light:     derive(#212428, 10%);
	-df-background-lighter:   derive(#212428, 20%);

	// Component
	-df-component-darker:     derive(#464c55, -20%);
	-df-component-dark:       derive(#464c55, -10%);
	-df-component:            #464c55;
	-df-component-light:      derive(#464c55, 10%);
	-df-component-lighter:    derive(#464c55, 20%);

	// Text & icons
	-df-text-dark:            derive(#b4bac1, -10%);
	-df-text:                 #b4bac1;
	-df-text-selected:        derive(#b4bac1, 20%);

  and so on...
```

The basic theme is divided into three groups of colors (with darker and lighter variants):

* Background color - background color in panels, windows, dialogs
* Component color - buttons, scroll bar handles, text field outlines
* Text color - text and icons

As an example, if you add this to your custom `editor.css` stylesheet in `.defold` folder in user home:

```
* {
	-df-background-darker:    derive(#0a0a42, -10%);
	-df-background-dark:      derive(#0a0a42, -5%);
	-df-background:           #0a0a42;
	-df-background-light:     derive(#0a0a42, 10%);
	-df-background-lighter:   derive(#0a0a42, 20%);
}
```

You will get the following look in your editor:

![](images/editor/editor-styling-color.png)


## Changing fonts

The editor uses two fonts: `Dejavu Sans Mono` for code and mono spaced text (errors) and `Source Sans Pro` for the rest of the UI. The font definitions are mainly found in [`_typography.scss`](https://github.com/defold/defold/blob/editor-dev/editor/styling/stylesheets/base/_typography.scss) and look like this:

```
@font-face {
  src: url("SourceSansPro-Light.ttf");
}

@font-face {
  src: url("DejaVuSansMono.ttf");
}

$default-font-mono: 'Dejavu Sans Mono';
$default-font: 'Source Sans Pro';
$default-font-bold: 'Source Sans Pro Semibold';
$default-font-italic: 'Source Sans Pro Italic';
$default-font-light: 'Source Sans Pro Light';

.root {
    -fx-font-size: 13px;
    -fx-font-family: $default-font;
}

Text.strong {
  -fx-font-family: $default-font-bold;
}

and so on...
```

The main font is defined in a root element which makes it quite easy to replace the font in most places. Add this to your `editor.css`:

```
@import url('https://fonts.googleapis.com/css2?family=Architects+Daughter&display=swap');

.root {
    -fx-font-family: "Architects Daughter";
}
```

You will get the following look in your editor:

![](images/editor/editor-styling-fonts.png)

It is also possible to use a local font instead of a web font:

```
@font-face {
  font-family: 'Comic Sans MS';
  src: local("cs.ttf");
}

.root {
  -fx-font-family: 'Comic Sans MS';
}
```

::: sidenote
The code editor font is defined separately in the editor Preferences!
:::

---
title: Editor overview
brief: This manual gives an overview on how the Defold editor look and works, and how to navigate in it.
---

# Editor overview

The editor allows you to browse and manipulate all files in your game project in an efficient manner. Editing files brings up a suitable editor and shows all relevant information about the file in separate views.

## Starting the editor

When you run the Defold editor, you are presented with a project selection and creation screen. Click to select what you want to do:

Home
: Click to show your recently opened projects so you can quickly access them. This is the default view.

New Project
: Click if you want to create a new Defold project, then select if you want to base your project on a basic template (from the *From Template* tab), if you would like to follow a tutorial (the *From Tutorial* tab), or try one of the sample projects (the *From Sample* tab).

  ![new project](images/editor/new_project.png)

  When you create a new project it is stored on your local drive and any edits you do are saved locally.

You can learn more about the different options in the [Project Setup manual](https://www.defold.com/manuals/project-setup/).

## The editor panes

The Defold editor is separated into a set of panes, or views, that display specific information.

![Editor 2](images/editor/editor2_overview.png)

The *Assets* pane
: Lists all the files that are part of your project. Click and scroll to navigate the list. All file oriented operations can be made in this view:

   - <kbd>Double click</kbd> a file to open it in an editor for that file type.
   - <kbd>Drag and drop</kbd> to add files from elsewhere on your disk to the project or move files and folders to new locations in the project.
   - <kbd>Right click</kbd> to open a _context menu_ from where you can create new files or folders, rename, delete, track file dependencies and more.

### Editor pane
The center view shows the currently open file in an editor for that file type. All visual editors allows you to change the camera view:

- Pan: <kbd>Alt + left mouse button</kbd>.
- Zoom: <kbd>Alt + Right button</kbd> (three button mouse) or <kbd>Ctrl + Mouse button</kbd> (one button). If your mouse has a scroll wheel, it can be used to zoom.
- Rotate in 3D: <kbd>Ctrl + left mouse button</kbd>.

There is a toolbar in the top right corner of the scene view where you find object manipulation tools: *Move*, *Rotate* and *Scale* as well as *2D Mode*, *Camera Perspective* and *Visibility Filters*.

![toolbar](images/editor/toolbar.png)

### Outline pane

This view shows the content of the file currently being edited, but in a hierarchical tree structure. The outline reflects the editor view and allows you to perform operations on your items:
   - <kbd>Click</kbd> to select an item. Hold <kbd>Shift</kbd> or <kbd>Option</kbd> to expand the selection.
   - <kbd>Drag and drop</kbd> to move items. Drop a game object on another game object in a collection to child it.
   - <kbd>Right click</kbd> to open a _context menu_ from where you can add items, delete selected items etc.

It is possible to toggle the visibility of game objects and visual components by clicking on the little eye icon to the right of an element in the list (Defold 1.9.8 and newer).

![toolbar](images/editor/outline.png)

### Properties pane

This view shows properties associated with the currently selected item, like Position, Rotation, Animation etc, etc.

### Tools pane

This view has several tabs. The *Console* tab shows any error output or purposeful printing that you do while your game is running. Alongside the console are tabs containing *Build Errors*, *Search Results* and the *Curve Editor* which is used when editing curves in the particle editor. The Tools pane is also used for interacting with the integrated debugger.

### Changed Files pane

If your project uses the distributed version-control system Git this view lists any files that has been changed, added or deleted in your project. By synchronizing the project regularly you can bring your local copy in sync with what is stored in the project Git repository, that way you can collaborate within a team, and you won’t lose your work if disaster strikes. You can learn more about Git in our [Version Control manual](/manuals/version-control/). Some file oriented operations can be performed in this view:

   - <kbd>Double click</kbd> a file to open a diff view of the file. The editor opens the file in a suitable editor, just like in the assets view.
   - <kbd>Right click</kbd> a file to open a pop up menu from where you can open a diff view, revert all changes done to the file, find the file on the filesystem and more.


## Side-by-side editing

If you have multiple files open, a separate tab for each file is shown at the top of the editor view. It is possible to open 2 editor views side by side. <kbd>Right click</kbd> the tab for the editor you want to move and select <kbd>Move to Other Tab Pane</kbd>.

![2 panes](images/editor/2-panes.png)

You can also use the tab menu to swap the position of the two panes and join them to a single pane.

## The scene editor

Double clicking a collection or game object file brings up the *Scene Editor*:

![Select object](images/editor/select.png)

### Selecting objects
Click on objects in the main window to select them. The rectangle surrounding the object in the editor view will highlight green to indicate what item is selected. The selected object is also highlighted in the *Outline* view.

  You can also select objects by:

  - <kbd>Click and drag</kbd> to select all objects inside the selection region.
  - <kbd>Click</kbd> objects in the Outline view.

  Hold <kbd>Shift</kbd> or <kbd>⌘</kbd> (Mac) / <kbd>Ctrl</kbd> (Win/Linux) while clicking to expand the selection.

### Move tool
![Move tool](images/editor/icon_move.png){.left}
To move objects, use the *Move Tool*. You find it in the toolbar in the top right corner of the scene editor, or by pressing the <kbd>W</kbd> key.

![Move object](images/editor/move.png)

The selected object shows a set of manipulators (squares and arrows). Click and drag the green center square handle to move the object freely in screen space, click and drag the arrows to move the object along the X, Y or Z-axis. There are also square handles for moving the object in the X-Y plane and (visible if rotating the camera in 3D) for moving the object in the X-Z and Y-Z planes.

### Rotate tool
![Rotate tool](images/editor/icon_rotate.png){.left}
To rotate objects, use the *Rotate Tool* by selecting it in the toolbar, or by pressing the <kbd>E</kbd> key.

![Move object](images/editor/rotate.png)

This tool consists of four circular manipulators. An orange manipulator that rotates the object in screen space and one for rotation around each of the X, Y and Z axes. Since the view is perpendicular to the X- and Y-axis, the circles only appear as two lines crossing the object.


### Scale tool
![Scale tool](images/editor/icon_scale.png){.left}
To scale objects, use the *Scale Tool* by selecting it in the toolbar, or by pressing the <kbd>R</kbd> key.

![Scale object](images/editor/scale.png)

This tool consists of a set of square handles. The center one scales the object uniformly in all axes (including Z). There also one handle for scaling along each of the X, Y and Z axes and one handle for scaling in the X-Y plane, the X-Z plane and the Y-Z plane.


### Visibility filters
Toggle visibility of various component types as well as bounding boxes and guide lines.

![Visibility filters](images/editor/visibilityfilters.png)


## Creating new project files

To create new resource files, either select <kbd>File ▸ New...</kbd> and then choose the file type from the menu, or use the context menu:

<kbd>Right click</kbd> the target location in the *Assets* browser, then select <kbd>New... ▸ [file type]</kbd>:

![create file](images/editor/create_file.png)

Type a suitable name for the new file. The full file name including the file type suffix is shown under *Path* in the dialog:

![create file name](images/editor/create_file_name.png)

It is possible to specify custom templates for each project. To do so, create a new folder named `templates` in the project’s root directory, and add new files named `default.*` with the desired extensions, such as `/templates/default.gui` or `/templates/default.script`. Additionally, if the `{{NAME}}` token is used in these files, it will be replaced with the filename specified in the file creation window.

## Importing files to your project

To add asset files (images, sounds, models etc) to your project, simply drag and drop them to the correct position in the *Assets* browser. This will make _copies_ of the files at the selected location in the project file structure. Read more about [how to import assets in our manual](/manuals/importing-assets/).

![Import files](images/editor/import.png)

## Updating the editor

The editor will automatically check for updates. When an update is detected it will be shown in the lower right corner of the editor window and on the project selection screen. Pressing the Update Available link will download and update the editor.

![Update from project selection](images/editor/update-project-selection.png)

![Update from editor](images/editor/update-main.png)

## Preferences

You can modify the settings of the editor [from the Preferences window](/manuals/editor-preferences).

## Editor logs
If you run into a problem with the editor and need to [report an issue](/manuals/getting-help/#getting-help) it is a good idea to provide log files from the editor itself. The editor logs files can be found here:

  * Windows: `C:\Users\ **Your Username** \AppData\Local\Defold`
  * macOS: `/Users/ **Your Username** /Library/Application Support/` or `~/Library/Application Support/Defold`
  * Linux: `$XDG_STATE_HOME/Defold` or `~/.local/state/Defold`

You can also get access to editor logs while the editor is running if it is started from a terminal/command prompt. To launch the editor from the terminal on macOS:

```
$ > ./path/to/Defold.app/Contents/MacOS/Defold
```

## Editor server

When the editor opens a project, it will start a web server on a random port. The server may be used to interact with the editor from other applications. Since 1.11.0, the port is written to the `.internal/editor.port` file.

Additionally, since 1.11.0 the editor executable has a command line option `--port` (or `-p`), which allows specifying the port during launch, e.g.::
```shell
# on Windows
.\Defold.exe --port 8181

# on Linux:
./Defold --port 8181

# on macOS:
./Defold.app/Contents/MacOS/Defold --port 8181
```



Tip: You can use touch and drag to rotate the scene. If you are reading this on a computer, you can even use WASD controls! Don’t tell the mobile users what Q and E do!
It’s just files, right?

Since most defold assets are edited as textual protobuf files, and the protobuf definitions are published with every release, it was always possible to edit them — they are just files, after all. First, let’s start with an editor script that creates “just files”. Then, we will discuss the problems with files, and when it makes sense to use another approach. In this post, we will implement a realistic use case that you might want to automate when working with Defold: importing asset packs.

Let’s say you want to use Kenney’s beautiful Castle Kit for a fantasy city builder prototype. You download the pack and extract the GLB models to the project folder. Now, to use the assets in a scene, you need to create game objects for the models. Let’s try creating a single one manually for now. We will also use Dragosha’s wonderful light-and-shadows pack for shading, so we will need to set up some custom materials on a model.

Here is how a manually-made game object looks:

To create it, we need to make a new game object with an embedded model component. Then, we set the following properties on a model:

    Mesh — points to the GLB file from Kenney’s asset pack
    colormap — material that casts shadows, from Dragosha’s pack
    tex0 — image to colorize the model

It would be time-consuming to repeat these steps for every model, so let’s write a simple editor script to automate it.
Editor Script Part 1: a Command

Let’s start with creating an .editor_script file and removing all the boilerplate:

local M = {}

function M.get_commands()
    return {}
end

return M

Now, let’s modify M.get_commands() to return a command that prints a message when executed. Start small.

return {
    editor.command({
        label = "Generate models",
        locations = {"Edit"},
        id = "app.generate-models",
        run = function()
            print("Lets go!")
        end
    })
}

Tip: if you create a command with an id, you can then open File → Preferences and assign a shortcut to this command in a Keymap tab. This comes in handy when iterating on editor scripts. I picked Ctrl+G, where G is a mnemonic for Generate.

Now, if you reload editor scripts (Project → Reload Editor Scripts or Cmd+Shift+R) and run the command (either using Edit → Generate Models, or a custom shortcut), you will see Lets go! printed in the console — we are ready to proceed.
Editor Script Part 2: Generating Game Objects

Let’s have a look at the game object file as a text:

embedded_components {
  id: "model"
  type: "model"
  data: "mesh: \"/assets/GLB format/siege-tower.glb\"\n"
  "name: \"\"\n"
  "materials {\n"
  "  name: \"colormap\"\n"
  "  material: \"/builtins/materials/model.material\"\n"
  "  textures {\n"
  "    sampler: \"tex0\"\n"
  "    texture: \"/assets/GLB format/Textures/colormap.png\"\n"
  "  }\n"
  "}\n"
  ""
}

Source files use a protobuf text format. Our embedded model is embedded as an escaped protobuf text. This happens because protobuf does not support generic message types, so we have to emulate them. Not very convenient, but we still prefer to use the format because protobuf resources can be compiled to very small binaries, and we care about small bundle sizes. Anyway, when creating files, we will only need to replace the siege-tower part with a model name, so let’s make it a template:

local template = [[embedded_components {
  id: "model"
  type: "model"
  data: "mesh: \"/assets/GLB format/%s.glb\"\n"
  "name: \"\"\n"
  "materials {\n"
  "  name: \"colormap\"\n"
  "  material: \"/builtins/materials/model.material\"\n"
  "  textures {\n"
  "    sampler: \"tex0\"\n"
  "    texture: \"/assets/GLB format/Textures/colormap.png\"\n"
  "  }\n"
  "}\n"
  ""
}
]]

As you can see, the name is replaced with %s — we will use template:format(name) to create .go files.

We will use the new editor.create_resources() function to create all the files at once — it is significantly more performant than using Lua’s utilities for writing files. To create multiple files with custom content, we will need to call it with a list of tuples: file names and contents. For example, it might look like that:

editor.create_resources({
    {"/assets/models/get/siege-tower.go", template:format("siege-tower")}
})

Now, let’s change the run function to create game objects for all the models:

-- select and clear the directory for generated assets
local root_dir = "/assets/models/gen"
editor.delete_directory(root_dir)
-- list all assets from the asset pack
local assets = editor.get("/assets/GLB format", "children")
-- this is the argument to `editor.create_resources()`:
local resources = {}
for i = 1, #assets do
    local glb_path = assets[i]
    local base_name = glb_path:match("([^/]+)%.glb$")
    if base_name then
        local go = root_dir .. "/" .. base_name .. ".go"
        resources[#resources+1] = {go, template:format(base_name)}
    end
end
editor.create_resources(resources)

Try reloading the editor scripts and executing the command again: it will create a game object for every model — these can be used for making scenes! Nice!

When files are not enough

So far, we have a simple file-based API to import assets, nothing fancy here. But using file formats is much harder when you want to create complex scenes. For example, collections are trees of game objects, but the file format of a collection is a flat list, where game objects refer to their children by ids. It’s inconvenient to take a tree and then convert it to such a flat list. Additionally, there is an extra complication: since a file format uses ids to refer to children, there is a requirement — but only in the file format — that every id must be specified, and unique. But when creating a collection, in a lot of cases you don’t care about ids of game objects that exist only to place something in a scene. So.

The problem is this — sometimes, you don’t want to think in terms of file formats. When it comes to scenes, you want to edit them as scenes. And this is exactly what we’ve been working on for the last 2 months. You can edit collections and GUIs as trees, and the editor will handle file formats and generate ids for you. You can edit tilemaps as 2D grids. Et cetera.

Now, let’s compose a scene!
Editor script part 3: making a collection

We are going to place the created game objects in a scene to preview all of them together. Additionally, let’s show a label with the name of the asset alongside every model. This is what we are going to do in the final part of the editor script:

First, let’s create an empty /assets/all.collection. Then, we will edit its children — the children property — using the editor’s built-in transactional editing API. This API is very useful for making commands that group multiple edits in a single undoable step, though it doesn’t matter much in our case. If simplified, the code would look something like this:

local coll = "/assets/models/all.collection"
editor.transact({
    editor.tx.add(coll, "children", {
        -- add referenced game object
        type = "go-reference",
        path = "/assets/models/gen/siege-tower.go",
        children = {
            -- add embedded game object with a label
            {
                type = "go",
                components = {
                    {type = "label", text = "siege-tower"}
                }
            }
        }
    })
})

Now let’s implement the real thing. We already have a resources array with tuples of game object paths + their contents. Let’s use it to edit the scene. We need to add the following code at the bottom of the run handler:

local coll = "/assets/models/all.collection"
-- txs array, start by clearing the collections, so we don't add 
-- too many items when re-generating the assets
local edit_txs = { editor.tx.clear(coll, "children") }

local row = math.floor(math.sqrt(#resources))
local half = math.floor(row / 2)
for i = 1, #resources do
    local go = resources[i][1]
    local x = (i - 1) % row
    local z = math.floor(i/row)
    edit_txs[#edit_txs+1] = editor.tx.add(coll, "children", {
        type = "go-reference",
        path = go,
        -- position all objects around 0,0
        position = {- (x - half) * 1.5, 0, - (z - half) * 1.5},
        children = {
            {
                -- no id necessary, it's auto-generted when omitted
                type = "go",
                scale = {0.007, 0.007, 0.007},
                position = {0, 0.2, 0.7},
                components = {
                    {
                        type = "label",
                        text = go:match("([^/]+)%.go$"),
                        font = "/main/font.font",
                        material = "/builtins/fonts/label.material"
                    }
                }
            }
        }
    })
end
editor.transact(edit_txs)
-- we don't care about undo here, might as well save:
editor.save()

And voila, that’s how it’s done! Reload editor scripts, re-run the command, and you’ll have a collection with every item.
P.S.

If you want to learn more, check out the editor scripting docs. Here is the code for the demo, and here is the full editor script source. Note that collection editing and editor.create_resources() are only available in Defold version 1.10.4, which, at the time of writing, has not been released yet.

We’d be happy to talk more about other, already released editing capabilities, such as tilemaps, but this post is already getting too long. Some other time, maybe?

Meanwhile, happy Defolding!

New editor script feature just got released: Outline Properties :tada:

Now your commands can target any item in the Outline View using "outline" query type. editor.get() now has access to properties displayed in Properties View. Since some of these properties are sometimes read-only, and sometimes unavailable, new API is added: editor.can_get() and editor.can_set() to check them beforehand. Hover over property names in Properties view to see how they are named in editor scripts.

{
    locations = {"Outline"},
    label = "Reset Transform",
    query = {selection = {
       type = "outline", cardinality = "one"
    }},
    active = function(opts) 
        local id = opts.selection
        return editor.can_set(id, "position") 
               or editor.can_set(id, "rotation") 
               or editor.can_set(id, "scale")
    end,
    run = function(opts)
        local id = opts.selection
        local ret = {}
        if editor.can_set(id, "position") then
            table.insert(ret, {
                action = "set", 
                node_id = id, 
                property = "position", 
                value = {0, 0, 0}
            })
        end
        if editor.can_set(id, "rotation") then
            table.insert(ret, {
                action = "set", 
                node_id = id, 
                property = "rotation", 
                value = {0, 0, 0}
            })
        end
        if editor.can_set(id, "scale") then
            table.insert(ret, {
                action = "set", 
                node_id = id, 
                property = "scale", 
                value = {1, 1, 1}
            })
        end
        return ret
    end
}

# Example Editor Scripts

## gen_models.editor_script

local M = {}

local template = [[embedded_components {
  id: "model"
  type: "model"
  data: "mesh: \"/assets/GLB format/%s.glb\"\n"
  "name: \"{{NAME}}\"\n"
  "materials {\n"
  "  name: \"colormap\"\n"
  "  material: \"/builtins/materials/model.material\"\n"
  "  textures {\n"
  "    sampler: \"tex0\"\n"
  "    texture: \"/assets/GLB format/Textures/colormap.png\"\n"
  "  }\n"
  "}\n"
  ""
}
]]

function M.get_commands()
    return {
        editor.command({
            label = "Generate models",
            locations = {"Edit"},
            id = "game.generate-models",
            run = function()
                local assets = editor.get("/assets/GLB format", "children")
                local root_dir = "/assets/models/gen"
                editor.delete_directory(root_dir)
                local resources = {}
                for i = 1, #assets do
                    local glb_path = assets[i]
                    local base_name = glb_path:match("([^/]+)%.glb$")
                    if base_name then
                        local go = root_dir .. "/" .. base_name .. ".go"
                        resources[#resources+1] = {go, template:format(base_name)}
                    end
                end
                editor.create_resources(resources)

                local coll = "/assets/models/all.collection"
                local edit_txs = {editor.tx.clear(coll, "children")}

                local row = math.floor(math.sqrt(#resources))
                local half = math.floor(row / 2)
                for i = 1, #resources do
                    local go = resources[i][1]
                    local x = (i - 1) % row
                    local z = math.floor(i/row)
                    edit_txs[#edit_txs+1] = editor.tx.add(coll, "children", {
                        type = "go-reference",
                        path = go,
                        position = {- (x - half) * 1.5, 0, - (z - half) * 1.5},
                        children = {
                            {
                                type = "go",
                                scale = {0.007, 0.007, 0.007},
                                position = {0, 0.2, 0.7},
                                components = {
                                    {
                                        type = "label",
                                        text = go:match("([^/]+)%.go$"),
                                        font = "/main/font.font",
                                        material = "/builtins/fonts/label.material"
                                    }
                                }
                            }
                        }
                    })
                end
                editor.transact(edit_txs)
                editor.save()
            end
        })
    }
end

return M

## atlas.editor_script


local query = require "editor-script-atlas.query"
local dialogs = require "editor-script-atlas.dialogs"
local utils = require "editor-script-atlas.utils"

local M = {}


local function add_images_as_animation(opts)
    local animation_name = editor.ui.show_dialog(dialogs.name_dialog({ title = "Add images as animation" }))
    if animation_name == nil then
        return
    end
    local atlas = utils.get_atlas(opts)

    local images = {}
    for _, id in pairs(opts.selection) do
        local path = editor.get(id, "path")
        if not utils.ends_with(path, ".atlas") then
            table.insert(images, {image=path})
        end
    end
    editor.transact({editor.tx.add(atlas, "animations", {
        id=animation_name,
        images=images
    })})
end


local function add_images_as_images(opts)
    local atlas = utils.get_atlas(opts)
    local txs = {}
    for _, id in pairs(opts.selection) do
        local path = editor.get(id, "path")
        if not utils.ends_with(path, ".atlas") then
            table.insert(txs, editor.tx.add(atlas, "images", {image=path}))
        end
    end
    editor.transact(txs)
end


local function add_all_in_directory(atlas, directory, txs, recursive)
    local children = editor.get(directory, "children")
    for i = 1, #children do
        local resource_path = editor.get(children[i], "path")
        if utils.ends_with(resource_path, ".png") then
            table.insert(txs, editor.tx.add(atlas, "images", {image=resource_path}))
        end
        if recursive and editor.resource_attributes(resource_path).is_directory then
            add_all_in_directory(atlas, resource_path, txs, recursive)
        end
    end
end

local function add_folders_as_animations(atlas, directory, txs)
    local children = editor.get(directory, "children")
    for i = 1, #children do
        local resource_path = editor.get(children[i], "path")
        if utils.ends_with(resource_path, ".png") then
            table.insert(txs, editor.tx.add(atlas, "images", {image=resource_path}))
        end
        if editor.resource_attributes(resource_path).is_directory then
            local _, name, _ = utils.path_segments(resource_path)
            local grandchildren = editor.get(resource_path, "children")
            local images = {}
            for j = 1, #grandchildren do
                local grandchild_path = editor.get(grandchildren[j], "path")
                if utils.ends_with(grandchild_path, ".png") then
                    table.insert(images, {image=grandchild_path})
                end
            end
            if #images then
                table.insert(txs, editor.tx.add(atlas, "animations", {id = name, images=images}))
            end
        end
    end
end
    
local function create_atlas_from_folder(opts)
    local atlas = opts.selection .. ".atlas"
    
    local txs = {}

    -- If the atlas already exists we ask if we should continue
    if editor.resource_attributes(atlas).exists then
        local atlas_name = editor.ui.show_dialog(dialogs.yes_no_dialog({ title = "Resource exists", text = "Recreate the atlas?" }))
        if atlas_name == false then
            return
        end
        table.insert(txs, editor.tx.clear(atlas, "images"))
        table.insert(txs, editor.tx.clear(atlas, "animations"))
    else
        -- No atlas exists, create a new empty file.
        local atlas_file = io.open("." .. atlas, "w")
        if atlas_file == nil then
            return
        end
        atlas_file:write('')
        atlas_file:close()
    end

    
    if query.directory_contains_image_subdirectories(opts) then
        local creation_mode = editor.ui.show_dialog(dialogs.sub_directories_dialog({ title = "Subdirectories found.", text = "How do you want to create the atlas?" }))
        if creation_mode == 1 then
            add_all_in_directory(atlas, opts.selection, txs, false)
        elseif creation_mode == 2 then
            add_folders_as_animations(atlas, opts.selection, txs)
        elseif creation_mode == 3 then
            add_all_in_directory(atlas, opts.selection, txs, true)
        end
    else
        add_all_in_directory(atlas, opts.selection, txs)
    end

    editor.transact(txs)
end


local function add_images_to_new_atlas(opts)
    local atlas_name = editor.ui.show_dialog(dialogs.name_dialog({ title = "Create a new atlas" }))
    if atlas_name == nil then
        return
    end


    local base_path = utils.path_segments(editor.get(opts.selection[1], "path"))
    local atlas = base_path .. atlas_name .. ".atlas"

    local atlas_file = io.open("." .. atlas, "w")
    if atlas_file == nil then
        return
    end
    
    atlas_file:write('')
    atlas_file:close()
    
    local txs = {}
    for _, id in pairs(opts.selection) do
        local path = editor.get(id, "path")
        table.insert(txs, editor.tx.add(atlas, "images", {image=path}))
    end

    editor.transact(txs)
end


local function remove_duplicated_images(opts)
    local all_images = {}
    local txs = {}
    local atlas = editor.get(opts.selection, "path")
    local image_nodes = editor.get(atlas, "images")
    for i = 1, #image_nodes do
        local img = editor.get(image_nodes[i], "image")
        local _, name, _ = utils.path_segments(img)
        if all_images[name] then
            if img == all_images[name] then
                table.insert(txs, editor.tx.remove(opts.selection, "images", image_nodes[i]))
            else
                print("Found two textures that shares name, but has different paths.")
            end
        end
        all_images[name] = img
    end
    if #txs > 0 then
        editor.transact(txs)
    end
end


function M.get_commands()
    return {
        {
            label="Add images...",
            locations = {"Assets"},
            query = {
                selection = {type = "resource", cardinality = "many"}
            },
            active = query.images_and_atlas_are_selected,
            run = add_images_as_images
        },
        {
            label="Add images as animation...",
            locations = {"Assets"},
            query = {
                selection = {type = "resource", cardinality = "many"}
            },
            active = query.images_and_atlas_are_selected,
            run = add_images_as_animation
        },
        {
            label="Create New Atlas",
            locations = {"Assets"},
            query = {
                selection = {type = "resource", cardinality = "many"}
            },
            active = query.images_but_no_atlas_are_selected,
            run = add_images_to_new_atlas
        },
        {
            label="Create New Atlas",
            locations = {"Assets"},
            query = {
                selection = {type = "resource", cardinality = "one"}
            },
            active = query.directory_with_images_selected,
            run = create_atlas_from_folder
        },
        {
            label="Remove duplicated images",
            locations = {"Assets"},
            query = {
                selection = {type = "resource", cardinality = "one"}
            },
            active = query.atlas_selected,
            run = remove_duplicated_images
        }
    }
end

return M

local exists, defaults = pcall(require,"templates")

local M = {}

local _empty = {}

local dialog = editor.ui.component(function(props)
    local name, set_name = editor.ui.use_state("")

    return editor.ui.dialog({
        title= props.title,
        content = editor.ui.vertical({
            padding = editor.ui.PADDING_LARGE,
            children = {
                editor.ui.string_field({
                    value = name,
                    on_value_changed = set_name
                })
            }
        }),
        buttons = {
            editor.ui.dialog_button({
                text = "Cancel"
            }),
            editor.ui.dialog_button({
                text = "Add",
                enabled = name ~= "",
                default = true,
                result = name
            }),
        }
    })
end)


local function split_path(path)
    local parent, stem, suffix = path:match("(.-)([^\\/]-)(%.[^\\/]*)$")
    return parent, stem, suffix
end


local function copy_file(selection, template_path)
    local file_name = editor.ui.show_dialog(dialog({ title = "File name" }))
    
    local path = editor.get(selection, "path")
    local parent, _, _ = split_path(path)
    
    local _, _, out_suffix = split_path(template_path)

    local new_file_location = "." .. parent .. file_name .. out_suffix

    local template = io.open(template_path, "r")
    local template_content = template:read("*a")
    template:close()

    local new_file = io.open(new_file_location, "w")
    new_file:write(template_content)
    new_file:close()
end

local function generate_commands()
    if not exists then
        return _empty
    end

    local commands = {}
    for name, template_path in pairs(defaults) do
        table.insert(commands, {
            label = "Create " .. name,
            query = {
                selection = {type = "resource", cardinality = "one"}
            },
            locations = {"Assets"},
            run = function(opts)
                copy_file(opts.selection, template_path)
            end
        })
    end

    return commands
end

function M.get_commands()
    return generate_commands()
end

return M

## format_document.editor_script

local M = {}

local function ends_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

function M.get_commands()
    return {
        {
            label = "Format Document",
            locations = {"Edit", "Assets"},
            query = {selection = {type = "resource", cardinality = "one"}},
            active = function(opts)
                local path = editor.get(opts.selection, "path")
                return ends_with(path, ".lua") or ends_with(path, ".script") or
                           ends_with(path, ".editor_script") or
                           ends_with(path, ".gui_script") or
                           ends_with(path, ".render_script")
            end,
            run = function(opts)
                local path = editor.get(opts.selection, "path")
                path = path:sub(2)

                if editor.platform == "x86_64-win32" then
                    return {
                        {
                            action = "shell",
                            command = {
                                "cmd", "/C",
                                "editor-script-lua-format\\bin\\win32\\lua-format.exe",
                                "-i", path
                            }
                        }
                    }
                elseif editor.platform == "x86_64-darwin" then
                    return {
                        {
                            action = "shell",
                            command = {
                                "./editor-script-lua-format/bin/darwin/lua-format",
                                "-i", path
                            }
                        }
                    }
                elseif editor.platform == "x86_64-linux" then
                    return {
                        {
                            action = "shell",
                            command = {
                                "./editor-script-lua-format/bin/linux/lua-format",
                                "-i", path
                            }
                        }
                    }
                else
                    print("ERROR: Not supported platform")
                    return nil
                end
            end
        }
    }
end

return M

## z_order.editor_script

local M = {}

local Z_OFFSET = 0.01
local function shift(ids, direction)
    local commands = {}
    if type(ids) == 'table' then
    else
        ids = {ids}
    end
        
    for _, id in pairs(ids) do
        if editor.can_get(id, "position") then
            local position = editor.get(id, "position")
            position[3] = position[3] + direction*Z_OFFSET
            table.insert(commands, {
                action = "set",
                node_id = id,
                property = "position",
                value = position
            })
        end
    end
    return commands
end

local function set_z_through_y(ids)
    local commands = {}
    if type(ids) == 'table' then
    else
        ids = {ids}
    end
        
    for _, id in pairs(ids) do
        if editor.can_get(id, "position") then
            local position = editor.get(id, "position")
            position[3] = -position[2]*0.001
            table.insert(commands, {
                action = "set",
                node_id = id,
                property = "position",
                value = position
            })
        end
    end
    return commands
end

local function swap(ids)
    local commands = {}
    local num = #ids
    if num > 1 then 
        local a = ids[1]
        local b = ids[2]
        local a_position = editor.get(a, "position")
        local b_position = editor.get(b, "position")
        a_position[3], b_position[3] = b_position[3], a_position[3]
            table.insert(commands, {
                action = "set",
                node_id = a,
                property = "position",
                value = a_position
            })
            table.insert(commands, {
                action = "set",
                node_id = b,
                property = "position",
                value = b_position
            })
    end
    return commands
end

-- sort by y
local function order(ids, reset)
    local commands = {}
    local temp = {}
    
    for _, id in pairs(ids) do
        if editor.can_get(id, "position") then
            local position = editor.get(id, "position")
            table.insert(temp, {
                id = id,
                position = position
            })
        end
    end
    
    table.sort(temp, function(a, b) return a.position[2] > b.position[2] end)

    local index = 0
    for _, node in pairs(temp) do
        local position = node.position
        if reset then
            position[3] = index
        else
            position[3] = position[3] + index
        end
        index = index + Z_OFFSET

        table.insert(commands, {
            action = "set",
            node_id = node.id,
            property = "position",
            value = position
        })
    end
    return commands
end

local function active(opts)
    for _, id in pairs(opts.selection) do
        if not editor.can_set(id, "position") then
            return false
        end
    end
    return #opts.selection > 1
end

function M.get_commands()
    return {
        -- Set Z coord as -Y/1000, for many and for one object
        {
            label = "Z = -Y",
            locations = {"Edit", "Outline"},
            query = {
                selection = {type = "outline",  cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return set_z_through_y(opts.selection)
            end
        },
        {
            label = "Z = -Y",
            locations = {"Edit", "Outline"},
            query = {
                selection = {type = "outline",  cardinality = "one"}
            },
            active = function(opts) 
                local id = opts.selection
                return editor.can_set(id, "position") 
            end,
            run = function(opts)
                return set_z_through_y(opts.selection)
            end
        },
        --  Sort objects by z, uses Y as comparison
        {
            label = "Z-order (sort by Y)",
            locations = {"Edit", "Outline"},
            query = {
                selection = {type = "outline",  cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return order(opts.selection, true)
            end
        },
        -- Swap Z between two selected objects
        {
            label = "Swap Z",
            locations = {"Edit", "Outline"},
            query = {
                selection = {type = "outline",  cardinality = "many"}
            },
            active = function(opts)
                for _, id in pairs(opts.selection) do
                    if not editor.can_set(id, "position") then
                        return false
                    end
                end
                return #opts.selection == 2
            end,
            run = function(opts)
                return swap(opts.selection)
            end
        },
        {
            label = "Shift DOWN",
            locations = {"Edit", "Outline"},
            query = {
                selection = {type = "outline",  cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return shift(opts.selection, -1)
            end
        },
        {
            label = "Shift UP",
            locations = {"Edit", "Outline"},
            query = {
                selection = {type = "outline",  cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return shift(opts.selection, 1)
            end
        },
        {
            label = "DOWN",
            locations = {"Edit", "Outline"},
            query = {
                selection = {type = "outline",  cardinality = "one"}
            },
            active = function(opts) 
                local id = opts.selection
                return editor.can_set(id, "position") 
            end,
            run = function(opts)
                return shift(opts.selection, -1)
            end
        },
        {
            label = "UP",
            locations = {"Edit", "Outline"},
            query = {
                selection = {type = "outline",  cardinality = "one"}
            },
            active = function(opts) 
                local id = opts.selection
                return editor.can_set(id, "position") 
            end,
            run = function(opts)
                return shift(opts.selection, 1)
            end
        },
        {
            locations = {"Outline"},
            label = "Reset Transform",
            query = {selection = {
                type = "outline", cardinality = "one"
            }},
            active = function(opts) 
                local id = opts.selection
                return editor.can_set(id, "position") 
                or editor.can_set(id, "rotation") 
                or editor.can_set(id, "scale")
            end,
            run = function(opts)
                local id = opts.selection
                local ret = {}
                if editor.can_set(id, "position") then
                    table.insert(ret, {
                        action = "set", 
                        node_id = id, 
                        property = "position", 
                        value = {0, 0, 0}
                    })
                end
                if editor.can_set(id, "rotation") then
                    table.insert(ret, {
                        action = "set", 
                        node_id = id, 
                        property = "rotation", 
                        value = {0, 0, 0}
                    })
                end
                if editor.can_set(id, "scale") then
                    table.insert(ret, {
                        action = "set", 
                        node_id = id, 
                        property = "scale", 
                        value = {1, 1, 1}
                    })
                end
                return ret
            end
        },
        -- Horizontal Flip
        {
            locations = {"Outline"},
            label = "Horizontal flip",
            query = {selection = {
                type = "outline", cardinality = "one"
            }},
            active = function(opts) 
                local id = opts.selection
                return editor.can_set(id, "rotation")
                
            end,
            run = function(opts)
                local id = opts.selection
                local ret = {}
                if editor.can_set(id, "rotation") then
                    local rotation = editor.get(id, "rotation")
                    if rotation[2] == 180 then
                        rotation[2] = 0
                    elseif rotation[2] == 0 then
                        rotation[2] = 180
                    end

                    table.insert(ret, {
                        action = "set", 
                        node_id = id, 
                        property = "rotation", 
                        value = rotation
                    })
                end
                return ret
            end
        }
    }
end

return M

## extra_locations

local inifile = require "editor-script-extra-locations.inifile"
local exists, extra_location = pcall(require,"extra-locations")

local M = {}

local macOS = "x86_64-macos"
local windows = "x86_64-win32"
local linux = "x86_64-linux"

local sys_platform = editor.platform


local paths = {
    ["Http Cache Location"] = {
        [macOS] = '~/Library/Application Support/Defold/http-cache',
        [windows] = "%appdata%/Defold/http-cache/"
    }
}

if exists then
    for key, value in pairs(extra_location) do
        paths[key] = value
    end
end


local function open()
    local bin = "./build/plugins/editor-script-extra-locations/plugins/bin/"
    local t = {
        [macOS] = bin .. "x86_64-macos/open.sh",
        [windows] = bin .. "x86_64-win32/open.bat",
        [linux] = bin .. "x86_64-linux/open.bat",
    }
    return t[sys_platform]
end

local function generate_commands()
    local commands = {}
    for name, _ in pairs(paths) do
        table.insert(commands, {
            label = "Open ".. name,
            locations = {"View"},
            run = function(opts)
                return {
                    {
                        action = "shell",
                        command = {open(), paths[name][sys_platform]}
                    }
                }
            end
        })
    end
    return commands
end

function M.get_commands()
    return generate_commands()
end

return M

## script_align

local M = {}

local min_max_map = {[-1]=math.min, [1]=math.max}


local function sum(T)
    local result = 0
    for _, value in pairs(T) do
        result = result + value
    end
    return result
end

local function scalar(v1, v2)
    return  {v1[1]*v2[1], v1[2]*v2[2], v1[3]*v2[3]}
end


local function can_get_size(node)
    if editor.can_get(node, "texture_size") then
        return true
    end
    if editor.can_get(node, "manual_size") then
        return true
    end
    return false
end

local function get_size(node)
    if editor.can_get(node, "texture_size") then
        return editor.get(node, "texture_size")
    end

    if editor.can_get(node, "manual_size") then
        return editor.get(node, "manual_size")
    end
end


local function get_pivot_modifier(node)
    local position = editor.get(node, "position")
    local size = scalar(get_size(node), editor.get(node, "scale"))

    if editor.can_get(node, "pivot") then
        local pivot = editor.get(node, "pivot")
        if pivot == "pivot-center" then
            return {0, 0, 0}
        elseif pivot == "pivot-e" then
            return {size[1] * 0.5, 0, 0}
        elseif pivot == "pivot-w" then
            return {-size[1] * 0.5, 0, 0}
        elseif pivot == "pivot-n" then
            return {0, size[2] * 0.5, 0}
        elseif pivot == "pivot-s" then
            return {0, -size[2] * 0.5, 0}
        elseif pivot == "pivot-ne" then
            return {size[1] * 0.5, size[2] * 0.5, 0}
        elseif pivot == "pivot-nw" then
            return {-size[1] * 0.5, size[2] * 0.5, 0}
        elseif pivot == "pivot-se" then
            return {size[1] * 0.5, -size[2] * 0.5, 0}
        elseif pivot == "pivot-sw" then
            return {-size[1] * 0.5, -size[2] * 0.5, 0}
            
        end
    else
        return position
    end
end


local function rotate_point(x, y, rotation)
    local angle = math.rad(rotation)
    local x_d =  x * math.cos(angle) + y * math.sin(angle)
    local y_d = -x * math.sin(angle) + y * math.cos(angle)
    return x_d, y_d
end

local function get_rotated_size(width, height, rotation)
    local max_y = height * 0.5
    local max_x = width * 0.5
    local min_y = -max_y
    local min_x = -max_x

    local x_points = {}
    local y_points = {}
    
    for _, p in pairs{{min_x,min_y}, {min_x, max_y}, {max_x, min_y}, {max_x, max_y}} do
        local x, y = rotate_point(p[1], p[2], rotation)
        table.insert(x_points, x)
        table.insert(y_points, y)
    end
    -- Return the calculated "bounding box"
    return {math.max(table.unpack(x_points)) - math.min(table.unpack(x_points)), math.max(table.unpack(y_points)) - math.min(table.unpack(y_points)), 0}
end

local function center(ids, x, y)
    local transactions = {}
    local target_x = {}
    local target_y = {}
    for _, id in pairs(ids) do
        if editor.can_get(id, "position") then
            local position = editor.get(id, "position")
            local pivot_modifier = get_pivot_modifier(id)
            table.insert(target_x, position[1] - pivot_modifier[1])
            table.insert(target_y, position[2] - pivot_modifier[2])
        end
    end
    -- Calculate the avarage new value if #target_* is more than 0
    target_x = #target_x > 0 and sum(target_x) / #target_x or target_x
    target_y = #target_y > 0 and sum(target_y) / #target_y or target_y
    
    for _, id in pairs(ids) do
        local position = editor.get(id, "position")
        local pivot_modifier = get_pivot_modifier(id)
        -- multiply the average new value with the input x to 0 out the axis we don't wnt
        position[1] = position[1] - (position[1] * x) + (target_x * x) + (pivot_modifier[1] * x)
        position[2] = position[2] - (position[2] * y) + (target_y * y) + (pivot_modifier[2] * y)
        table.insert(transactions, editor.tx.set(id, "position", {position[1], position[2], position[3]}))
    end
    editor.transact(transactions)
end

local function get_bounding_box_of_node(id)
    local size = {0, 0, 0}
    local scale = {1, 1, 1}
    if can_get_size(id) then
        size = get_size(id)
    end
    if editor.can_get(id, "scale") then
        scale = editor.get(id, "scale")
    end
    if editor.can_get(id, "rotation") then
        local rotation = editor.get(id, "rotation")
        local normalize_size = scalar(size, scale)
        return get_rotated_size(normalize_size[1], normalize_size[2], rotation[3])
    else
        return scalar(size, scale)
    end
end


local function align(ids, x, y, f)
    local transactions = {}
    local target_x
    local target_y
    
    -- First we find the target_x and y
    for _, id in pairs(ids) do
        if editor.can_get(id, "position") then
            local position = editor.get(id, "position")
            local pos_x = position[1]
            local pos_y = position[2]
            local bounding_box = get_bounding_box_of_node(id)
            local pivot_modifier = get_pivot_modifier(id)
            pos_x = pos_x + (x * f * bounding_box[1] * 0.5) + pivot_modifier[1]
            pos_y = pos_y + (y * f * bounding_box[2] * 0.5) + pivot_modifier[2]
            target_x = min_max_map[f](pos_x, target_x or pos_x)
            target_y = min_max_map[f](pos_y, target_y or pos_y)
        end
    end

    -- Now with the max/min found we can position them
    for _, id in pairs(ids) do
        local position = editor.get(id, "position")
        local bounding_box = get_bounding_box_of_node(id)
        local pivot_modifier = get_pivot_modifier(id)
        position[1] = position[1] - (position[1] * x) + (target_x * x) - (x * f * bounding_box[1] * 0.5) + (pivot_modifier[1])
        position[2] = position[2] - (position[2] * y) + (target_y * y) - (y * f * bounding_box[2] * 0.5) + (pivot_modifier[2])
        table.insert(transactions, editor.tx.set(id, "position", {position[1], position[2], position[3]}))
    end
    editor.transact(transactions)
end

local function active(opts)
    for _, id in pairs(opts.selection) do
        if not editor.can_set(id, "position") then
            return false
        end
    end
    return #opts.selection > 1
end

function M.get_commands()
    return {
        {
            label="Align Right",
            locations = {"Edit"},
            query = {
                selection = {type = "outline", cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return align(opts.selection, 1, 0, 1)
            end
        },
        {
            label="Align Left",
            locations = {"Edit"},
            query = {
                selection = {type = "outline", cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return align(opts.selection, 1, 0, -1)
            end
        },
        {
            label="Align Top",
            locations = {"Edit"},
            query = {
                selection = {type = "outline", cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return align(opts.selection, 0, 1, 1)
            end
        },
        {
            label="Align Down",
            locations = {"Edit"},
            query = {
                selection = {type = "outline", cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return align(opts.selection, 0, 1, -1)
            end
        },
        {
            label="Align Vertical Center",
            locations = {"Edit"},
            query = {
                selection = {type = "outline", cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return center(opts.selection, 1, 0)
            end
        },
        {
            label="Align Horizontal Center",
            locations = {"Edit"},
            query = {
                selection = {type = "outline", cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return center(opts.selection, 0, 1)
            end
        }
    }
end

return M

## distribute

local M = {}

local operator = {}

local function distribute(ids, x, y)
    local transactions = {}
    local max
    local min
    local list = {}
    -- Find the max/min of any axis
    for _, id in pairs(ids) do
        if editor.can_get(id, "position") then
            local position = editor.get(id, "position")
            max = math.max(position[1] * x, position[2] * y, max or -math.huge)
            min = math.min(y == 0 and position[1] * x or position[2] * y, min or math.huge)
            table.insert(list, {id=id, value=position[1]*x + position[2]*y})
        end
    end
    -- Sort the list from lowest to highest
    table.sort(list, function(a, b) return a.value < b.value end)
    local distance = (max - min) / (#list - 1)
    for index, data in pairs(list) do
        local id = data.id
        local position = editor.get(id, "position")

        position[1] = position[1] * (1 - x) + (min * x) + distance * (index-1) * x
        position[2] = position[2] * (1 - y) + (min * y) + distance * (index-1) * y

        table.insert(transactions, editor.tx.set(id, "position", {position[1], position[2], position[3]}))
    end
    editor.transact(transactions)
end

local function active(opts)
    for _, id in pairs(opts.selection) do
        if not editor.can_set(id, "position") then
            return false
        end
    end
    return #opts.selection > 1
end

function M.get_commands()
    return {
        {
            label="Distribute Vertical",
            locations = {"Edit"},
            query = {
                selection = {type = "outline", cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return distribute(opts.selection, 0, 1)
            end
        },
        {
            label="Distribute Horizontal",
            locations = {"Edit"},
            query = {
                selection = {type = "outline", cardinality = "many"}
            },
            active = active,
            run = function(opts)
                return distribute(opts.selection, 1, 0)
            end
        }
    }
end


return M

## check_library

local check_dependencies = require "editor-script-check-dependencies.scripts.check_dependencies"

local M = {}

function M.get_commands()
	return
	{
		{
			label="Check Libraries for Updates",
			locations = {"View"},
			run = function(opts)
				check_dependencies.main()
			end
		}
	}
end

return M

## create components

local file_templates = require "editor-script-components.file_templates"

local M = {}

local function ends_with(path, suffix)
    return path:find(suffix, nil, true) or path:find(suffix, nil, true)
end

local function path_segments(path)
    return string.match(path, "(.-)([^\\/]-%.?([^%.\\/]*))$")
end

local function name_ext(file_name)
    return string.match(file_name, "(.+)%..+")
end

local function create_multiple(opts)
    local paths = {}
    if opts and opts.selection then
        for _, id in pairs(opts.selection) do
            local path = editor.get(id, "path")
            local base_path, file_name, ext = path_segments(path)
            local name = name_ext(file_name)
            
            local extension = ""
            local string = ""
            if ext == "spinescene" then
                string = file_templates.spine_model(path)
                extension = ".spinemodel"
            elseif ext == "wav" or ext == "ogg" then
                string = file_templates.sound(path)
                extension = ".sound"
            end
            
            local file = io.open("." .. base_path .. name .. extension, "w")
            file:write(string)
            file:close()
        end
    end
end




local function check_file_suffix(opts, ...)
    for _, id in pairs(opts.selection) do
        local path = editor.get(id, "path")
        local ok = false
        for _, suffix in ipairs(...) do
            if ends_with(path, suffix) then
                ok = true
            end
        end
        if ok == false then
            return false
        end
    end
    return true
end

local function create_spine_scene(opts)
    local paths = {}
    local json_file
    local atlas_file
    for _, id in pairs(opts.selection) do
        local path = editor.get(id, "path")
        if ends_with(path, ".json") then
            json_file = path
        else
            atlas_file = path
        end
        table.insert(paths, path)
    end
    local base, file_name, ext =  path_segments(json_file)
    local name = name_ext(file_name)
    local string = file_templates.spine_scene(json_file, atlas_file)

    local file = io.open("." .. base .. name .. ".spinescene", "w")
    file:write(string)
    file:close()
end


local function create_model(opts)
    local paths = {}
    local material
    for _, id in pairs(opts.selection) do
        local path = editor.get(id, "path")
        if ends_with(path, ".material") then
            material = path
        end
    end
    
    for _, id in pairs(opts.selection) do
        local path = editor.get(id, "path")
        if ends_with(path, ".dae") then
            local base, file_name, ext =  path_segments(path)
            local name = name_ext(file_name)
            local string = file_templates.model(path, material)

            local file = io.open("." .. base .. name .. ".model", "w")
            file:write(string)
            file:close()
        end
    end
    
    

end

function M.get_commands()
    return {
        {
            label="Create Sound From...",
            locations = {"Assets"},
            active = function(opts)
                for _, id in pairs(opts.selection) do
                    local path = editor.get(id, "path")
                    if ends_with(path, ".wav") or ends_with(path, ".ogg") then
                    else
                        return false
                    end
                end
                return true
            end,
            query = {
                selection = {type = "resource", cardinality = "many"}
            },
            run = create_multiple
        },
        {
            label="Create Spine Scene From...",
            locations = {"Assets"},
            active = function(opts)
                for _, id in pairs(opts.selection) do
                    local path = editor.get(id, "path")
                    local is_json = false
                    local is_atlas = false
                    if ends_with(path, ".json") then 
                        if is_json then
                            return false
                        end
                        is_json = true
                    elseif ends_with(path, ".atlas") then
                        if is_atlas then 
                            return false
                        end
                        is_atlas = true
                    else
                        return false
                    end
                end
                return true
            end,
            query = {
                selection = {type = "resource", cardinality = "many"}
            },
            run = create_spine_scene
        },
        {
            label="Create Spine Model From...",
            locations = {"Assets"},
            active = function(opts)
                return check_file_suffix(opts, {".spinescene"})
            end,
            query = {
                selection = {type = "resource", cardinality = "many"}
            },
            run = create_multiple
        },
        {
            label="Create Model From...",
            locations = {"Assets"},
            active = function(opts)
                return check_file_suffix(opts, {"dae", ".material"})
            end,
            query = {
                selection = {type = "resource", cardinality = "many"}
            },
            run = create_model
        }
    }
    
end

return M

file_temaplates.lua:

local M = {}

function M.sound(path)
	return [[sound: "]].. path ..[["
looping: 0
group: "master"
gain: 1.0
pan: 0.0
speed: 1.0
]]
end

function M.spine_scene(spine_json, atlas_path)
	spine_json = spine_json or ""
	atlas_path = atlas_path or ""
	return [[spine_json: "]] .. spine_json .. [["
atlas: "]] .. atlas_path  .. [["
sample_rate: 30
]]
end

function M.spine_model(path)
	return [[spine_scene: "]] .. path .. [["
default_animation: ""
skin: ""
]]
end


function M.model(path, material)
	material = material or "/builtins/materials/model.material"
	return [[mesh: "]] .. path .. [["
material: "]] .. material .. [["
textures: ""
skeleton: ""
animations: ""
default_animation: ""
name: "unnamed"]]
end

return M

# create sound component

local M = {}
M.VERBOSE = false

local function sound_template(path)
return
[[sound: "]] .. path .. [["
looping: 0
group: "master"
gain: 1.0
pan: 0.0
speed: 1.0]]
end

local function file_exists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

local function get_filename(path)   
    local main, filename, extension = path:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
    return main, filename
end

local function is_audio(node_id)
    local path = editor.get(node_id, "path")
    return path:find(".ogg", nil, true) or path:find(".wav", nil, true)
end

local function make_audio_component(path)
    local main, filename = get_filename(path)

    local target_path = "." .. main .. filename:match("(.+)%..+") .. ".sound"
    if file_exists(target_path) then
        if M.VERBOSE then print("make_audio_component: sound already exists", target_path) end
        return false
    end
    local file = sound_template(main .. filename)
    if M.VERBOSE then print(file) end
    local sound = io.open(target_path, "w")
    sound:write(file)
    sound:close()
end

function M.get_commands()
    return {
        {
            label = "Create Sound Component",
            locations = {"Assets"},
            query = {
                selection = { type = "resource", cardinality = "one" }
            },
            active = function(opts)
                if not is_audio(opts.selection) then
                    return false
                end
                return true
            end,
            run = function(opts)
                if M.VERBOSE then print("Create Sound Component: Run") end
                local path = editor.get(opts.selection, "path")
                if M.VERBOSE then print("path: ", path) end
                make_audio_component(path)
            end,
        },
        {
            label = "Create Sound Components",
            locations = {"Assets"},
            query = {
                selection = { type = "resource", cardinality = "many" }
            },
            active = function(opts)
                local count = 0
                for _, node_id in ipairs(opts.selection) do
                    count = count + 1
                    if not is_audio(node_id) then
                        return false
                    end
                end
                if count <= 1 then return false end
                return true
            end,
            run = function(opts)
                if M.VERBOSE then print("Create Sound Components: Run") end
                for _, node_id in ipairs(opts.selection) do
                    local path = editor.get(node_id, "path")
                    if M.VERBOSE then print("path: ", path) end
                    make_audio_component(path)
                end
            end,
        }        

    }
end

return M

## play sound

local M = {}
M.VERBOSE = false

local function file_exists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

local function get_filename(path)   
    local main, filename, extension = path:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
    return main, filename
end

local function lines_from(file)
    if not file_exists(file) then return {} end
    lines = {}
    for line in io.lines(file) do 
        lines[#lines + 1] = line
    end
    return lines
end

local function is_sound_component(node_id)
    local path = editor.get(node_id, "path")
    return path:find(".sound", nil, true)
end

local function read_sound_component(path)
    local file = lines_from(path)
    local audio_path = string.match(file[1], [[sound: "([^"]+)]])
    return "." .. audio_path
end

local function is_sound_file(node_id)
    local path = editor.get(node_id, "path")
    return path:find(".wav", nil, true) or path:find(".ogg", nil, true)
end

function M.get_commands()
    return {
        {
            label = "Play Sound Component",
            locations = {"Assets", "Outline"},
            query = {
                selection = { type = "resource", cardinality = "one" }
            },
            active = function(opts)
                if not is_sound_component(opts.selection) then
                    return false
                end
                return true
            end,
            run = function(opts)
                if M.VERBOSE then print("Play Sound Component: Run") end
                local path = editor.get(opts.selection, "path")
                if M.VERBOSE then print("path: ", path) end

                local main, filename = get_filename(path)
                local target_path = "." .. main .. filename:match("(.+)%..+") .. ".sound"

                local sound_file = ""
                
                if file_exists(target_path) then
                    sound_file = read_sound_component(target_path)
                end
                
                print("If you do not have ffplay installed you must install it and add it to your path.")
                print("Attempting to play " .. sound_file .. " with ffplay... wait until a new line prints in console to know when it's done.")
                return {
                    {
                        action = "shell", 
                        command = {"ffplay", sound_file, "-loglevel", "warning", "-autoexit", "-nodisp"}
                    }
                }
            end,
        },
        {
            label = "Play Sound File",
            locations = {"Assets"},
            query = {
                selection = { type = "resource", cardinality = "one" }
            },
            active = function(opts)
                if not is_sound_file(opts.selection) then
                    return false
                end
                return true
            end,
            run = function(opts)
                if M.VERBOSE then print("Play Sound File: Run") end
                local path = "." .. editor.get(opts.selection, "path")
                if M.VERBOSE then print("path: ", path) end

                print("If you do not have ffplay installed you must install it and add it to your path.")
                print("Attempting to play " .. path .. " with ffplay... wait until a new line prints in console to know when it's done.")
                return {
                    {
                        action = "shell", 
                        command = {"ffplay", path, "-loglevel", "warning", "-autoexit", "-nodisp"}
                    }
                }
            end,             
        }

    }
end

return M

## spritesheet

local _M = {}

local function ends_with(str, ending)
	return ending == '' or str:sub(-#ending) == ending
end

function _M.get_commands()
	local commands = {}
	local spritesheet_split = {
		label = 'Spritesheet: Split',
		locations = {'Assets'},
		query = {
			selection = {type = 'resource', cardinality = 'one'}
		},
		active = function(opts)
			local path = editor.get(opts.selection, 'path')
			return ends_with(path, '.json')
		end,
		run = function(opts)
			local path = editor.get(opts.selection, 'path'):sub(2)
			local command
			if editor.platform == 'x86_64-win32' then
				command = {'cmd', '/C', 'build\\plugins\\spritesheet_script\\plugins\\bin\\win32\\spritesheet.exe', path}
			elseif editor.platform == 'x86_64-macos' then
				command = {'./build/plugins/spritesheet_script/plugins/bin/macos/spritesheet', path}
			elseif editor.platform == 'x86_64-linux' then
				command = {'./build/plugins/spritesheet_script/plugins/bin/linux/spritesheet', path}
			end
			return {
				{action = 'shell', command = command}
			}
		end
	}

	table.insert(commands, spritesheet_split)
	return commands
end

return _M

## ffmpeg_helper.lua

local M = {}

-- Adjust the paths if needed
local FFMPEG_PATH = "C:/ffmpeg/bin/ffmpeg.exe"
local FFPLAY_PATH = "C:/ffmpeg/bin/ffplay.exe"
local FFPROBE_PATH = "C:/ffmpeg/bin/ffprobe.exe"

if editor.platform == "x86_64-win32" then
	FFMPEG_PATH = "C:/ffmpeg/bin/ffmpeg.exe"
	FFPLAY_PATH = "C:/ffmpeg/bin/ffplay.exe"
	FFPROBE_PATH = "C:/ffmpeg/bin/ffprobe.exe"
elseif editor.platform == "x86_64-macos" or editor.platform == "arm64-macos" then
	FFMPEG_PATH = "/usr/local/bin/ffmpeg"
	FFPLAY_PATH = "/usr/local/bin/ffplay"
	FFPROBE_PATH = "/usr/local/bin/ffprobe"
elseif editor.platform == "x86_64-linux" then
	FFMPEG_PATH = "/usr/bin/ffmpeg"
	FFPLAY_PATH = "/usr/bin/ffplay"
	FFPROBE_PATH = "/usr/bin/ffprobe"
end

-- Checks if selected resource is a supported sound format file
function M.execute_play_sound_in_window(sound_path, window_title)
	local sound_file_path = "." .. sound_path -- Assuming project root is current directory
	-- Build the command to start ffplay in a unique window title:
	local command = 'start "'..window_title..'" "'..FFPLAY_PATH..'" "'..sound_file_path..'" -autoexit -nodisp -hide_banner'

	editor.execute('cmd.exe', '/C', command)
end

-- Escape double quotes in paths
local function escape(s)
	return s:gsub('"', '""')
end

-- Create content of a VBScript to run given sound in backgorund using FFplay
function M.create_vbscript_command_ffplay(sound_path)
	return string.format([[
	Set WshShell = CreateObject("WScript.Shell")
	WshShell.Run """%s"" ""%s"" -autoexit -nodisp -hide_banner", 0, False
	]], escape(FFPLAY_PATH), escape(sound_path))
end

function M.is_ffplay_running()
	local platform = editor.platform
	if platform == "x86_64-win32" then
		-- Windows
		local success, output = pcall(function()
			return editor.execute('tasklist', '/FI', 'IMAGENAME eq ffplay.exe', '/NH', {
				out = "capture",
				err = "stdout",
				reload_resources = false,
			})
		end)
		return success and output and output:find("ffplay.exe") ~= nil
	else
		-- Linux (MacOS?)
		local success, output = pcall(function()
			return editor.execute('pgrep', 'ffplay', {
				out = "capture",
				err = "stdout",
				reload_resources = false,
			})
		end)
		return success and output and output ~= ""
	end
end

-- Execute command to kill FFplay process
function M.execute_kill_ffplay()
	if not M.is_ffplay_running() then
		print("FFplay is not running, no need to kill it.")
		return true
	end

	local result = pcall(function()
		editor.execute('taskkill', '/F', '/IM', 'ffplay.exe')
	end)

	if not result then
		local error_message = "Unknown error occurred while killing ffplay."
		error("Failed to kill ffplay: " .. error_message)
		return false, error_message
	end

	return true
end

-- Function to get the duration of the audio file using ffprobe
function M.get_audio_duration(sound_path)
	sound_path = sound_path:sub(2)  -- Remove leading slash
	-- Use FFprobe to get the duration
	local success, result = pcall(function()
		return editor.execute(
			FFPROBE_PATH,
			"-v", "error",
			"-show_entries", "format=duration",
			"-of", "default=noprint_wrappers=1:nokey=1",
			sound_path,
			{
				reload_resources = true,
				out = "capture",
				err = "stdout"
			}
		)
	end)

	if not success then
		local error_message = result and result.err or "Unknown error occurred while executing ffprobe."
		return nil, "Failed to get audio duration: " .. tostring(error_message)
	end

	-- The duration should be in result
	if not result then
		return nil, "FFprobe did not return any duration information."
	end

	-- Trim any whitespace
	result = result:match("^%s*(.-)%s*$")

	-- Convert duration to number
	local duration = tonumber(result)
	if not duration then
		return nil, "Failed to parse audio duration: " .. tostring(result)
	end

	return duration, nil
end

-- Function to extract a subtrack using FFmpeg
function M.extract_subtrack(input_path, output_path, start_time, end_time)
	input_path = input_path:sub(2)  -- Remove leading slash
	-- Remove leading slash from input_path and output_path if present
	input_path = input_path:gsub("^/", "")
	output_path = output_path:gsub("^/", "")

	print("Executing FFmpeg command")
	print("FFMPEG_PATH:", FFMPEG_PATH)
	print("Input:", input_path)
	print("Output:", output_path)
	print("Start time:", start_time)
	print("End time:", end_time)

	-- Execute the FFmpeg command
	local success, result = pcall(function()
		return editor.execute(FFMPEG_PATH,
			"-y",
			"-i", input_path,
			"-ss", tostring(start_time),
			"-to", tostring(end_time),
			"-c", "copy",
			output_path,
			{
				reload_resources = true,
				out = "discard",
				err = "discard"
			}
		)
	end)

	print("FFmpeg execution result:", success, result)

	if success then
		if result then  -- Check if result is not nil
			return true, result
		else
			return true, "FFmpeg executed successfully, but no output was captured."
		end
	else
		local error_message = "FFmpeg execution failed.\n"
		error_message = error_message .. "Error: " .. tostring(result) .. "\n"
		return false, error_message
	end
end


-- Check if a process is running
function M.is_process_running(process_name)
	local platform = editor.platform
	if platform == "x86_64-win32" then
		-- Use tasklist and findstr to check for process on Windows
		local success, output = pcall(function()
			return editor.execute('cmd.exe', '/C', 'tasklist | findstr ' .. process_name, {
				out = "capture",
				err = "stdout",
				reload_resources = false,
			})
		end)
		return success and output and output:find(process_name) ~= nil
	else
		-- Use pgrep for Unix-based systems
		local success, output = pcall(function()
			return editor.execute('pgrep', process_name, {
				out = "capture",
				err = "stdout",
				reload_resources = false,
			})
		end)
		return success and output and output ~= ""
	end
end

-- Function to convert audio using FFmpeg
function M.convert_audio(input_path, output_path, output_format)
	--input_path = input_path:sub(2)  -- Remove leading slash
	--output_path = output_path:gsub("^/", "")
	input_path = "./" .. input_path  -- Ensure it's treated as a relative path

	-- Define FFmpeg parameters for different formats and execute command
	local success, result = pcall(function()
		if output_format == "ogg" then
			-- OGG format conversion with Defold-compatible parameters
			return editor.execute(
				FFMPEG_PATH,
				"-y",
				"-loglevel", "error",
				"-i", input_path,
				"-ar", "44100",  -- Set sample rate to 44100 Hz
				"-ac", "2",      -- Set number of audio channels to 2
				"-b:a", "192k",  -- Set audio bitrate
				output_path,
				{
					reload_resources = true,
					out = "capture",
					err = "stdout"
				}
			)
		elseif output_format == "wav" then
			-- WAV format conversion with Defold-compatible parameters
			return editor.execute(
			FFMPEG_PATH,
				"-y",
				"-loglevel", "error",
				"-i", input_path,
				"-ar", "44100",  -- Set sample rate to 44100 Hz
				"-ac", "2",      -- Set number of audio channels to 2
				output_path,
				{
					reload_resources = true,
					out = "capture",
					err = "stdout"
				}
			)
		else
			-- Unsupported format
			return false, "Unsupported output format: " .. output_format
		end
	end)

	return success, result or "FFmpeg execution failed."
end

return M

## file_helper.lua

local M = {}

-- Checks if given file is a supported sound format file
function M.is_sound_file(path)
	return path:lower():match("%.wav$")
	or path:lower():match("%.ogg$")
	or path:lower():match("%.flac$")
	or path:lower():match("%.mp3$")
	or path:lower():match("%.aac")
end

-- Returns the file name without extension
function M.get_file_name_without_extension(path)
	return path:match("([^/\\]+)%.%w+$")
end

-- Returns the file extension
function M.get_file_extension(path)
	return path:match("%.([%w]+)$")
end

-- Returns the directory of a file path
function M.get_directory(path)
	return path:match("(.*/)")
end

-- Checks if given file exists
function M.exists(path)
	local success, output_attrs = pcall(editor.resource_attributes, path)
	if not success or not output_attrs then
		success, output_attrs = pcall(editor.external_file_attributes, path)
	end

	if success and output_attrs then
		return output_attrs.exists
	else
		print("Failed to retrieve attributes for path:", path)
		return false
	end
end


function M.file_exists(path)
	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	else
		return false
	end
end

-- Creates directory at given path if not existing
function M.create_directory(path)
	-- First try to use Defold's editor API for resource paths
	if not (editor.resource_attributes(path) and editor.resource_attributes(path).exists) then
		local success = pcall(editor.create_directory, path)
		if not success then
			-- Fallback to using os.execute if the path isn't a recognized resource path
			local fallback_success, err = os.execute('mkdir "' .. path .. '"')
			if fallback_success then
				print("Directory created using os.execute:", path)
			else
				print("Failed to create directory with os.execute:", path, "Error:", err)
			end
		else
			print("Directory created using editor API:", path)
		end
	end
end

-- Creates a directory at a given path if not existing
function M.create_directory_2(path)
	-- Check if the path exists using Lua's `io` functions
	if not M.file_exists(path) then
		-- Attempt to create the directory using Lua's `os.execute`
		local success, err = os.execute('mkdir "' .. path .. '"')
		if success then
			print("Directory created using os.execute:", path)
		else
			print("Failed to create directory with os.execute:", path, "Error:", err)
		end
	else
		print("Directory already exists:", path)
	end
end

-- Escape double quotes in paths
function M.escape(input_path)
	return input_path:gsub('"', '""')
end

-- Escape leading slash in paths
function M.escape_leading_slash(input_path)
	return ( (input_path:sub(1, 1) == "/") and input_path:sub(2) or input_path )
end

-- Creates a VBscript file in given directory with given command content
function M.create_vbscript(command, temp_dir)
	-- Create a unique temporary filename in temporary directory
	local temp_vbs_filename = 'temp_ffplay_'..tostring(os.time())..'.vbs'
	local vbs_script_full_path = "."..temp_dir..'/'..temp_vbs_filename

	-- Write the VBScript file
	local vbs_file, err = io.open(vbs_script_full_path, "w")
	if not vbs_file then
		error("Failed to create VBScript file: " .. tostring(err))
	end
	vbs_file:write(command)
	vbs_file:close()

	return vbs_script_full_path
end

-- Removes file or directory using standard Lua functions
function M.remove(path)
	local error = os.remove(path)
	if not error then
		print("Removed file/directory:", path)
		return true
	else
		print("Error removing file/directory:", path, "Error:", error)
		return false
	end
end

function M.remove_directory_recursive(path)
	if not M.exists(path) then
		return true
	end

	local success, files = pcall(editor.list_files, path)
	if not success then
		print("Error listing files in directory:", path)
		return false
	end

	for _, file in ipairs(files) do
		local file_path = path .. "/" .. file
		local attr = editor.resource_attributes(file_path)

		if attr.type == "directory" then
			if not M.remove_directory_recursive(file_path) then
				return false
			end
		else
			local remove_success = pcall(editor.delete_resource, file_path)
			if not remove_success then
				print("Error removing file:", file_path)
				return false
			end
		end
	end

	-- Remove empty catalog
	local remove_dir_success = pcall(editor.delete_resource, path)
	if not remove_dir_success then
		print("Error removing directory:", path)
		return false
	end

	return true
end

return M

## ui_helper.lua:

local M = {}

-- Creates a window popup with just a title and a single button to exit.
function M.show_dialog_single_button(title_text, button_text, callback)
	-- Create dialog popup:
	local dialog = editor.ui.dialog({
		title = title_text,
		buttons = {
			editor.ui.dialog_button({
				text = button_text or "OK",
				default = true,
				result = true
			})
		}
	})

	-- Show popup and handle result
	local result = editor.ui.show_dialog(dialog)
	if result and callback then
		callback()
	end
end

-- Creates a window popup with just a title and a single button to exit.
function M.show_dialog_single_text_and_button(title_text, content_text, button_text)
	-- Create dialog popup:
	local dialog = editor.ui.dialog({
		title = title_text,
		content = editor.ui.vertical({
			padding = editor.ui.PADDING.LARGE,
			children = {
				editor.ui.paragraph({
					text = content_text,
					read_only = true,
					alignment = editor.ui.TEXT_ALIGNMENT.LEFT,
					width = 600,
					height = 300,
					word_wrap = true,
				}),
			},
		}),
		buttons = {
			editor.ui.dialog_button({
				text = button_text,
				default = true,
				result = true
			})
		}
	})

	-- Show popup and return user input
	return editor.ui.show_dialog(dialog)
end

-- Creates a window popup with just a title, a text in content and a single button to exit.
function M.show_error(error_text)
	-- Create dialog popup:
	local dialog = editor.ui.dialog({
		title = "Error",
		content = editor.ui.label({
			text = error_text,
			alignment = editor.ui.ALIGNMENT.LEFT,
			word_wrap = true,
		}),
		buttons = {
			editor.ui.dialog_button({
				text = "Exit",
				default = true,
				result = true,
			}),
		}
	})

	-- Show popup and return user input
	return editor.ui.show_dialog(dialog)
end

-- Creates a window popup with just a title and a single button to exit.
function M.show_dialog_with_confirm_and_cancel(title_text, confirm_button_text)
	-- Create dialog popup:
	local dialog = editor.ui.dialog({
		title = title_text,
		buttons = {
			editor.ui.dialog_button({
				text = "Cancel",
				default = false,
				result = false,
				cancel = true,
			}),
			editor.ui.dialog_button({
				text = confirm_button_text,
				default = true,
				result = true
			})
		}
	})

	-- Show popup and return user input
	return editor.ui.show_dialog(dialog)
end

return M


## gui add script

local M = {}

-- Define the content for the GUI script
local GUI_SCRIPT_CONTENT = [[
function init(self)
    msg.post(".", "acquire_input_focus")
end

function final(self)
    msg.post(".", "release_input_focus")
end

function update(self, dt)
end

function on_message(self, message_id, message, sender)
end

function on_input(self, action_id, action)
end

function on_reload(self)
end
]]

local function create_gui_script(gui_path)
    -- Extract the base directory and the name of the .gui file
    local base_dir, gui_name = gui_path:match("(.-)([^\\/]+)%.gui$")
    local gui_script_path = base_dir .. gui_name .. ".gui_script"

    -- Write the content to the .gui_script file
    local file = io.open("." .. gui_script_path, "w")
    if not file then
        print("Error: Unable to create GUI script file at: " .. gui_script_path)
        return
    end
    file:write(GUI_SCRIPT_CONTENT)
    file:close()

    print("GUI script created at: " .. gui_script_path)

    -- Attach the GUI script to the selected GUI component
    local gui_file = io.open("." .. gui_path, "rb")
    if not gui_file then return end
    local gui_text = gui_file:read("*a")
    gui_file:close()

    -- Replace or add the script reference in the .gui file
    if gui_text:match('script: ".*"') then
        -- Replace existing script line
        gui_text = gui_text:gsub('script: ".*"', 'script: "' .. gui_script_path .. '"')
    else
        -- Add script property if it doesn't exist
        gui_text = gui_text .. '\nscript: "' .. gui_script_path .. '"\n'
    end

    gui_file = io.open("." .. gui_path, "w")
    gui_file:write(gui_text)
    gui_file:close()

    print("Attached GUI script to: " .. gui_path)
end

local function create_gui_script_for_selected_gui(selection)
    -- Get the path of the selected .gui file
    local gui_path = editor.get(selection, "path")

    -- Ensure the path is valid
    if not gui_path or not gui_path:match("%.gui$") then
        print("Error: Invalid GUI file selected.")
        return
    end

    -- Create the GUI script and attach it
    create_gui_script(gui_path)
end

function M.get_commands()
    return {
        {
            label = "Add GUI Script",
            locations = { "Assets" },
            query = {
                selection = { type = "resource", cardinality = "one" }
            },
            active = function(opts)
                local path = editor.get(opts.selection, "path")
                return path:match("%.gui$")
            end,
            run = function(opts)
                create_gui_script_for_selected_gui(opts.selection)
            end
        }
    }
end

return M

## gui add to collection

local M = {}

-- Define the content for the GUI script
local GUI_SCRIPT_CONTENT = [[
function init(self)
    msg.post(".", "acquire_input_focus")
end

function final(self)
    msg.post(".", "release_input_focus")
end

function update(self, dt)
end

function on_message(self, message_id, message, sender)
end

function on_input(self, action_id, action)
end

function on_reload(self)
end
]]

-- Helper functions to handle string manipulation
local function path_segments(path)
    return string.match(path, "(.-)([^\\/]-%.?([^%.\\/]*))$")
end

local function ends_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

local function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

-- Create GUI and GUI script files
local function create_gui_and_script_files(gui_path, gui_script_path)
    -- Create the GUI component file
    if not file_exists("." .. gui_path) then
        local gui_content = [[
        script: "]] .. gui_script_path .. [["
        fonts {
            name: "default"
            font: "/builtins/fonts/default.font"
        }
        material: "/builtins/materials/gui.material"
        adjust_reference: ADJUST_REFERENCE_PARENT
        ]]
        local gui_file = io.open("." .. gui_path, "w")
        gui_file:write(gui_content)
        gui_file:close()
    end

    -- Create the GUI script file
    if not file_exists("." .. gui_script_path) then
        local gui_script_file = io.open("." .. gui_script_path, "w")
        gui_script_file:write(GUI_SCRIPT_CONTENT)
        gui_script_file:close()
    end
end

-- Function to insert a game object with the created GUI component into the collection
local function insert_game_object_in_collection(collection_path, gui_path, go_name)
    -- Read the current collection file
    local collection_file = io.open("." .. collection_path, "r")
    if not collection_file then
        print("Failed to open collection file: " .. collection_path)
        return
    end

    local collection_text = collection_file:read("*a")
    collection_file:close()

    -- Add a new game object with the GUI component
    local new_game_object = [[
    embedded_instances {
        id: "]] .. go_name .. [["
        data: "components {\n"
        "  id: \"gui\"\n"
        "  component: \"]] .. gui_path .. [[\"\n"
        "  position {\n"
        "    x: 0.0\n"
        "    y: 0.0\n"
        "    z: 0.0\n"
        "  }\n"
        "  rotation {\n"
        "    x: 0.0\n"
        "    y: 0.0\n"
        "    z: 0.0\n"
        "    w: 1.0\n"
        "  }\n"
        "  scale {\n"
        "    x: 1.0\n"
        "    y: 1.0\n"
        "    z: 1.0\n"
        "  }\n"
        "}\n"
    }
    ]]
    -- Append the new game object to the collection
    collection_text = collection_text .. new_game_object

    -- Write the updated collection back to the file
    local updated_collection_file = io.open("." .. collection_path, "w")
    updated_collection_file:write(collection_text)
    updated_collection_file:close()

    print("Game object with GUI added to collection.")
end

-- UI dialog component to get the name of the new GUI
local dialog = editor.ui.component(function(props)
    local name, set_name = editor.ui.use_state("")

    return editor.ui.dialog({
        title = props.title or "Enter GUI Name",
        content = editor.ui.vertical({
            padding = editor.ui.PADDING.LARGE,
            children = {
                editor.ui.string_field({
                    value = name,
                    on_value_changed = set_name,
                    label = "GUI Name"
                })
            }
        }),
        buttons = {
            editor.ui.dialog_button({
                text = "Cancel",
                cancel = true
            }),
            editor.ui.dialog_button({
                text = "Create",
                enabled = name ~= "",
                default = true,
                result = name
            }),
        }
    })
end)

-- Handler function to show the dialog and create the GUI files
local function handle_create_gui_with_script(collection_path)
    -- Show the UI dialog to get the name of the GUI
    local gui_name = editor.ui.show_dialog(dialog({ title = "New GUI Name" }))

    if gui_name then
        -- Extract the base directory of the collection
        local base_path, _ = path_segments(collection_path)

        -- Generate new GUI and GUI script paths
        local gui_path = base_path .. gui_name .. ".gui"
        local gui_script_path = base_path .. gui_name .. ".gui_script"

        -- Create the GUI and GUI script files
        create_gui_and_script_files(gui_path, gui_script_path)

        -- Insert a new game object in the collection with the GUI component
        insert_game_object_in_collection(collection_path, gui_path, gui_name)
    else
        print("GUI creation canceled.")
    end
end

-- Command to create GUI with script and insert it into the collection
function M.get_commands()
    return {
        {
            label = "Add GUI to collection",
            locations = {"Outline"},
            query = {
                selection = {type = "resource", cardinality = "one"}
            },
            active = function(opts)
                -- Only active if a .collection file is selected
                local path = editor.get(opts.selection, "path")
                return ends_with(path, ".collection")
            end,
            run = function(opts)
                -- Ensure the selection exists
                if not opts.selection then
                    print("No valid selection found.")
                    return
                end

                -- Get the path of the collection
                local collection_path = editor.get(opts.selection, "path")
                if not collection_path then
                    print("Failed to retrieve collection path.")
                    return
                end

                -- Handle the GUI creation and insertion into the collection
                handle_create_gui_with_script(collection_path)
            end
        }
    }
end

return M

## sound component

local M = {}

-- Helper function to check if a file is a .wav or .ogg file
local function is_audio_file(path)
    return path:match("%.wav$") or path:match("%.ogg$")
end

-- Helper function to get the file name without extension
local function get_file_name_without_extension(path)
    return path:match("([^/\\]+)%.%w+$")
end

-- Helper function to get the directory of a file path
local function get_directory(path)
    return path:match("(.*/)")
end

-- Function to create the .sound file with the specified properties
local function create_sound_file(sound_file_path, properties)
    -- Construct the .sound file content
    local content = string.format([[
    sound: "%s"
    looping: %d
    group: "%s"
    gain: %f
    pan: %f
    speed: %f
    loopcount: %d
    ]], properties.sound, properties.looping and 1 or 0, properties.group, properties.gain, properties.pan, properties.speed, properties.loopcount)

    -- Determine the .sound file path
    local directory = get_directory(sound_file_path)
    local sound_file_name = properties.name .. ".sound"
    local sound_file_full_path = "." .. directory .. sound_file_name

    -- Write the .sound file
    local file, err = io.open(sound_file_full_path, "w")
    if not file then
        error("Failed to create sound file: " .. tostring(err))
    end
    file:write(content)
    file:close()
end

-- Define the UI dialog component
local sound_dialog = editor.ui.component(function(props)
    -- Initialize state variables
    local name, set_name = editor.ui.use_state(props.default_name or "")
    local looping, set_looping = editor.ui.use_state(props.default_looping or false)
    local loopcount, set_loopcount = editor.ui.use_state(props.default_loopcount or 0)
    local group, set_group = editor.ui.use_state(props.default_group or "master")
    local gain, set_gain = editor.ui.use_state(props.default_gain or 1.0)
    local pan, set_pan = editor.ui.use_state(props.default_pan or 0.0)
    local speed, set_speed = editor.ui.use_state(props.default_speed or 1.0)

    -- Validate input values
    local gain_issue = nil
    if gain < 0.0 or gain > 1.0 then
        gain_issue = { severity = editor.ui.ISSUE_SEVERITY.ERROR, message = "Gain must be between 0.0 and 1.0" }
    end

    local pan_issue = nil
    if pan < -1.0 or pan > 1.0 then
        pan_issue = { severity = editor.ui.ISSUE_SEVERITY.ERROR, message = "Pan must be between -1.0 and 1.0" }
    end

    local speed_issue = nil
    if speed <= 0.0 then
        speed_issue = { severity = editor.ui.ISSUE_SEVERITY.ERROR, message = "Speed must be greater than 0.0" }
    end

    -- Determine if the "Create" button should be enabled
    local can_create = name ~= "" and not gain_issue and not pan_issue and not speed_issue

    return editor.ui.dialog({
        title = "Create Sound Component",
        content = editor.ui.grid({
            columns = {{}, {grow = true}},
            padding = editor.ui.PADDING.LARGE,
            spacing = editor.ui.SPACING.MEDIUM,
            children = {
                -- Name field
                {
                    editor.ui.label({
                        text = "Sound Name",
                        alignment = editor.ui.ALIGNMENT.RIGHT,
                    }),
                    editor.ui.string_field({
                        value = name,
                        on_value_changed = set_name,
                    }),
                },
                -- Looping checkbox
                {
                    editor.ui.label({
                        text = "Looping",
                        alignment = editor.ui.ALIGNMENT.RIGHT,
                    }),
                    editor.ui.check_box({
                        value = looping,
                        on_value_changed = set_looping,
                    }),
                },
                -- Loopcount field
                {
                    editor.ui.label({
                        text = "Loop Count",
                        alignment = editor.ui.ALIGNMENT.RIGHT,
                    }),
                    editor.ui.integer_field({
                        value = loopcount,
                        on_value_changed = set_loopcount,
                    }),
                },
                -- Group field
                {
                    editor.ui.label({
                        text = "Group",
                        alignment = editor.ui.ALIGNMENT.RIGHT,
                    }),
                    editor.ui.string_field({
                        value = group,
                        on_value_changed = set_group,
                    }),
                },
                -- Gain field
                {
                    editor.ui.label({
                        text = "Gain (0.0 - 1.0)",
                        alignment = editor.ui.ALIGNMENT.RIGHT,
                    }),
                    editor.ui.number_field({
                        value = gain,
                        on_value_changed = set_gain,
                        issue = gain_issue,
                    }),
                },
                -- Pan field
                {
                    editor.ui.label({
                        text = "Pan (-1.0 - 1.0)",
                        alignment = editor.ui.ALIGNMENT.RIGHT,
                    }),
                    editor.ui.number_field({
                        value = pan,
                        on_value_changed = set_pan,
                        issue = pan_issue,
                    }),
                },
                -- Speed field
                {
                    editor.ui.label({
                        text = "Speed (> 0.0)",
                        alignment = editor.ui.ALIGNMENT.RIGHT,
                    }),
                    editor.ui.number_field({
                        value = speed,
                        on_value_changed = set_speed,
                        issue = speed_issue,
                    }),
                },
            }
        }),
        buttons = {
            editor.ui.dialog_button({
                text = "Cancel",
                cancel = true,
            }),
            editor.ui.dialog_button({
                text = "Create",
                default = true,
                enabled = can_create,
                result = {
                    name = name,
                    looping = looping,
                    loopcount = loopcount,
                    group = group,
                    gain = gain,
                    pan = pan,
                    speed = speed,
                },
            }),
        }
    })
end)

function M.get_commands()
    return {
        {
            label = "Create Sound Component",
            locations = { "Assets" },
            query = { selection = { type = "resource", cardinality = "one" } },
            active = function(opts)
                local path = editor.get(opts.selection, "path")
                return is_audio_file(path)
            end,
            run = function(opts)
                local path = editor.get(opts.selection, "path")
                local file_name_without_ext = get_file_name_without_extension(path)

                -- Show the dialog
                local result = editor.ui.show_dialog(sound_dialog({
                    default_name = file_name_without_ext,
                }))

                if result then
                    -- Set the properties
                    local properties = result
                    properties.sound = path  -- Resource path to the sound file

                    -- Create the .sound file
                    local ok, err = pcall(function()
                        create_sound_file(path, properties)
                    end)
                    if not ok then
                        editor.ui.show_dialog(editor.ui.dialog({
                            title = "Error",
                            content = editor.ui.label({
                                text = "Failed to create sound component:\n" .. tostring(err),
                                alignment = editor.ui.TEXT_ALIGNMENT.LEFT,
                            }),
                            buttons = {
                                editor.ui.dialog_button({
                                    text = "OK",
                                    default = true,
                                }),
                            }
                        }))
                    else
                        editor.ui.show_dialog(editor.ui.dialog({
                            title = "Success",
                            content = editor.ui.scroll({
                                content = editor.ui.vertical({
                                    padding = editor.ui.PADDING.LARGE,
                                    children = {
                                        editor.ui.paragraph({
                                            text = "Sound component created successfully.",
                                            alignment = editor.ui.TEXT_ALIGNMENT.LEFT,
                                            word_wrap = true
                                        })
                                    }
                                })
                            }),
                            buttons = {
                                editor.ui.dialog_button({
                                    text = "OK",
                                    default = true
                                })
                            }
                        }))

                        -- Optionally, save any unsaved changes
                        editor.save()
                    end
                else
                    -- User cancelled the dialog
                end
            end
        }
    }
end

return M

## sound converter

local ffmpeg_helper = require "editor-scripts.ffmpeg_helper"
local file_helper = require "editor-scripts.file_helper"
local ui_helper = require "editor-scripts.ui_helper"

local M = {}

-- Function to convert audio to Defold-compatible formats using FFmpeg
local function convert_audio(input_path, output_format)
    input_path = file_helper.escape_leading_slash(input_path)

    -- Define the output file path by replacing the extension with the selected format
    local output_path = input_path:gsub("%.%w+$", "." .. output_format)

    -- Execute the FFmpeg command using the helper with the chosen format
    return ffmpeg_helper.convert_audio(input_path, output_path, output_format)
end

-- Active function for 'Convert Sound' command
local active_function = function(opts)
    for _, id in ipairs(opts.selection) do
        local path = editor.get(id, "path")
        if not file_helper.is_sound_file(path) then
            return false
        end
    end
    return true
end

-- Reactive component for format selection dialog
local function converter_popup(selected_format)
    return editor.ui.dialog({
        title = "Select Output Format",
        content = editor.ui.vertical({
            padding = editor.ui.PADDING.LARGE,
            spacing = editor.ui.SPACING.MEDIUM,
            children = {
                editor.ui.label({
                    text = "Choose the output format:",
                    alignment = editor.ui.ALIGNMENT.LEFT
                }),
                editor.ui.select_box({
                    value = selected_format.value,
                    on_value_changed = function(new_value)
                        selected_format.value = new_value
                    end,
                    options = {"ogg", "wav"},
                    to_string = function(item) return item:upper() end,
                    alignment = editor.ui.ALIGNMENT.LEFT
                })
            }
        }),
        buttons = {
            editor.ui.dialog_button({
                text = "Cancel",
                cancel = true
            }),
            editor.ui.dialog_button({
                text = "Convert",
                enabled = selected_format.value ~= "",
                default = true,
                result = selected_format.value
            }),
        }
    })
end

-- Run function for 'Convert Sound' command
local run_convert_function = function(opts)
    local selected_format = { value = "ogg" }

    -- Show format selection dialog and store the user's choice
    local output_format = editor.ui.show_dialog(converter_popup(selected_format))

    -- Check if the user canceled the dialog
    if not output_format then
        return
    end

    local files_converted = {}
    local files_skipped = {}
    local error_messages = {}

    for _, id in ipairs(opts.selection) do
        -- Get the selected file path
        local resource_path = editor.get(id, "path")
        local input_path = file_helper.escape_leading_slash(resource_path) -- Remove leading "/"

        -- Define the output path
        local output_path = input_path:gsub("%.%w+$", "." .. selected_format.value)

        -- Check if the output file already exists
        local should_convert = true
        if file_helper.exists(output_path) then
            local title_text = "File already exists. Overwrite?"
            local confirm_button_text = "Overwrite"
            local is_overwrite_accepted = ui_helper.show_dialog_with_confirm_and_cancel(title_text, confirm_button_text)
            if not is_overwrite_accepted then
                print("Conversion canceled by user for: " .. output_path)
                table.insert(files_skipped, resource_path)
                should_convert = false
            end
        end

        if should_convert then
            -- Get the file extension
            local ext = file_helper.get_file_extension(input_path)
            if not ext then
                table.insert(error_messages, resource_path .. ": Could not determine file extension")
            else
                ext = ext:lower():sub(2) -- Remove dot and make lowercase

                if ext == output_format then
                    -- File is already in desired format; skip conversion
                    table.insert(files_skipped, resource_path)
                else
                    -- Call the conversion function
                    local success, error_message = convert_audio(input_path, selected_format.value)

                    if success then
                        table.insert(files_converted, resource_path)
                    else
                        table.insert(error_messages, resource_path .. ": " .. error_message)
                    end
                end
            end
        end
    end

    -- Provide feedback to the user
    local message_parts = {}

    if #files_converted > 0 then
        table.insert(message_parts, string.format("Files converted to %s format: \n\n%s", selected_format.value:upper(), table.concat(files_converted, "\n")))
    end

    if #files_skipped > 0 then
        table.insert(message_parts, "Skipped files already in desired format or not overwritten: \n" .. table.concat(files_skipped, "\n"))
    end

    if #error_messages > 0 then
        table.insert(message_parts, "Errors occurred during conversion: \n" .. table.concat(error_messages, "\n"))
    end

    local message = table.concat(message_parts, "\n\n")
    ui_helper.show_dialog_single_text_and_button("Conversion Results", message or "", "OK")

    -- Optionally, save any unsaved changes
    editor.save()
end

function M.get_commands()
    return {
        {
            label = "Convert",
            locations = { "Assets" },
            query = {
                selection = { type = "resource", cardinality = "many" }
            },
            active = active_function,
            run = run_convert_function
        }
    }
end

return M

## sound cut

local ffmpeg_helper = require "editor-scripts.ffmpeg_helper"
local file_helper = require "editor-scripts.file_helper"
local ui_helper = require "editor-scripts.ui_helper"

local M = {}

local active_function = function(opts)
    -- Only active if the selected resource is a supported sound file
    local sound_path = editor.get(opts.selection, "path")
    return file_helper.is_sound_file(sound_path)
end

-- Define the main UI dialog (Cut Editor)
local cut_subtrack_editor = editor.ui.component(function(props)
    -- Initialize state variables
    local start_time, set_start_time = editor.ui.use_state(0)
    local end_time, set_end_time = editor.ui.use_state(props.duration or 0)
    local name, set_name = editor.ui.use_state(props.default_name or "")
    local is_prehearing, set_is_prehearing = editor.ui.use_state(false)

    -- Paths without leading slashes for consistency
    local prehear_filepath = "editor-scripts/tmp_cut/prehear.wav"
    local vbs_script_path = "editor-scripts/tmp_cut/play_sound.vbs"
    local temp_prehear_directory = "/editor-scripts/tmp_cut"
    local duration = props.duration or 0

    -- Validate input values
    local issues = {}
    if start_time < 0 or start_time >= duration then
        issues.start_time = {
            severity = editor.ui.ISSUE_SEVERITY.ERROR,
            message = string.format("Start time must be between 0 and %.2f seconds", duration)
        }
    end

    if end_time <= start_time or end_time > duration then
        issues.end_time = {
            severity = editor.ui.ISSUE_SEVERITY.ERROR,
            message = string.format("End time must be between start time and %.2f seconds", duration)
        }
    end

    local can_extract = not issues.start_time and not issues.end_time and name ~= ""

    -- Function to clean up temporary prehearing files and directories
    local function cleanup_prehearing_resources()
        if file_helper.file_exists(prehear_filepath) then
            local removed = file_helper.remove("./"..prehear_filepath)
            if not removed then
                print("Failed to remove prehear file:", prehear_filepath)
            end
        end

        if file_helper.file_exists(vbs_script_path) then
            local removed = file_helper.remove(vbs_script_path)
            if not removed then
                print("Failed to remove VBScript file:", vbs_script_path)
            end
        end

        local remo_dir = temp_prehear_directory:gsub('/', '')
        local removed = file_helper.remove("."..temp_prehear_directory)
        if not removed then
            print("Failed to remove temp directory:", "."..temp_prehear_directory)
        else
            print("Temporary directory removed:", "."..temp_prehear_directory)
        end
    end

    -- Function to stop prehearing and clean up resources
    local function stop_prehearing()
        if ffmpeg_helper.is_process_running("ffplay.exe") then
            local stop_success, stop_error = pcall(ffmpeg_helper.execute_kill_ffplay)
            if not stop_success then
                print("Warning: " .. tostring(stop_error))
            else
                print("ffplay process stopped successfully.")
            end
        else
            print("ffplay is not running; no need to kill the process.")
        end

        cleanup_prehearing_resources()
        set_is_prehearing(false)
    end

    -- Function to handle prehearing
    local function handle_prehear()
        if is_prehearing then
            print("Attempting to stop prehearing...")
            stop_prehearing()
            return
        end

        print("Starting prehearing...")
        file_helper.create_directory(temp_prehear_directory)

        -- Extract the subtrack to the temporary file
        local success, error_message = ffmpeg_helper.extract_subtrack(props.sound_path, prehear_filepath, start_time, end_time)
        if not success then
            ui_helper.show_error("Failed to extract subtrack for prehearing:\n" .. error_message)
            cleanup_prehearing_resources()
            return
        end

        -- Create VBScript content and run it
        local vbscript_command_run_ffplay = ffmpeg_helper.create_vbscript_command_ffplay(prehear_filepath)
        vbs_script_path = file_helper.create_vbscript(vbscript_command_run_ffplay, temp_prehear_directory)

        local play_success, result = pcall(function()
            return editor.execute('wscript.exe', vbs_script_path)
        end)

        set_is_prehearing(play_success)

        if not play_success then
            local error_text = "Failed to execute VBScript:\n" .. tostring(result)
            ui_helper.show_error(error_text)
            cleanup_prehearing_resources()
        else
            print("Playing sound: " .. prehear_filepath)
            local title_text = "Playing Sound: " .. prehear_filepath
            local button_text = "Stop"
            ui_helper.show_dialog_single_button(title_text, button_text, function()
                stop_prehearing()
                print("Stopped prehearing after dialog close.")
            end)
        end
    end
    
    

    return editor.ui.dialog({
        title = "Extract Subtrack",
        content = editor.ui.grid({
            columns = {{}, {grow = true}},
            padding = editor.ui.PADDING.LARGE,
            spacing = editor.ui.SPACING.MEDIUM,
            children = {
                -- Track Name Display
                {
                    editor.ui.label({
                        text = "Source Track Name:",
                        alignment = editor.ui.ALIGNMENT.LEFT,
                    }),
                    editor.ui.label({
                        text = props.track_name,
                        alignment = editor.ui.ALIGNMENT.LEFT,
                    }),
                },
                -- Track Duration Display
                {
                    editor.ui.label({
                        text = "Source Track Duration: ",
                        alignment = editor.ui.ALIGNMENT.LEFT,
                    }),
                    editor.ui.label({
                        text = string.format("%.2f s", duration),
                        alignment = editor.ui.ALIGNMENT.LEFT,
                    }),
                },
                -- Separator
                {
                    editor.ui.separator({ grow = true, column_span = 2 }),
                },
                -- Subtrack Name
                {
                    editor.ui.label({
                        text = "Subtrack Name:",
                        alignment = editor.ui.ALIGNMENT.LEFT,
                    }),
                    editor.ui.string_field({
                        value = name,
                        on_value_changed = set_name,
                    }),
                },
                -- Start Time
                {
                    editor.ui.label({
                        text = "Start Time (s):",
                        alignment = editor.ui.ALIGNMENT.LEFT,
                    }),
                    editor.ui.number_field({
                        value = start_time,
                        on_value_changed = set_start_time,
                        issue = issues.start_time,
                    }),
                },
                -- End Time
                {
                    editor.ui.label({
                        text = "End Time (s):",
                        alignment = editor.ui.ALIGNMENT.LEFT,
                    }),
                    editor.ui.number_field({
                        value = end_time,
                        on_value_changed = set_end_time,
                        issue = issues.end_time,
                    }),
                },
                -- Prehear Button
                {
                    editor.ui.label({ text = "" }), -- Empty label for alignment
                    editor.ui.button({
                        text = is_prehearing and "Stop Subtrack" or "Play Subtrack", -- Change button text based on state
                        enabled = can_extract,
                        on_pressed = handle_prehear,
                    }),
                },
            }
        }),
        buttons = {
            editor.ui.dialog_button({
                text = "Cancel",
                cancel = true,
            }),
            editor.ui.dialog_button({
                text = "Extract",
                default = true,
                enabled = can_extract,
                result = {
                    name = name,
                    start_time = start_time,
                    end_time = end_time,
                },
            }),
        }
    })
end)

local run_cut_editor_function = function(opts)
    local sound_path = editor.get(opts.selection, "path")
    local sound_filename = file_helper.get_file_name_without_extension(sound_path)
    local sound_extension = file_helper.get_file_extension(sound_path)
    local sound_directory = file_helper.get_directory(sound_path)

    -- Get audio duration
    local duration, err = ffmpeg_helper.get_audio_duration(sound_path)
    if not duration then
        ui_helper.show_error("Failed to get audio duration: " .. err)
        return
    end

    -- Show the main dialog - Cut Editor
    local user_parameters = editor.ui.show_dialog(cut_subtrack_editor({
        track_name = sound_filename,
        track_extension = sound_extension,
        duration = duration,
        default_name = sound_filename .. "_subtrack",
        sound_path = sound_path, -- Pass the sound_path to the editor component
    }))

    -- Cut and save subtrack with given user parameters
    if user_parameters then
        local subtrack_name = user_parameters.name
        local start_time = user_parameters.start_time
        local end_time = user_parameters.end_time

        -- Determine the output file path
        local output_resource_path = sound_directory .. subtrack_name .. "." .. sound_extension
        local output_path = output_resource_path:sub(2)  -- Remove the leading dot

        -- Ask if user accepts overwriting if file already exists
        if file_helper.exists(output_path) then
            local title_text = "File already exists. Overwrite?"
            local confirm_button_text = "Overwrite"
            local is_overwrite_accepted = ui_helper.show_dialog_with_confirm_and_cancel(title_text, confirm_button_text)
            if not is_overwrite_accepted then
                print("Subtrack extraction canceled by user.")
                return
            end
        end

        -- Extract the subtrack
        local success, error_message = ffmpeg_helper.extract_subtrack(sound_path, output_path, start_time, end_time)
        if success then
            local title_text = "Subtrack extracted successfully to: " .. output_path
            local button_text = "OK"
            ui_helper.show_dialog_single_button(title_text, button_text)
        else
            ui_helper.show_error("Failed to extract subtrack:" .. error_message)
        end
    else
        print("Subtrack extraction canceled by user.")
    end
end

function M.get_commands()
    return {
        {
            label = "Cut Subtrack",
            locations = { "Assets" },
            query = { selection = { type = "resource", cardinality = "one" } },
            active = active_function,
            run = run_cut_editor_function,
        }
    }
end

return M

## sound play

local ffmpeg_helper = require "editor-scripts.ffmpeg_helper"
local file_helper = require "editor-scripts.file_helper"
local ui_helper = require "editor-scripts.ui_helper"

local M = {}

local active_function = function(opts)
    -- Only active if the selected resource is a supported sound file
    local sound_path = editor.get(opts.selection, "path")
    return file_helper.is_sound_file(sound_path)
end

--[[local run_in_terminal_function = function(opts)
    local sound_path = editor.get(opts.selection, "path")
    local window_title = 'Defold_FFPLAY_' .. tostring(os.time())

    -- Start playing sound in terminal
    ffmpeg_helper.execute_play_sound_in_window(sound_path, window_title)

    -- While sound is playing - show popup
    local title_text = "Playing Sound: "..sound_path
    local button_text = "Stop"
    ui_helper.show_dialog_single_button(title_text, button_text)

    -- When dialog is closed, continue and kill ffplay process:
    ffmpeg_helper.execute_kill_ffplay()
end]]

local function cleanup_temp_directory(temp_directory, vbs_script_path)
    -- Remove the temporary VBS file
    if vbs_script_path and file_helper.exists(vbs_script_path) then
        file_helper.remove(vbs_script_path)
    end
    -- Safely remove the temporary directory
    if temp_directory and file_helper.exists("." .. temp_directory) then
        local remove_success, remove_error = pcall(function()
            file_helper.remove_directory_recursive("." .. temp_directory)
        end)
        if not remove_success then
            print("Warning: Failed to remove temporary directory: " .. tostring(remove_error))
        else
            print("Successfully removed temporary directory: " .. temp_directory)
        end
    end
end

local run_in_background_function = function(opts)
    local sound_path = "." .. editor.get(opts.selection, "path")
    local temp_directory = "/editor-scripts/tmp_play"
    -- Make sure the temporary directory is empty before creating it
    cleanup_temp_directory(temp_directory, nil)
    file_helper.create_directory(temp_directory)
    -- Create and run the VBS script
    local vbscript_command_run_ffplay = ffmpeg_helper.create_vbscript_command_ffplay(sound_path)
    local vbs_script_path = file_helper.create_vbscript(vbscript_command_run_ffplay, temp_directory)
    local success, result = pcall(function()
        return editor.execute('wscript.exe', vbs_script_path)
    end)
    if not success then
        local error_text = "Failed to execute VBScript:\n" .. tostring(result)
        ui_helper.show_error(error_text)
    else
        -- Show dialog while playing the sound
        local title_text = "Playing Sound: " .. sound_path
        local button_text = "Stop"
        ui_helper.show_dialog_single_button(title_text, button_text)
        -- After closing the dialog, check if ffplay is still running and stop it if so
        if ffmpeg_helper.is_ffplay_running() then
            ffmpeg_helper.execute_kill_ffplay()
        else
            print("Sound playback has already finished.")
        end
    end
    -- Always perform cleanup at the end, regardless of the outcome
    cleanup_temp_directory(temp_directory, vbs_script_path)
end

function M.get_commands()
    return {
        --[[{    -- Safe version that plays explicitly in Terminal Window
            label = "Play in Terminal",
            locations = { "Assets" },
            query = { selection = { type = "resource", cardinality = "one" } },
            active = active_function,
            run = run_in_terminal_function
        },]]
        {
            label = "Play",
            locations = { "Assets" },
            query = { selection = { type = "resource", cardinality = "one" } },
            active = active_function,
            run = run_in_background_function
        }
    }
end

return M