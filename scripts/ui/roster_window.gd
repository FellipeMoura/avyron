class_name RosterWindow
extends PanelContainer

## A janela do time (tecla `T`): ativa, reservas, status de cada uma, e a
## troca de quem vai à frente.
##
## É a única peça de HUD do mapa que aceita clique. Todo o resto usa
## `MOUSE_FILTER_IGNORE` para não roubar o clique de seleção de criatura; aqui
## o clique **é** a função, então a janela para o evento — e o `WorldRoot`
## ignora clique de mundo enquanto ela está aberta, senão selecionar uma
## criatura por trás da janela seria acidente garantido.
##
## Não pausa o jogo. Trocar quem vai à frente é decisão de exploração, e
## congelar o mapa para isso transformaria um gesto rápido num menu.

signal activate_requested(index: int)

const COL_BONE  := "#F2EDE0"
const COL_MOSS  := "#7A8C6B"
const COL_SLATE := "#6B7280"
const COL_EMBER := "#C6552F"

## Linha ocupada tem duas: identificação em cima, status embaixo. Slot vazio
## tem uma só, e dar a mesma altura aos dois abria um vão de ar entre as
## reservas e o rodapé maior que a própria lista.
const ROW_HEIGHT := 46
const ROW_HEIGHT_EMPTY := 24

var _db: BestiaryData
var _rows: VBoxContainer
var _title: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left   = -330
	offset_right  = 330
	# Ancorada no centro, cresce para os dois lados até o conteúdo — a janela
	# fica do tamanho do time, não de um retângulo escolhido no chute.
	offset_top    = 0
	offset_bottom = 0
	# `PRESET_CENTER` sozinho cresce só para baixo, e a janela nascia com o
	# topo no meio da tela em vez de centrada nela.
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0A0B0D", 0.96)
	style.border_color = Color("#1F2530")
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	_title = _make_label(14)
	column.add_child(_title)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	column.add_child(_rows)

	var footer := _make_label(12)
	footer.text = "[color=%s]clique ou 1–%d manda à frente   ·   T / Esc fecha[/color]" \
		% [COL_SLATE, PlayerRoster.MAX_SLOTS]
	column.add_child(footer)

	hide()


func setup(db: BestiaryData) -> void:
	_db = db


func is_open() -> bool:
	return visible


func toggle() -> void:
	visible = not visible


func close() -> void:
	hide()


## Redesenha a lista inteira. Reconstruir em vez de atualizar linha a linha é
## barato para seis slots e elimina toda a classe de bug em que a linha ativa
## e o índice real saem de sincronia.
##
## Recebe o time inteiro, não uma lista de códigos: o HP corrente de cada
## membro vive nele, e passar códigos e HP em arrays paralelos seria criar
## duas fontes que podem discordar.
func refresh(roster: PlayerRoster, level: int) -> void:
	if _rows == null or roster == null:
		return

	var active_index := roster.active_index()
	_title.text = "[color=%s]time[/color]   [color=%s]%d/%d[/color]" \
		% [COL_BONE, COL_SLATE, roster.size(), PlayerRoster.MAX_SLOTS]

	for child in _rows.get_children():
		child.queue_free()

	for i in PlayerRoster.MAX_SLOTS:
		var occupied := i < roster.size()
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT if occupied else ROW_HEIGHT_EMPTY)
		row.flat = true
		# Slot vazio e slot ativo não têm ação: um não tem quem mandar à
		# frente, o outro já está lá. Caída **não** entra nessa lista: no mapa
		# ela é só uma criatura muito ferida, e escolher andar com ela é
		# decisão legítima — quem barra desmaiada é o combate.
		row.disabled = not occupied or i == active_index
		row.focus_mode = Control.FOCUS_NONE
		if occupied and i != active_index:
			row.pressed.connect(_on_row_pressed.bind(i))

		var text := _make_label(13)
		text.set_anchors_preset(Control.PRESET_FULL_RECT)
		text.offset_left = 10
		text.offset_right = -10
		text.offset_top = 4
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.text = _row_text(i, roster, level)
		row.add_child(text)

		_rows.add_child(row)


func _on_row_pressed(index: int) -> void:
	activate_requested.emit(index)


func _row_text(slot: int, roster: PlayerRoster, level: int) -> String:
	var number := "[color=%s]%d[/color]" % [COL_SLATE, slot + 1]
	var code := roster.code_at(slot)

	if code == "":
		return "%s  [color=%s][ vazio ][/color]" % [number, COL_SLATE]

	var c := _db.creature(code) if _db else {}
	if c.is_empty():
		return "%s  [color=%s]%s[/color]" % [number, COL_SLATE, code]

	var is_active := slot == roster.active_index()
	var class_code := str(c.get("class", ""))
	var element_code := str(c.get("element", ""))
	var element_name := str(_db.element(element_code).get("name", element_code))
	var class_label := str(_db.creature_class(class_code).get("name", class_code))

	var marker := "[color=%s]●[/color] " % COL_EMBER if is_active else "  "
	var head := "%s %s[color=%s][b]%s[/b][/color]   [color=%s]Lv %d · %s · %s[/color]" \
		% [number, marker, COL_BONE, str(c.get("name", code)), COL_SLATE,
		   level, class_label, element_name]

	# HP corrente na frente dos stats: com dano que persiste, "quanto sobrou" é
	# a leitura que decide a troca, e stat base é contexto.
	var hp := roster.hp_at(slot)
	var top := roster.max_hp_at(slot)
	var hp_color := COL_EMBER if hp <= 0 else COL_BONE
	var detail := "[color=%s]HP %d/%d[/color]" % [hp_color, hp, top]
	if hp <= 0:
		detail += "  [color=%s]caida[/color]" % COL_EMBER

	var stats := _db.stats_at_level(code, level) if _db else {}
	if not stats.is_empty():
		detail += "  [color=%s]· ATQ %d · DEF %d · VEL %d[/color]" \
			% [COL_SLATE, int(stats["attack"]), int(stats["defense"]), int(stats["speed"])]

	# O papel de mineração aparece na linha de cada criatura porque é metade da
	# razão para trocar a ativa fora de combate — sem ele, a janela sugeriria
	# que a escolha é só sobre quem luta melhor.
	var role := MiningTable.role_label(_db, class_code)
	if role != "":
		var separator := "   ·   " if detail != "" else ""
		detail += "%s[color=%s]%s ×%.1f[/color]" \
			% [separator, COL_MOSS, role, MiningTable.speed_modifier(_db, class_code)]

	return head + "\n" + detail


func _make_label(font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", font_size)
	return label
