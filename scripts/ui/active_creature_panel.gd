class_name ActiveCreaturePanel
extends PanelContainer

## A criatura ativa, no canto superior direito. Substitui o antigo painel de
## time, que mostrava um slot de captura e nada mais.
##
## Mostra o que muda de decisão enquanto se explora: quem está à frente, o que
## ela aguenta, onde está na curva de nível e — o motivo de o painel existir —
## **o que ela minera**. A classe da ativa entra na fórmula da picareta, então
## o perfil de trabalho é informação de mapa, não de menu.
##
## Ao contrário do painel de identificação da criatura selvagem, aqui os stats
## aparecem: esconder número da própria criatura não cria tensão nenhuma, só
## obriga o jogador a abrir a janela do time para uma conta que ele deveria ter
## na cara.
##
## É uma janela simples, na mesma linguagem de `RosterWindow`/`PlayerSetWindow`
## (fundo escuro, borda fina, texto em bbcode). Entre 2026-09 e 2026-09-17
## foi um painel montado sobre ~30 PNGs (moldura, retrato circular por
## shader, barra de HP em imagem, selo de nível, botões em quatro estados),
## medido num canvas de 1536×320 e escalado. Saiu porque era a única peça de
## HUD com layout próprio: cada ajuste (uma linha a mais, uma faixa de XP)
## virava sondagem de pixel em cima de arte, enquanto o resto da HUD muda
## com uma linha de texto. O que ficou da arte é só o card da criatura
## (`res://cards/`), que é conteúdo, não moldura.

signal inventory_requested
signal equipment_requested
signal relicary_requested

const COL_BONE  := "#F2EDE0"
const COL_MOSS  := "#7A8C6B"
const COL_SLATE := "#6B7280"
const COL_EMBER := "#C6552F"

## Mesmo diretório espelhado que `CreatureInfoPanel` consulta — ver o
## comentário lá para o porquê do `ResourceLoader.exists` em vez de erro.
const CARDS_DIR := "res://cards/"

const CARD_SIZE := Vector2(84, 84)
const PANEL_WIDTH := 360

var _db: BestiaryData
var _biome_code := ""

var _card: TextureRect
var _label: RichTextLabel
var _footer: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_right  = -16
	offset_left   = offset_right - PANEL_WIDTH
	offset_top    = 16
	offset_bottom = 16  # cresce até o conteúdo
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	# O container em si não toma clique — o clique de seleção de criatura
	# atrás dele tem de chegar ao mundo. Os botões abaixo, sim: são a função.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0A0B0D", 0.96)
	style.border_color = Color("#1F2530")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)

	_card = TextureRect.new()
	_card.custom_minimum_size = CARD_SIZE
	_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# `EXPAND_IGNORE_SIZE`: sem isso o mínimo do controle vira o tamanho em
	# pixels do PNG e o card infla o painel inteiro (ver `CreatureInfoPanel`).
	_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.hide()
	row.add_child(_card)

	_label = _make_label(13)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)

	_footer = _make_label(12)
	column.add_child(_footer)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(actions)
	actions.add_child(_make_button("bolsa  V", func(): inventory_requested.emit()))
	actions.add_child(_make_button("set  E", func(): equipment_requested.emit()))
	actions.add_child(_make_button("time  T", func(): relicary_requested.emit()))


func _make_label(font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", font_size)
	return label


## Botão de texto, flat, sem foco de teclado — a tecla já é a atalho do
## mundo, e um botão focado engoliria o `WASD`.
func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", Color(COL_SLATE))
	b.add_theme_color_override("font_hover_color", Color(COL_BONE))
	b.add_theme_color_override("font_pressed_color", Color(COL_BONE))
	b.pressed.connect(on_pressed)
	return b


## O bioma entra pelo setup e é trocado por `set_biome`, nunca pelo refresh:
## o refresh roda a cada captura e recebe os números do time, que não têm nada
## a ver com onde o jogador está pisando.
func setup(db: BestiaryData, biome_code: String) -> void:
	_db = db
	_biome_code = biome_code
	refresh("", 1, 0, 6)


## Troca o bioma corrente sem redesenhar — quem redesenha é o refresh seguinte,
## que é quem tem os números do time em mãos.
##
## Existe desde que o bioma virou consulta por posição: ele muda enquanto o
## jogador anda, e chamar `setup` de novo a cada fronteira apagaria o painel
## para o estado vazio no meio da caminhada.
func set_biome(biome_code: String) -> void:
	_biome_code = biome_code


## `hp`/`max_hp` chegam prontos do time em vez de saírem de `stats_at_level`:
## o HP corrente persiste entre batalhas e é o time quem guarda, não o bundle.
## `hp` negativo desliga a linha — é o que o duelo solto de playtest passa.
## `roster_capacity` vem de `PlayerRoster.capacity()` — dinâmico desde que o
## Relicário existe, não mais o `MAX_SLOTS` fixo de antes. `progress` é o
## dicionário de `PlayerRoster.progress_at`; vazio desliga a linha de XP.
func refresh(creature_code: String, level: int, roster_size: int, roster_capacity: int,
		hp: int = -1, max_hp: int = 0, progress: Dictionary = {}) -> void:
	if _label == null:
		return

	var c := _db.creature(creature_code) if (_db and creature_code != "") else {}
	if c.is_empty():
		_card.hide()
		_label.text = "[color=%s]criatura ativa[/color]   [color=%s][ nenhuma ][/color]" \
			% [COL_SLATE, COL_SLATE]
		_footer.text = "[color=%s]time  %d/%d[/color]" % [COL_SLATE, roster_size, roster_capacity]
		return

	var card_path := CARDS_DIR + creature_code + ".png"
	if ResourceLoader.exists(card_path):
		_card.texture = load(card_path)
		_card.show()
	else:
		_card.hide()

	var class_code := str(c.get("class", ""))
	var element_code := str(c.get("element", ""))
	var element_name := str(_db.element(element_code).get("name", element_code))
	var class_label := str(_db.creature_class(class_code).get("name", class_code))

	var lines: Array[String] = []
	var caida := hp >= 0 and hp <= 0
	var name_tag := "  [color=%s]caida[/color]" % COL_EMBER if caida else ""
	lines.append("[color=%s][b]%s[/b][/color]%s" % [COL_BONE, str(c.get("name", creature_code)), name_tag])
	lines.append("[color=%s]Lv %d · %s · %s[/color]" % [COL_SLATE, level, class_label, element_name])

	if hp >= 0 and max_hp > 0:
		var hp_color := COL_EMBER if caida else COL_BONE
		lines.append("[color=%s]HP %d/%d[/color]" % [hp_color, hp, max_hp])

	# A mesma barra da janela do time, sem a frase de material — aqui só o
	# "onde estou"; o "o que falta" é uma tecla `T` de distância. O estado que
	# a próxima vitória sozinha não resolve é o único que ganha acento.
	if not progress.is_empty() and (int(progress.get("xp_to_next", 0)) > 0 or bool(progress.get("at_cap", false))):
		var xp_line := ProgressText.bar(progress) + "  " + ProgressText.xp_label(progress)
		if bool(progress.get("xp_full", false)):
			xp_line += "  [color=%s]pronta pra subir[/color]" % COL_EMBER
		lines.append(xp_line)

	_label.text = "\n".join(lines)

	# O papel de mineração é o motivo do painel existir (ver o topo do arquivo).
	var footer := "[color=%s]time  %d/%d[/color]" % [COL_SLATE, roster_size, roster_capacity]
	var role := MiningTable.role_label(_db, class_code)
	if role != "":
		footer += "   ·   [color=%s]mineracao[/color]  [color=%s]%s ×%.1f[/color]" % [
			COL_SLATE, COL_MOSS, role, MiningTable.speed_modifier(_db, class_code)]
	_footer.text = footer
