class_name InventoryPanel
extends PanelContainer

## Painel de inventário no mapa de exploração (canto superior esquerdo).
## Mostra todos os minerais coletados com quantidade.
##
## Os nomes vêm do bundle (`mining.items`), não de uma tabela local: o que o
## jogador lê aqui é o mesmo texto que o bestiário publica, e renomear um
## mineral lá aparece aqui no próximo export sem tocar em código.

const COL_BONE  := "#F2EDE0"
const COL_SLATE := "#6B7280"
const COL_EMBER := "#C6552F"

var _label: RichTextLabel
var _db: BestiaryData


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left   = 16
	offset_top    = 16
	offset_right  = 236
	# Altura zero de propósito: um Control nunca encolhe abaixo do mínimo
	# combinado, então a caixa cresce exatamente até o conteúdo. Altura fixa
	# deixava um retângulo vazio pendurado embaixo de três minerais.
	offset_bottom = 16
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


func setup(db: BestiaryData) -> void:
	_db = db
	refresh([])


## `currency` negativo desliga a linha da bolsa — é o que um bundle sem o
## bloco `economy` produz, e mostrar "0 moedas" ali seria inventar um número.
func refresh(item_entries: Array, currency: int = -1) -> void:
	if _label == null:
		return
	var lines: Array[String] = []
	lines.append("[color=%s]bolsa  ·  [F] minera[/color]" % COL_SLATE)

	if currency >= 0:
		var unit := _db.currency_name(currency) if _db else ""
		lines.append("[color=%s][b]%d[/b] %s[/color]" % [COL_EMBER, currency, unit])

	lines.append("")
	if item_entries.is_empty():
		lines.append("[color=%s][ inventario vazio ][/color]" % COL_SLATE)
	else:
		for e in item_entries:
			var code := str(e["code"])
			var display := _db.item_name(code) if _db else code
			lines.append("[color=%s]%s[/color]  [b]×%d[/b]" % [COL_BONE, display, int(e["qty"])])
	_label.text = "\n".join(lines)
