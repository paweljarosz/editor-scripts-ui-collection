# Collection of Defold Editor Scripts and UI

This project contains Useful Editor Scripts with custom UI for Defold.

This project contains also several "helper" Lua modules for doing recurring stuff for Editor Scripts and UI e.g. string operations (`string_helper`), file operations (`file_helper`), some common UI stuff (`ui_helper`) and other, like helpers for resources - for creating or modifying text files being Defold components or resources. Use them in your own scripts too!

All scripts are tested on Linux (Ubuntu 24.04) and Windows.
OS-independent scripts should work on all platforms, but sound related uses external ffmpeg.

PRs are welcomed. If you spot any issues, report them!

# Installation

You can use the these editor scripts in your own project by adding this project as a [Defold library dependency](https://www.defold.com/manuals/libraries/). Open your `game.project` file and in the dependencies field under project add:

`https://github.com/paweljarosz/editor-scripts-ui-collection/archive/master.zip`

or particular version - newest is 1.2:

`https://github.com/paweljarosz/editor-scripts-ui-collection/archive/v1.2.zip`

You can also just copy and paste needed scripts directly to your project directory and modify them to suit your needs (default file content, default reference files, etc.).

---

# Models 🧸

## model_from_gltf 🌐

Create any number `.model` component files out of selected or added `.gltf` meshes, all with one configured material and sampler textures into the given output folder (or in place of GLTF files by default). The script uses a rich dialog UI for selecting files and defining other properties.

1. Open UI:
 - **Project command** – open the **Project** context menu and pick `Create Models From GLTF` to start from scratch or:
 - **Assets command** – select one or more `.gltf` files in **Assets**, right‑click, and choose `Create Models From GLTF` to prefill the dialog with those files.
2. Configure output directory, which material is used, assign textures to each sampler of the given material.
3. Add/remove GLTF files via the dedicated picker. Use `+Add Many` to add files in batch or `+Add` to add a single entry. Use `-` (minus) button to remove a given entry.
4. Use checkbox for each file if the output model should have the property `Create GO Bones` enabled/disabled. Use checkbox at the bottom `Mark All Create Go Bones Disabled/Enabled` to do it for all.
5. Resolve any validation warnings (duplicate targets, missing textures, etc.), then click `Create Models` to generate the `.model` files. The script automatically creates directories if needed and reports success or errors in Console.

![](media/models_from_gltf.gif)

---

# GUI 📱

## gui_add_script 📜

It quickly creates a default `.gui_script` file and links it to each selected `.gui` component immediately (to `Script` property).

1. Right click on any `.gui` file or a selection of files including `.gui` files in `Assets`.
2. Select `Add GUI Script`.

![](media/add-gui-script.gif)

## gui_add_to_collection 📲

It creates both `.gui` component and `.gui_script` files binded together **and** puts a game object with gui component with this gui directly in the given collection. It also has a UI popup, where you can type a name.

1. Right click on `Collection` in your collection's `Outline` pane.
2. Select `Add GUI to collection`.
3. Type in a name and click `Enter`.
4. Click `Create`.

![](media/add-gui-collection.gif)

---

# Sound 🔊

> Note! Read FFmpeg dependency section below before first use.

##  sound-convert ♻️

It allows you to convert sound file(s) (`.mp3`, `.wav.`, `.ogg`, `.flac` or `.aac`.) to one of Defold compatible sound files (`.wav`, `.ogg`).

1. Right click on any sound file (or selected multiple sound files).
2. Select `Convert Sound`.
3. Select output file format from a dropdown list (`OGG` or `WAV`)
4. Click `Convert`

For each source file, it creates a file with the same name as a source file, in the same location, but with `.wav` / `.ogg` extension. File is at 44100 Hz.

![](media/sound-convert.gif)

## sound-play ▶️

It allows you to "prehear" given sound. Plays `.mp3`, `.wav`, `.ogg`, `.flac` or `.aac`. It plays the sound once either until end of file or until the moment when the popup UI is closed.

1. Right click on any sound file.
2. Select `Play`

![](media/sound-play.gif)

P.S.
There are two versions of this script actually, but second is commented out:
1. **Play**
when you run it first time your OS might go crazy - it plays in background, but because of this, it requires your explicit permissions, e.g. Windows asks for permission to run from Unknown Publisher.
You can uncheck this bottom checkbox saying `"Always ask before opening this file"` and it should never prompt again.
Your antivirus might also block or quantine it - you can make an exception for it.
opens terminal window additionally. You can then either close this window or closing the UI popup in Defold will also close it.
2. **Play in Terminal**  
because of issues above, I leave there another version that is "safe" - plays in separate Terminal Window. If you like it more, you can use this (just comment out Play in Terminal command in the script).

I would love if someone could figure out and propose better solutions :D 

## sound-cut ✂️

It allows you to cut a subtrack out of the source track (`.mp3`, `.wav`, `.ogg`, `.flac` or `.aac`). It needs `start` and `end` timestamps and creates one subtrack saved into file of same format, where X is start (in seconds from original sound beginning) and Y is stop timestamp (in s). 
`end` has to be larger than `start`. 
`end` can't be larger than source sound duration (provided as information in popup)

1. Right click on any sound file.
2. Select `Cut Subtrack`.
3. Set `Start Time` and `End Time` timestamps (in seconds). Eventually change output Subtrack file name.
4. *Experimental.* You can eventually "prehear" the cut subtrack by clicking `Play Subtrack` button. Close the popup to stop it playing.
5. Click `Extract` to extract the cut subtrack to a file.

![](media/sound-cut.gif)

P.S. It checks for input validity and also asks if you want to overwrite if file with same name exists. Also, make sure you click "somewhere" after editing inputs - value is changed "on release" not on input changes, so before you click "Play Subtrack", ensure the changed values are "in".

P.P.S. I know, it would be great to have a visual waveform on a timeline with start and end markers for it to be convenient, but anyway - it simplifies this process a lot and you don't need to explicitly use external programs ;)

## sound-component 🔊

Turn multiple `.wav`/`.ogg` files into `.sound` resources in one pass.

1. Select the desired sound files in **Assets** (only `.wav` and `.ogg` populate the dialog).
2. Run `Create Sound Components`.
3. A scrollable table opens showing each sound on its own two-row card. The top row lists the index, file path, and remove button; the bottom row is aligned under fixed headers for `Loop`, `Count` (Loopcount), `Group`, `Gain`, `Pan`, and `Speed`.
4. Adjust properties per row (loop counts, groups, gain/pan/speed). The header stays visible while scrolling when more than six sounds are selected.
5. Click **Create Sound Components** and the `.sound` files are emitted next to their source clips.

![](media/sound-components.gif)

---

# FFmpeg dependency

Currently, there is no possibility to do anything with sounds in Editor Scripts, afaik. So I used powerful `execute` and utilised FFmpeg.

In order to use them, you have to install FFmpeg then. Download executables from:

https://www.ffmpeg.org/download.html

And add installation localization to PATH (windows).

On Windows you can also:
1. Open Windows Powershell
2. `winget install ffmpeg`
3. `Y` to confirm
4. Check installation path: `where ffmpeg`
( should give e.g. --> `C:\ffmpeg\bin\ffmpeg.exe`)

On Linux you can (though scripts are Windows only - they need modifications to run on Linux):
1. Open terminal
2. `sudo apt install ffmpeg` (or `sudo snap install ffmpeg`)
3. `Y` to confirm
4. Check installation path: `which -a ffmpeg`
(should give e.g. --> `/usr/bin/ffmpeg` or `/bin/ffmpeg`)

Scripts tries to automatically detect correct paths when you click `Reload Editor Scripts`.
If your path is not found, please modify it in scripts (perhaps there should be a script to install ffmpeg and add its path here, but for now.. heh :sweat_smile:) in the common `ffmpeg_helper.lua` module:

    -- Adjust the paths if needed
    local FFMPEG_PATH = "C:/ffmpeg/bin/ffmpeg.exe"
    local FFPLAY_PATH = "C:/ffmpeg/bin/ffplay.exe"
    local FFPROBE_PATH = "C:/ffmpeg/bin/ffprobe.exe"


## FFplay and FFprobe dependency

Additionally, sound-play Editor Script utilizes `ffplay` and sound-cut utilizes `ffprobe`.
Ensure that `ffplay` and `ffprobe` comes with your installation. They might be in `.../ffmpeg/bin/`. 
Check `ffplay -version` and ``ffprobe -version` in terminal. If not, [download them](https://github.com/BtbN/FFmpeg-Builds/releases) and copy there.

---

# License

For full license details, see the [LICENSE.md](LICENSE.md) file.

# Issues and suggestions

If you have any issues, questions or suggestions please [create an issue](https://github.com/paweljarosz/editor-scripts-ui-collection/issues).


# ❤️ Support ❤️

If you appreciate what I'm doing, please consider supporting me!

[![Patreon](https://img.shields.io/badge/Patreon-f96854?style=for-the-badge&logo=patreon&logoColor=white)](https://www.patreon.com/witchcrafter_rpg)
[![Github-sponsors](https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#EA4AAA)](https://github.com/sponsors/paweljarosz) [![Ko-Fi](https://img.shields.io/badge/Ko--fi-F16061?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/witchcrafter) 
