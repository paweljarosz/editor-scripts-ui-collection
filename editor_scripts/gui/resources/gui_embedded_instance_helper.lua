local M = {}

function M.build(go_name, gui_path)
	return string.format([[embedded_instances {
	id: "%s"
	data: "components {\n"
	"  id: \"gui\"\n"
	"  component: \"%s\"\n"
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
]], go_name, gui_path)
end

return M
