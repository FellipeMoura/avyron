class_name PlayerSetWindow
extends PanelContainer

## Janela do set do jogador (tecla `E`): visão dos equipamentos do domador.
##
## Hoje só tem um slot — o Relicário —, mas a janela já vive separada do
## posto do relicário (`RelicStationScreen`) porque os dois respondem a
## perguntas diferentes: o posto é onde o equipamento se *gerencia*
## (depositar/retirar/trocar de modelo, só perto do ponto fixo do mapa); esta
## janela é só a *visão* do que está equipado, consultável de qualquer lugar,
## sem exigir estar em ponto nenhum — o mesmo espírito da janela do time
## (`RosterWindow`, tecla `T`).
##
## Somente leitura por enquanto — sem clique, sem escolha, sem modo. Quando o
## set ganhar mais peças (buff de batalha, Despertar, troca, exploração —
## fora de escopo aqui, ver documento `relicario`), cada uma vira uma nova
## seção de texto aqui, não uma janela nova: a lista de seções é o que cresce,
## não o número de telas que o jogador precisa lembrar.

const COL_BONE  := "#F2EDE0"
const COL_MOSS  := "#7A8C6B"
const COL_SLATE := "#6B7280"

var _label: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left   = -260
	offset_right  = 260
	offset_top    = 0
	offset_bottom = 0
	# `PRESET_CENTER` sozinho só cresce para baixo — mesma correção que
	# `RosterWindow`/`RelicStationScreen` já aplicam, pela mesma razão.
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0A0B0D", 0.96)
	style.border_color = Color("#1F2530")
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	hide()


func is_open() -> bool:
	return visible


func toggle() -> void:
	visible = not visible


func close() -> void:
	hide()


## Redesenha com o relicário equipado — `relic == null` é estado normal
## enquanto não existir sistema de aquisição (ou, hoje, se o bundle não tiver
## o modelo starter — ver `WorldRoot._pick_starter_relic`), não um erro a
## esconder.
func refresh(db: BestiaryData, relic: PlayerRelic) -> void:
	if _label == null:
		return

	var lines: Array[String] = []
	lines.append("[color=%s][b]set do jogador[/b][/color]" % COL_BONE)
	lines.append("")
	lines.append("[color=%s]RELICARIO[/color]" % COL_SLATE)
	if relic == null or db == null:
		lines.append("[color=%s]nenhum relicario equipado[/color]" % COL_SLATE)
	else:
		lines.append_array(_relic_lines(db, relic))
	lines.append("")
	lines.append("[color=%s][ sem outras pecas de equipamento ainda ][/color]" % COL_SLATE)
	lines.append("")
	lines.append("[color=%s][Esc] fecha[/color]" % COL_SLATE)
	_label.text = "\n".join(lines)


func _relic_lines(db: BestiaryData, relic: PlayerRelic) -> Array[String]:
	var out: Array[String] = []
	var cap := relic.max_level(db)
	out.append("  [color=%s]%s[/color]   [color=%s]nivel %d%s[/color]" % [
		COL_BONE, relic.display_name(db), COL_MOSS, relic.level,
		("/%d" % cap) if cap > 0 else "",
	])
	# "—" para elemento/classe ausentes — o starter neutro (documento
	# `relicario`) não tem afinidade nenhuma, e isso é o esperado, não um
	# dado faltando.
	out.append("  [color=%s]afinidade[/color]  %s · %s" % [
		COL_SLATE, _element_name(db, relic.element_code(db)), _class_name(db, relic.class_code(db)),
	])
	out.append("  [color=%s]slots[/color]  %d   [color=%s]xp[/color]  %d/%d   [color=%s]taxa de captura[/color]  %.0f" % [
		COL_SLATE, relic.slot_capacity(db),
		COL_SLATE, relic.xp, relic.xp_to_next(db),
		COL_SLATE, relic.capture_rate(db),
	])
	return out


func _element_name(db: BestiaryData, code: String) -> String:
	if code == "":
		return "—"
	return str(db.element(code).get("name", code))


func _class_name(db: BestiaryData, code: String) -> String:
	if code == "":
		return "—"
	return str(db.creature_class(code).get("name", code))
