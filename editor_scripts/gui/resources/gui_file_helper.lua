local M = {}

function M.build(script_path)
	return string.format([[script: "%s"
fonts {
	name: "default"
	font: "/builtins/fonts/default.font"
}
material: "/builtins/materials/gui.material"
adjust_reference: ADJUST_REFERENCE_PARENT
]], script_path)
end

return M
