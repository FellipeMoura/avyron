class_name DuelScreen
extends Control

## HUD de duelo em quatro painéis de canto, com o mundo 3D visível atrás.
##
## Não é a UI final do jogo — é instrumento de playtest. Continua tudo em texto
## monoespaçado com BBCode; o que mudou em relação à versão anterior é o
## enquadramento: nada mais cobre a tela inteira. Cada painel ocupa um canto,
## deixando o meio livre para o mundo — o que casa com a especificação
## `escala-e-camera-de-batalha`: "combate no mesmo espaço, sem corte de cena".
##
##   top-left     card do adversário   (nome, classe·elemento, HP, carga, awakening)
##   top-right    card do jogador      (mesmo layout, espelhado no anchor)
##   bottom-left  log recente          (últimas rodadas + `dados X.YZ`)
##   bottom-right ações                (golpes 1–6, comandos, mensagem/desfecho)
##
## Teclas: 1-6 golpes · E desperta · C captura · F foge · R reinicia · Esc sai

const DEFAULT_LEVEL := 25
const LOG_LINES := 6
const BAR_WIDTH := 16

## Fade-in do overlay durante a transição de entrada. Casado com o
## `IsoCamera.zoom_in_duration` — se um dos dois passar por variação, os dois
## precisam variar juntos, senão os painéis aparecem fora do ritmo do
## movimento da câmera.
const INTRO_FADE_SEC := 0.5

## Padding dos painéis em relação à borda da tela.
const EDGE_INSET := 16
## Largura mínima de card e painel de ações — larga o bastante para caber o
## nome+level+elemento e a lista de golpes sem quebra de linha.
const CARD_MIN_WIDTH := 320
const ACTIONS_MIN_WIDTH := 480
const LOG_MIN_WIDTH := 380

## Emitido quando o jogador sai da tela. Quem abriu decide o que fazer —
## voltar a cena, destravar a câmera, liberar a criatura para reengajar.
signal closed(outcome: int)

## Preenchidos por quem abre a tela como overlay. Vazios = sorteio livre, que
## é o comportamento quando a cena roda sozinha para playtest.
var player_code := ""
var enemy_code := ""
var duel_level := DEFAULT_LEVEL

## Paleta herdada dos tokens do app web.
const COL_BONE := "#F2EDE0"
const COL_MOSS := "#7A8C6B"
const COL_EMBER := "#C6552F"
const COL_SLATE := "#6B7280"
const COL_PANEL_BG := "#0A0B0D"
const COL_PANEL_BORDER := "#1F2530"

var battle: Battle
var _rng := RandomNumberGenerator.new()
var _last_message := ""

var _enemy_label: RichTextLabel
var _player_label: RichTextLabel
var _log_label: RichTextLabel
var _actions_label: RichTextLabel

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
	# O root não intercepta o mouse — cliques atravessam para o mundo. Cada
	# painel individual também é IGNORE, mais abaixo.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Fade-in coordenado com a transição da câmera. Só faz sentido quando a
	# tela é aberta como overlay do WorldRoot; rodando solta em playtest, o
	# fade seria só um estorvo.
	if get_tree().current_scene != self:
		modulate.a = 0.0
		var fade := create_tween()
		fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		fade.tween_property(self, "modulate:a", 1.0, INTRO_FADE_SEC)

	# Grade full-rect com spacers expansíveis — a mesma ideia de flexbox. Cada
	# canto recebe seu PanelContainer, que auto-dimensiona pelo conteúdo. O
	# esquema antigo por `set_anchors_preset` + offset manual quebrava para os
	# cantos direito/inferior: sem esticar offset_left/top, o rect virava
	# largura zero e o painel sumia. Aqui o container faz o cálculo.
	var vbox := VBoxContainer.new()
	vbox.name = "Grid"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, EDGE_INSET
	)
	add_child(vbox)

	var top_row := _make_row("TopRow")
	vbox.add_child(top_row)
	_enemy_label = _add_card(top_row, "EnemyCard", CARD_MIN_WIDTH)
	_add_spacer(top_row, true)
	_player_label = _add_card(top_row, "PlayerCard", CARD_MIN_WIDTH)

	_add_spacer(vbox, false)

	var bot_row := _make_row("BottomRow")
	vbox.add_child(bot_row)
	_log_label = _add_card(bot_row, "LogPanel", LOG_MIN_WIDTH)
	_add_spacer(bot_row, true)
	_actions_label = _add_card(bot_row, "ActionsPanel", ACTIONS_MIN_WIDTH)

	_start_new_duel()


func _make_row(row_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


## Spacer entre dois painéis do mesmo eixo. Empurra os vizinhos para as
## bordas — é o único jeito de "alinhar à direita" num HBoxContainer.
func _add_spacer(parent: Container, horizontal: bool) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal:
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)


## Constrói um card (PanelContainer + RichTextLabel) e o anexa à linha.
## Devolve o label — quem chama já perdeu o interesse no container.
func _add_card(parent: Container, node_name: String, min_width: int) -> RichTextLabel:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(min_width, 0)
	# Não estica: o card fica no tamanho que o conteúdo pedir, deixando o
	# spacer ao lado engolir o resto do espaço.
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = Color(COL_PANEL_BG, 0.88)
	style.border_color = Color(COL_PANEL_BORDER)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var label := RichTextLabel.new()
	label.name = "Label"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 14)
	panel.add_child(label)

	return label


# ---------------------------------------------------------------------------
# ciclo do duelo
# ---------------------------------------------------------------------------

func _start_new_duel() -> void:
	var codes: Array = _db.creature_codes()
	codes.sort()

	var a := player_code
	var b := enemy_code
	if a == "":
		a = codes[_rng.randi() % codes.size()]
	if b == "":
		b = codes[_rng.randi() % codes.size()]
		while b == a:
			b = codes[_rng.randi() % codes.size()]

	var hero := Combatant.from_bestiary(_db, a, duel_level)
	var foe := Combatant.from_bestiary(_db, b, duel_level)
	battle = Battle.new(_db, [hero], foe)
	_last_message = "Duelo iniciado. Escolha um golpe."
	_render()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode

	if key == KEY_ESCAPE:
		closed.emit(battle.outcome)
		# Rodando como cena principal não há quem trate o sinal, então a tela
		# volta ao mapa por conta própria. Como overlay, quem abriu decide.
		if get_tree().current_scene == self:
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	if key == KEY_R:
		# Um duelo aberto por encontro tem adversário definido; reiniciar ali
		# repetiria o mesmo confronto, o que não é o que a tecla promete.
		if enemy_code == "":
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

	_enemy_label.text = _combatant_block(foe, "adversario")
	_player_label.text = _combatant_block(hero, "voce")
	_log_label.text = _log_block()
	_actions_label.text = _actions_block(hero)


func _combatant_block(c: Combatant, role: String) -> String:
	var lines: Array[String] = []
	var awakened := ""
	if c.is_awakened:
		awakened = "  [color=%s]DESPERTO (%d)[/color]" % [COL_EMBER, c.awakened_rounds_left]

	lines.append("[color=%s]%s[/color]  [b]%s[/b]  Lv%d%s"
		% [COL_SLATE, role, c.display_name, c.level, awakened])
	lines.append("[color=%s]%s · %s[/color]"
		% [COL_SLATE, _class_name(c.creature_class), _element_name(c.element)])
	lines.append("HP    %s  %d/%d"
		% [_bar(float(c.hp) / float(c.max_hp), COL_MOSS), c.hp, c.max_hp])
	lines.append("Carga %s  %d/100"
		% [_bar(c.charge_meter / battle.charge_max(), COL_EMBER), int(c.charge_meter)])
	return "\n".join(lines)


## Barra em ASCII de propósito: blocos unicode dependem da fonte ter o glifo,
## e uma barra que vira retângulo vazio é pior que uma barra feia.
func _bar(ratio: float, color: String) -> String:
	var filled := int(round(clampf(ratio, 0.0, 1.0) * BAR_WIDTH))
	return "[color=%s]%s[/color][color=%s]%s[/color]" % [
		color, "|".repeat(filled),
		COL_SLATE, ".".repeat(BAR_WIDTH - filled),
	]


func _actions_block(c: Combatant) -> String:
	var out: Array[String] = []

	if battle.is_over():
		out.append("[color=%s]%s[/color]" % [COL_EMBER, _outcome_text()])
		out.append("")
		out.append("[color=%s][R] novo duelo    [Esc] voltar ao mapa[/color]" % COL_SLATE)
	else:
		out.append(_ability_list(c))
		out.append("")
		out.append(_command_line(c))

	if _last_message != "":
		out.append("")
		out.append("[color=%s]%s[/color]" % [COL_EMBER, _last_message])

	return "\n".join(out)


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

		lines.append("[color=%s][%d][/color] %-20s %-8s %-28s %d usos"
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
	parts.append("[color=%s][C] capturar  [F] fugir  [R] reiniciar  [Esc] mapa[/color]" % COL_SLATE)
	return "  ".join(parts)


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


## Log com o dataVersion como cabeçalho discreto — permanece rastreável em
## bug reports sem ocupar espaço nobre da HUD.
func _log_block() -> String:
	var lines: Array[String] = []
	lines.append("[color=%s]log · dados %s[/color]" % [COL_SLATE, _db.data_version])
	var start := maxi(0, battle.log_events.size() - LOG_LINES)
	for i in range(start, battle.log_events.size()):
		var e: Dictionary = battle.log_events[i]
		var color := COL_SLATE
		if e["type"] in ["awaken", "revert", "faint", "capture"]:
			color = COL_EMBER
		lines.append("[color=%s]r%d[/color] [color=%s]%s[/color]"
			% [COL_SLATE, e["round"], color, str(e.get("text", e["type"]))])
	return "\n".join(lines)


func _element_name(code: String) -> String:
	if code == "":
		return "—"
	var e := _db.element(code)
	return str(e.get("name", code))


func _class_name(code: String) -> String:
	var c := _db.creature_class(code)
	return str(c.get("name", code))


## Concatena o texto puro (sem BBCode) dos quatro painéis. Usado só nos testes
## headless — a lógica de renderização passou a viver em quatro labels
## independentes, e sem esse resumão as asserções por conteúdo teriam de
## andar de painel em painel.
func debug_text() -> String:
	var chunks: Array[String] = []
	for label in [_enemy_label, _player_label, _log_label, _actions_label]:
		if label:
			chunks.append(label.get_parsed_text())
	return "\n".join(chunks)
