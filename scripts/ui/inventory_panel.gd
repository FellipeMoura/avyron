class_name InventoryPanel
extends PanelContainer

## Painel de inventário no mapa de exploração (canto superior esquerdo).
## Mostra todos os itens coletados com quantidade.

const COL_BONE  := "#F2EDE0"
const COL_SLATE := "#6B7280"

var _label: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left   = 16
	offset_top    = 16
	offset_right  = 226
	offset_bottom = 196
	mouse_filter  = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0A0B0D", 0.75)
	style.border_color = Color("#1F2530")
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 13)
	add_child(_label)

	refresh([])


func refresh(item_entries: Array) -> void:
	if _label == null:
		return
	var lines: Array[String] = []
	lines.append("[color=%s]minerais  [F] minera[/color]" % COL_SLATE)
	if item_entries.is_empty():
		lines.append("[color=%s][ vazio ][/color]" % COL_SLATE)
	else:
		for e in item_entries:
			var name := OreTable.ore_name(str(e["code"]))
			lines.append("[color=%s]%s[/color]  [b]×%d[/b]" % [COL_BONE, name, int(e["qty"])])
	_label.text = "\n".join(lines)
