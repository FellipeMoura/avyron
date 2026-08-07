class_name DuelScreen
extends Control

## Tela de duelo para testar o combate na mão.
##
## Não é a UI do jogo — é instrumento de playtest. Tudo é texto monoespaçado
## em um único RichTextLabel, porque o que precisa ser avaliado aqui é o
## *ritmo* do combate: se cinco rodadas dão espaço tático, se o Despertar
## chega na hora certa, se a vantagem elemental é sentida. Barra de vida
## bonita não responde nada disso e atrasaria a resposta.
##
## Teclas: 1-6 golpes · E desperta · C captura · F foge · R reinicia · Esc sai

const LEVEL := 25
const LOG_LINES := 8
const BAR_WIDTH := 16

## Paleta herdada dos tokens do app web.
const COL_BONE := "#F2EDE0"
const COL_MOSS := "#7A8C6B"
const COL_EMBER := "#C6552F"
const COL_SLATE := "#6B7280"

var battle: Battle
var _label: RichTextLabel
var _rng := RandomNumberGenerator.new()
var _last_message := ""

## Resolvido por caminho, não pelo identificador global do autoload.
##
## Referenciar `Bestiary` direto torna este script incompilável fora de uma
## execução normal do jogo — o modo `--script` não registra autoloads, e isso
## quebraria tanto o gerador de cena quanto os testes headless. Com o
## fallback, a tela também funciona instanciada sozinha.
var _db: BestiaryData


func _ready() -> void:
	_db = get_node_or_null("/root/Bestiary") as BestiaryData
	if _db == null:
		_db = BestiaryData.new()
		add_child(_db)

	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("#0A0B0D")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 24
	_label.offset_top = 20
	_label.offset_right = -24
	_label.offset_bottom = -20
	_label.add_theme_font_size_override("normal_font_size", 15)
	add_child(_label)

	_start_new_duel()


# ---------------------------------------------------------------------------
# ciclo do duelo
# ---------------------------------------------------------------------------

func _start_new_duel() -> void:
	var codes: Array = _db.creature_codes()
	codes.sort()
	var a: String = codes[_rng.randi() % codes.size()]
	var b: String = codes[_rng.randi() % codes.size()]
	while b == a:
		b = codes[_rng.randi() % codes.size()]

	var hero := Combatant.from_bestiary(_db, a, LEVEL)
	var foe := Combatant.from_bestiary(_db, b, LEVEL)
	battle = Battle.new(_db, [hero], foe)
	_last_message = "Duelo iniciado. Escolha um golpe."
	_render()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode

	if key == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	if key == KEY_R:
		_start_new_duel()
		return
	if battle.is_over():
		return

	# Despertar não consome o turno, então não dispara a rodada.
	if key == KEY_E:
		if battle.activate_awakening(true):
			_last_message = ""
		else:
			_last_message = "O medidor de carga ainda nao esta cheio."
		_render()
		return

	var action: BattleAction = null
	if key >= KEY_1 and key <= KEY_9:
		var index := key - KEY_1
		var options := battle.player_active().available_abilities()
		if index < options.size():
			action = BattleAction.use_ability(str(options[index]["code"]))
		else:
			_last_message = "Nao existe golpe nessa posicao."
			_render()
			return
	elif key == KEY_C:
		action = BattleAction.capture()
	elif key == KEY_F:
		action = BattleAction.flee()

	if action == null:
		return

	_last_message = ""
	battle.resolve_round(action, battle.choose_enemy_action())
	_render()


# ---------------------------------------------------------------------------
# desenho
# ---------------------------------------------------------------------------

func _render() -> void:
	var hero := battle.player_active()
	var foe := battle.enemy
	var out: Array[String] = []

	out.append("[color=%s]AVYRON[/color]  [color=%s]duelo de teste — dados %s[/color]"
		% [COL_EMBER, COL_SLATE, _db.data_version])
	out.append("")
	out.append(_combatant_block(foe, "adversario"))
	out.append(_combatant_block(hero, "voce"))
	out.append(_rule())

	if battle.is_over():
		out.append("")
		out.append("[color=%s]%s[/color]" % [COL_EMBER, _outcome_text()])
		out.append("")
		out.append("[color=%s][R] novo duelo    [Esc] voltar ao mapa[/color]" % COL_SLATE)
	else:
		out.append(_ability_list(hero))
		out.append("")
		out.append(_command_line(hero))

	if _last_message != "":
		out.append("[color=%s]%s[/color]" % [COL_EMBER, _last_message])

	out.append(_rule())
	out.append(_recent_log())

	_label.text = "\n".join(out)


func _combatant_block(c: Combatant, role: String) -> String:
	var lines: Array[String] = []
	var awakened := ""
	if c.is_awakened:
		awakened = "  [color=%s]DESPERTO (%d)[/color]" % [COL_EMBER, c.awakened_rounds_left]

	lines.append("[color=%s]%s[/color]  [b]%s[/b]  Lv%d  %s / %s%s"
		% [COL_SLATE, role, c.display_name, c.level,
		   _class_name(c.creature_class), _element_name(c.element), awakened])
	lines.append("  HP   %s  %d/%d"
		% [_bar(float(c.hp) / float(c.max_hp), COL_MOSS), c.hp, c.max_hp])
	lines.append("  Carga%s  %d/100"
		% [_bar(c.charge_meter / battle.charge_max(), COL_EMBER), int(c.charge_meter)])
	lines.append("")
	return "\n".join(lines)


## Barra em ASCII de propósito: blocos unicode dependem da fonte ter o glifo,
## e uma barra que vira retângulo vazio é pior que uma barra feia.
func _bar(ratio: float, color: String) -> String:
	var filled := int(round(clampf(ratio, 0.0, 1.0) * BAR_WIDTH))
	return "[color=%s]%s[/color][color=%s]%s[/color]" % [
		color, "|".repeat(filled),
		COL_SLATE, ".".repeat(BAR_WIDTH - filled),
	]


func _ability_list(c: Combatant) -> String:
	var lines: Array[String] = []
	var options := c.available_abilities()
	for i in options.size():
		var a: Dictionary = options[i]
		var elem_code := BestiaryData.ability_element(a)
		var element := _element_name(elem_code)
		var detail := ""
		if int(a["power"]) > 0:
			var mult := 1.0
			if elem_code != "":
				mult = _db.element_multiplier(elem_code, battle.enemy.element)
			var flag := ""
			if mult > 1.0:
				flag = "  [color=%s]eficaz[/color]" % COL_MOSS
			elif mult < 1.0:
				flag = "  [color=%s]fraco[/color]" % COL_SLATE
			detail = "pot %-3d  prec %d%%%s" % [int(a["power"]), int(a["accuracy"]), flag]
		else:
			detail = str(a["effectCode"]).replace("_", " ")

		var mark := ""
		if bool(a["awakeningOnly"]):
			mark = "[color=%s]*[/color]" % COL_EMBER

		lines.append("  [color=%s][%d][/color] %-20s %-8s %-28s %d usos"
			% [COL_BONE, i + 1, str(a["name"]) + mark, element, detail,
			   c.uses_left(str(a["code"]))])
	return "\n".join(lines)


func _command_line(c: Combatant) -> String:
	var parts: Array[String] = []
	if c.can_awaken(battle.charge_max()):
		parts.append("[color=%s][E] DESPERTAR ANCESTRAL[/color]" % COL_EMBER)
	else:
		parts.append("[color=%s][E] despertar (carga %d/100)[/color]"
			% [COL_SLATE, int(c.charge_meter)])
	parts.append("[color=%s][C] capturar   [F] fugir   [R] reiniciar   [Esc] mapa[/color]" % COL_SLATE)
	return "  " + "    ".join(parts)


func _outcome_text() -> String:
	match battle.outcome:
		Battle.Outcome.PLAYER_WON:
			return "Voce venceu em %d rodadas." % battle.round_number
		Battle.Outcome.PLAYER_LOST:
			return "Sua criatura foi derrotada em %d rodadas." % battle.round_number
		Battle.Outcome.CAPTURED:
			return "%s foi capturada!" % battle.enemy.display_name
		Battle.Outcome.FLED:
			return "Voce fugiu."
		_:
			return ""


func _recent_log() -> String:
	var lines: Array[String] = []
	var start := maxi(0, battle.log_events.size() - LOG_LINES)
	for i in range(start, battle.log_events.size()):
		var e: Dictionary = battle.log_events[i]
		var color := COL_SLATE
		if e["type"] in ["awaken", "revert", "faint", "capture"]:
			color = COL_EMBER
		lines.append("  [color=%s]r%d[/color] [color=%s]%s[/color]"
			% [COL_SLATE, e["round"], color, str(e.get("text", e["type"]))])
	return "\n".join(lines)


func _rule() -> String:
	return "[color=%s]%s[/color]" % [COL_SLATE, "-".repeat(72)]


func _element_name(code: String) -> String:
	if code == "":
		return "—"
	var e := _db.element(code)
	return str(e.get("name", code))


func _class_name(code: String) -> String:
	var c := _db.creature_class(code)
	return str(c.get("name", code))
