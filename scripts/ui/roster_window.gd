class_name RosterWindow
extends PanelContainer

## A janela do time (tecla `T`): ativa, reservas, status de cada uma, a troca
## de quem vai à frente, e o uso de item de cura (tecla `I`).
##
## É a única peça de HUD do mapa que aceita clique. Todo o resto usa
## `MOUSE_FILTER_IGNORE` para não roubar o clique de seleção de criatura; aqui
## o clique **é** a função, então a janela para o evento — e o `WorldRoot`
## ignora clique de mundo enquanto ela está aberta, senão selecionar uma
## criatura por trás da janela seria acidente garantido.
##
## Não pausa o jogo. Trocar quem vai à frente é decisão de exploração, e
## congelar o mapa para isso transformaria um gesto rápido num menu.
##
## ## Os três modos
##
## Curar precisa de duas escolhas — em quem e com o quê — e a janela já é a
## lista de criaturas com o HP de cada uma, então a ordem natural é apontar o
## ferido primeiro e escolher o remédio depois:
##
##     LIST  ──I──▶  PICK_TARGET  ──criatura──▶  PICK_ITEM
##       ◀────Esc─────────┘  ◀───────Esc / item usado──┘
##
## O modo muda o que a linha significa, e por isso o rodapé é reescrito em
## cada um: uma lista que faz coisas diferentes com o mesmo clique sem dizer
## qual é o caso é a receita do clique errado. É o mesmo desenho do menu de
## resinas do duelo (`_capture_mode` em `DuelScreen`) — dois lugares com o
## mesmo problema resolvido do mesmo jeito.

signal activate_requested(index: int)

## Pedido de uso de item. A janela não cura nem consome nada: quem tem a bolsa
## e o time é o `WorldRoot`, e deixar a UI mexer nos dois abriria o caminho
## para uma cura aplicada sem o item sair do inventário.
signal item_use_requested(index: int, item_code: String)

const COL_BONE  := "#F2EDE0"
const COL_MOSS  := "#7A8C6B"
const COL_SLATE := "#6B7280"
const COL_EMBER := "#C6552F"

## Linha ocupada tem duas: identificação em cima, status embaixo. Slot vazio
## tem uma só, e dar a mesma altura aos dois abria um vão de ar entre as
## reservas e o rodapé maior que a própria lista.
const ROW_HEIGHT := 46
const ROW_HEIGHT_EMPTY := 24

enum Mode { LIST, PICK_TARGET, PICK_ITEM }

var _db: BestiaryData
var _inventory: PlayerInventory
var _rows: VBoxContainer
var _title: RichTextLabel
var _footer: RichTextLabel

var _mode := Mode.LIST
## Em quem o item vai ser usado, escolhido no `PICK_TARGET`. -1 fora dele.
var _target := -1
## Códigos dos itens na ordem desenhada, para a tecla numérica achar o mesmo
## que o clique.
var _item_rows: Array[String] = []

## Último time desenhado. Guardado porque a troca de modo redesenha sozinha,
## sem o `WorldRoot` no meio — e pedir o time de volta a cada mudança de modo
## faria a janela depender de quem a abriu para trocar de tela.
var _roster: PlayerRoster
var _level := 1


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

	_footer = _make_label(12)
	column.add_child(_footer)

	hide()


## `inventory` é opcional: em playtest solto não há bolsa, e sem ela a janela
## simplesmente não oferece cura em vez de quebrar.
func setup(db: BestiaryData, inventory: PlayerInventory = null) -> void:
	_db = db
	_inventory = inventory


func is_open() -> bool:
	return visible


func toggle() -> void:
	visible = not visible
	if not visible:
		_reset_mode()


func close() -> void:
	# O modo cai junto com a janela: reabrir no meio de uma escolha de item,
	# com um alvo que pode nem estar mais ferido, é estado velho disfarçado de
	# continuidade.
	_reset_mode()
	hide()


func _reset_mode() -> void:
	_mode = Mode.LIST
	_target = -1
	_item_rows.clear()


func mode() -> Mode:
	return _mode


# ---------------------------------------------------------------------------
# navegação
# ---------------------------------------------------------------------------

## Entra no modo de uso de item. Devolve `false` — sem entrar em modo nenhum —
## quando não há cura na bolsa: abrir uma lista vazia diria menos que a
## mensagem que o `WorldRoot` mostra no lugar.
func open_item_mode() -> bool:
	if _roster == null or _held_heal_items().is_empty():
		return false
	_mode = Mode.PICK_TARGET
	_target = -1
	_render()
	return true


## Volta um passo. Devolve `false` quando já estava na lista normal, e aí quem
## chamou é que decide o que fazer com o `Esc` — no `WorldRoot`, fechar.
func back() -> bool:
	match _mode:
		Mode.PICK_ITEM:
			_mode = Mode.PICK_TARGET
			_target = -1
			_render()
			return true
		Mode.PICK_TARGET:
			_reset_mode()
			_render()
			return true
		_:
			return false


## Escolha por índice, a mesma para clique e para tecla numérica. Ter um ponto
## só evita a classe de bug em que o número faz uma coisa e o clique outra
## depois de um modo novo aparecer.
func choose_row(index: int) -> void:
	if _roster == null:
		return

	match _mode:
		Mode.LIST:
			if index >= 0 and index < _roster.size() and index != _roster.active_index():
				activate_requested.emit(index)

		Mode.PICK_TARGET:
			# Criatura cheia não é alvo: o item seria consumido curando zero.
			if index < 0 or index >= _roster.size() or _roster.missing_hp_at(index) <= 0:
				return
			_target = index
			_mode = Mode.PICK_ITEM
			_render()

		Mode.PICK_ITEM:
			if index < 0 or index >= _item_rows.size():
				return
			var code := _item_rows[index]
			var target := _target
			# O modo volta **antes** do `emit` de propósito: o sinal é síncrono,
			# o mundo cura e redesenha a janela dentro dele, e se o modo ainda
			# fosse `PICK_ITEM` nessa hora a lista se redesenharia com um alvo
			# que acabou de mudar de HP.
			_mode = Mode.PICK_TARGET
			_target = -1
			item_use_requested.emit(target, code)
			# Redesenha também quando o uso não mudou nada (item recusado): sem
			# isto a janela ficaria na tela de itens de um alvo já esquecido.
			_render()


func _on_row_pressed(index: int) -> void:
	choose_row(index)


# ---------------------------------------------------------------------------
# desenho
# ---------------------------------------------------------------------------

## Redesenha a lista inteira. Reconstruir em vez de atualizar linha a linha é
## barato para seis slots e elimina toda a classe de bug em que a linha ativa
## e o índice real saem de sincronia.
##
## Recebe o time inteiro, não uma lista de códigos: o HP corrente de cada
## membro vive nele, e passar códigos e HP em arrays paralelos seria criar
## duas fontes que podem discordar.
func refresh(roster: PlayerRoster, level: int) -> void:
	if roster == null:
		return
	_roster = roster
	_level = level
	_render()


func _render() -> void:
	if _rows == null or _roster == null:
		return

	# A bolsa pode ter esvaziado desde que o modo abriu — a última resina gasta
	# na tela anterior, por exemplo. Cair para a lista normal é mais honesto
	# que oferecer uma lista de zero linhas.
	if _mode != Mode.LIST and _held_heal_items().is_empty():
		_reset_mode()

	for child in _rows.get_children():
		child.queue_free()

	match _mode:
		Mode.PICK_ITEM:
			_render_items()
		_:
			_render_team()


func _render_team() -> void:
	var picking := _mode == Mode.PICK_TARGET
	var active_index := _roster.active_index()

	if picking:
		_title.text = "[color=%s]usar item[/color]   [color=%s]em quem?[/color]" \
			% [COL_BONE, COL_SLATE]
	else:
		_title.text = "[color=%s]time[/color]   [color=%s]%d/%d[/color]" \
			% [COL_BONE, COL_SLATE, _roster.size(), PlayerRoster.MAX_SLOTS]

	for i in PlayerRoster.MAX_SLOTS:
		var occupied := i < _roster.size()
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT if occupied else ROW_HEIGHT_EMPTY)
		row.flat = true
		if picking:
			# No modo de cura só linha ferida responde. Slot vazio e criatura
			# cheia não têm o que curar, e deixá-las clicáveis gastaria o item.
			row.disabled = not occupied or _roster.missing_hp_at(i) <= 0
		else:
			# Slot vazio e slot ativo não têm ação: um não tem quem mandar à
			# frente, o outro já está lá. Caída **não** entra nessa lista: no
			# mapa ela é só uma criatura muito ferida, e escolher andar com ela
			# é decisão legítima — quem barra desmaiada é o combate.
			row.disabled = not occupied or i == active_index
		row.focus_mode = Control.FOCUS_NONE
		if not row.disabled:
			row.pressed.connect(_on_row_pressed.bind(i))

		var text := _make_label(13)
		text.set_anchors_preset(Control.PRESET_FULL_RECT)
		text.offset_left = 10
		text.offset_right = -10
		text.offset_top = 4
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.text = _row_text(i, picking)
		row.add_child(text)

		_rows.add_child(row)

	if picking:
		_footer.text = "[color=%s]clique ou 1–%d escolhe   ·   Esc volta[/color]" \
			% [COL_SLATE, PlayerRoster.MAX_SLOTS]
	else:
		var heal_hint := ""
		if not _held_heal_items().is_empty():
			heal_hint = "   ·   I usa item"
		_footer.text = "[color=%s]clique ou 1–%d manda à frente%s   ·   T / Esc fecha[/color]" \
			% [COL_SLATE, PlayerRoster.MAX_SLOTS, heal_hint]


func _render_items() -> void:
	_item_rows = _held_heal_items()
	var name_of := _creature_name(_roster.code_at(_target))
	var missing := _roster.missing_hp_at(_target)

	_title.text = "[color=%s]usar em[/color]   [color=%s][b]%s[/b][/color]   [color=%s]faltam %d HP[/color]" \
		% [COL_SLATE, COL_BONE, name_of, COL_EMBER, missing]

	for i in _item_rows.size():
		var code := _item_rows[i]
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT_EMPTY + 6)
		row.flat = true
		row.focus_mode = Control.FOCUS_NONE
		row.pressed.connect(_on_row_pressed.bind(i))

		var text := _make_label(13)
		text.set_anchors_preset(Control.PRESET_FULL_RECT)
		text.offset_left = 10
		text.offset_right = -10
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.text = _item_row_text(i, code, missing)
		row.add_child(text)

		_rows.add_child(row)

	_footer.text = "[color=%s]clique ou 1–%d usa   ·   Esc volta[/color]" \
		% [COL_SLATE, _item_rows.size()]


## Uma linha de item: nome, potência nominal, o que **de fato** vai entrar
## neste alvo, e quantos restam.
##
## Mostrar o efetivo ao lado do nominal é o ponto: `+100%` numa criatura a que
## faltam 12 HP restaura 12, e sem esse número o jogador queima a Seiva
## Primordial de 600 óbolos num arranhão.
func _item_row_text(slot: int, code: String, missing: int) -> String:
	var number := "[color=%s]%d[/color]" % [COL_SLATE, slot + 1]
	var effect := _db.item_effect_code(code) if _db else ""
	var value := _db.item_effect_value(code) if _db else 0.0
	var top := _roster.max_hp_at(_target)
	var effective := mini(ItemEffects.heal_amount(effect, value, top), missing)
	var qty := _inventory.quantity(code) if _inventory else 0
	var nominal := ItemEffects.heal_label(effect, value)

	# Desperdício em ember: é a informação que muda a escolha, e o resto da
	# linha é contexto. Um único uso do acento por linha, como manda a direção.
	var waste := ItemEffects.heal_amount(effect, value, top) - effective
	var effective_text := "[color=%s]restaura %d[/color]" % [COL_MOSS, effective]
	if waste > 0:
		effective_text += " [color=%s](desperdicia %d)[/color]" % [COL_EMBER, waste]

	return "%s  [color=%s]%s[/color]   [color=%s]%s[/color]   %s   [color=%s]x%d[/color]" \
		% [number, COL_BONE, _item_name(code), COL_SLATE, nominal,
		   effective_text, COL_SLATE, qty]


func _row_text(slot: int, picking: bool) -> String:
	var number := "[color=%s]%d[/color]" % [COL_SLATE, slot + 1]
	var code := _roster.code_at(slot)

	if code == "":
		return "%s  [color=%s][ vazio ][/color]" % [number, COL_SLATE]

	var c := _db.creature(code) if _db else {}
	if c.is_empty():
		return "%s  [color=%s]%s[/color]" % [number, COL_SLATE, code]

	var is_active := slot == _roster.active_index()
	var class_code := str(c.get("class", ""))
	var element_code := str(c.get("element", ""))
	var element_name := str(_db.element(element_code).get("name", element_code))
	var class_label := str(_db.creature_class(class_code).get("name", class_code))

	var marker := "[color=%s]●[/color] " % COL_EMBER if is_active else "  "
	var head := "%s %s[color=%s][b]%s[/b][/color]   [color=%s]Lv %d · %s · %s[/color]" \
		% [number, marker, COL_BONE, str(c.get("name", code)), COL_SLATE,
		   _level, class_label, element_name]

	# HP corrente na frente dos stats: com dano que persiste, "quanto sobrou" é
	# a leitura que decide a troca, e stat base é contexto.
	var hp := _roster.hp_at(slot)
	var top := _roster.max_hp_at(slot)
	var hp_color := COL_EMBER if hp <= 0 else COL_BONE
	var detail := "[color=%s]HP %d/%d[/color]" % [hp_color, hp, top]
	if hp <= 0:
		detail += "  [color=%s]caida[/color]" % COL_EMBER

	# No modo de cura a linha responde outra pergunta — "dá para curar?" — e o
	# perfil de mineração vira ruído. Dizer por que a linha está apagada é o
	# que impede o jogador de achar que a janela travou.
	if picking:
		if hp >= top:
			detail += "   [color=%s]sem ferimento[/color]" % COL_SLATE
		else:
			detail += "   [color=%s]faltam %d[/color]" % [COL_MOSS, top - hp]
		return head + "\n" + detail

	var stats := _db.stats_at_level(code, _level) if _db else {}
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


# ---------------------------------------------------------------------------
# itens
# ---------------------------------------------------------------------------

## Curas em mãos, da mais fraca para a mais forte — a mesma ordenação do menu
## de resinas do duelo, e pela mesma razão: a tecla `1` cai sempre no item
## barato, então o gesto rápido nunca é o caro.
##
## Filtra por `effectCode`, não por categoria: a categoria é como o bestiário
## organiza a vitrine, o efeito é o que o jogo executa. Um item de outra
## categoria que cure entra aqui sem esta lista saber que ele existe.
func _held_heal_items() -> Array[String]:
	var out: Array[String] = []
	if _inventory == null or _db == null:
		return out
	for entry in _inventory.entries():
		var code := str(entry["code"])
		if ItemEffects.is_heal(_db.item_effect_code(code)):
			out.append(code)
	out.sort_custom(func(a: String, b: String) -> bool:
		return _db.item_effect_value(a) < _db.item_effect_value(b))
	return out


## Público para o `WorldRoot` decidir a mensagem antes de tentar abrir o modo.
func has_heal_items() -> bool:
	return not _held_heal_items().is_empty()


func _item_name(code: String) -> String:
	return _db.item_name(code) if _db else code


func _creature_name(code: String) -> String:
	if _db == null or code == "":
		return code
	return str(_db.creature(code).get("name", code))


func _make_label(font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", font_size)
	return label
