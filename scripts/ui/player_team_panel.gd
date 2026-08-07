class_name PlayerTeamPanel
extends PanelContainer

## Painel do time do jogador no mapa de exploração.
##
## Mostra os slots de captura: quantos existem e o que há em cada um.
## Atualizado via `refresh` sempre que o time muda.

const MAX_SLOTS := 1

const COL_BONE := "#F2EDE0"
const COL_SLATE := "#6B7280"

var _label: RichTextLabel
var _db: BestiaryData


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left  = -220
	offset_top   = 16
	offset_right = -16
	offset_bottom = 76
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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


func setup(db: BestiaryData) -> void:
	_db = db
	refresh([])


func refresh(team_codes: Array[String]) -> void:
	if _label == null:
		return
	var lines: Array[String] = []
	lines.append("[color=%s]time[/color]" % COL_SLATE)
	for i in MAX_SLOTS:
		if i < team_codes.size():
			var code := team_codes[i]
			var c := _db.creature(code) if _db else {}
			var creature_name := str(c.get("name", code))
			var elem_code := str(c.get("element", ""))
			var elem := _db.element(elem_code) if (_db and elem_code != "") else {}
			var elem_name := str(elem.get("name", "—")) if not elem.is_empty() else "—"
			lines.append("[color=%s][b]%s[/b]  %s[/color]" % [COL_BONE, creature_name, elem_name])
		else:
			lines.append("[color=%s][ vazio ][/color]" % COL_SLATE)
	_label.text = "\n".join(lines)
