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
## Somente leitura, e continua sendo com o set em três peças: quem *gerencia*
## é o ponto fixo do mapa — o posto para o Relicário, a bancada para o resto.
## Esta janela responde "o que estou usando?", de qualquer lugar.
##
## O plano de crescer por **seção** e não por janela foi o que se cumpriu:
## Amplificador e Encantador entraram como duas seções aqui, e o jogador não
## teve de aprender tela nenhuma. A regra segue valendo para a próxima peça.

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


## Redesenha com o set atual. `relic == null` é estado normal enquanto não
## existir sistema de aquisição (ou, hoje, se o bundle não tiver o modelo
## starter — ver `WorldRoot._pick_starter_relic`), não um erro a esconder.
##
## `loadout` tem padrão null e as seções aguentam isso porque a janela também
## roda em bancada de teste sem mundo. Slot vazio, aliás, é o estado de todo
## jogador no primeiro minuto: as peças não vêm no boot, se fabricam.
func refresh(db: BestiaryData, relic: PlayerRelic, loadout: PlayerLoadout = null) -> void:
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
	lines.append_array(_slot_lines(db, loadout, BestiaryData.SLOT_AMPLIFIER, "AMPLIFICADOR"))
	lines.append("")
	lines.append_array(_slot_lines(db, loadout, BestiaryData.SLOT_ENCHANTER, "ENCANTADOR"))

	lines.append("")
	lines.append("[color=%s][Esc] fecha[/color]" % COL_SLATE)
	_label.text = "\n".join(lines)


## Uma seção de slot do loadout. Slot vazio diz **onde se resolve isso**, e
## não só que está vazio: "nada equipado" sozinho deixaria o jogador sem saber
## que existe uma bancada, e a peça fica invisível até ele achar o ponto no
## mapa por acaso.
func _slot_lines(
	db: BestiaryData, loadout: PlayerLoadout, slot: String, title: String
) -> Array[String]:
	var out: Array[String] = []
	out.append("[color=%s]%s[/color]" % [COL_SLATE, title])
	if db == null or loadout == null:
		out.append("  [color=%s]nada equipado[/color]" % COL_SLATE)
		return out

	var code := loadout.equipped_in(slot)
	if code == "":
		out.append("  [color=%s]nada equipado  ·  fabrique na bancada[/color]" % COL_SLATE)
		return out

	out.append("  [color=%s]%s[/color]   [color=%s]T%d[/color]" % [
		COL_BONE, db.equipment_name(code), COL_MOSS, db.equipment_tier(code),
	])
	out.append("  [color=%s]efeito[/color]  %s" % [COL_SLATE, _effect_line(db, code)])
	return out


## O modificador em uma frase, com o alvo saindo do **slot** e o sinal saindo
## do código do efeito — as duas fontes que `Battle` usa, lidas do mesmo
## jeito. Nenhum texto aqui inventa quem leva o efeito.
func _effect_line(db: BestiaryData, code: String) -> String:
	var effect := db.equipment_effect_code(code)
	var value := int(db.equipment_effect_value(code))
	var stat := "defesa" if effect.ends_with("_defense") else "ataque"
	if effect.begins_with("debuff_"):
		return "-%d%% de %s do adversario" % [value, stat]
	return "+%d%% de %s da sua criatura" % [value, stat]


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
