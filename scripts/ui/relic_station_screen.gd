class_name RelicStationScreen
extends PanelContainer

## O posto do Relicário. Overlay sobre o mundo congelado, mesmo enquadramento
## e razão do comerciante (`MerchantScreen`): gerenciar o time não é outro
## lugar, é o mesmo lugar com a atenção em outra coisa.
##
## Quatro modos, um de cada vez — Tab circula entre eles:
##   INFO      status do relicário equipado (nível, XP, capacidade, taxa)
##   DEPOSIT   manda um ativo pro storage
##   WITHDRAW  traz um guardado de volta pro ativo
##   SWAP      troca de modelo — só habilitado com o time ativo vazio
##            (documento `relicario`: "esvaziar os slots" é obrigatório antes)
##
## Teclas: Tab circula modo · 1-9 escolhe linha · ←/→ (PgUp/PgDn) página · Esc sai
##
## As listas são paginadas em blocos de `MAX_ROWS`: o storage não tem teto, e
## antes da paginação a décima criatura guardada simplesmente não aparecia —
## sem erro, sem aviso, só inacessível até alguém retirar outra.

signal closed
signal relic_swapped(new_relic: PlayerRelic)

const COL_BONE  := "#F2EDE0"
const COL_MOSS  := "#7A8C6B"
const COL_EMBER := "#C6552F"
const COL_SLATE := "#6B7280"

## Linhas por página — o que cabe nas teclas 1-9.
const MAX_ROWS := 9

enum Mode { INFO, DEPOSIT, WITHDRAW, SWAP }

var _db: BestiaryData
var _roster: PlayerRoster
var _relic: PlayerRelic
## Opcional: sem bolsa a linha de material diz "tem 0", que é a verdade de
## uma bancada sem bolsa.
var _inventory: PlayerInventory
var _mode := Mode.INFO
var _message := ""

## Página corrente da lista do modo, e quantas ela tem — `_page_total` é
## escrito por quem monta as linhas (`_paged`), lido pelo rodapé.
var _page := 0
var _page_total := 1

var _label: RichTextLabel
## Mesma razão de `MerchantScreen._rows`: reconstruído a cada `_render`, pra
## uma tecla nunca apontar pra uma linha que já não existe mais.
var _rows: Array[String] = []


func setup(
	db: BestiaryData, roster: PlayerRoster, relic: PlayerRelic, inventory: PlayerInventory = null
) -> void:
	_db = db
	_roster = roster
	_relic = relic
	_inventory = inventory
	_render()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -350
	offset_right = 350
	offset_top = 0
	offset_bottom = 0
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0A0B0D", 0.96)
	style.border_color = Color("#1F2530")
	style.set_border_width_all(1)
	style.set_content_margin_all(18)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 13)
	add_child(_label)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	if key.keycode == KEY_ESCAPE:
		closed.emit()
	elif key.keycode == KEY_TAB:
		_cycle_mode()
	elif key.keycode >= KEY_1 and key.keycode < KEY_1 + MAX_ROWS:
		_choose(key.keycode - KEY_1)
	elif key.keycode == KEY_RIGHT or key.keycode == KEY_PAGEDOWN:
		next_page()
	elif key.keycode == KEY_LEFT or key.keycode == KEY_PAGEUP:
		prev_page()
	else:
		return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# paginação — públicos pelo mesmo motivo de `RosterWindow.choose_row`: teste
# headless não sintetiza tecla.
# ---------------------------------------------------------------------------

func page() -> int:
	return _page


func page_count() -> int:
	return _page_total


func next_page() -> void:
	if _page + 1 >= _page_total:
		return
	_page += 1
	_message = ""
	_render()


func prev_page() -> void:
	if _page <= 0:
		return
	_page -= 1
	_message = ""
	_render()


## Índices da página corrente sobre uma lista de `total` itens. Clampa a
## página antes de recortar: a lista pode ter encolhido desde a última tecla
## (retirar do storage tira uma linha), e uma página que ficou vazia deve
## cair pra anterior em vez de mostrar "[ storage vazio ]" com dez guardadas.
func _paged(total: int) -> Array:
	_page_total = maxi(1, int(ceil(float(total) / float(MAX_ROWS))))
	_page = clampi(_page, 0, _page_total - 1)
	var start := _page * MAX_ROWS
	return range(start, mini(total, start + MAX_ROWS))


func _cycle_mode() -> void:
	_message = ""
	# Cada modo lista outra coisa; a página de uma não diz nada sobre a outra.
	_page = 0
	match _mode:
		Mode.INFO:
			_mode = Mode.DEPOSIT
		Mode.DEPOSIT:
			_mode = Mode.WITHDRAW
		Mode.WITHDRAW:
			_mode = Mode.SWAP
		Mode.SWAP:
			_mode = Mode.INFO
	_render()


func _choose(index: int) -> void:
	if index < 0 or index >= _rows.size():
		_message = "Nao ha nada nessa posicao."
		_render()
		return

	match _mode:
		Mode.DEPOSIT:
			if _roster.deposit(int(_rows[index])):
				_message = "Guardado."
			else:
				_message = "Precisa sobrar pelo menos uma ativa."
		Mode.WITHDRAW:
			if _roster.withdraw(int(_rows[index])):
				_message = "Trouxe de volta."
			else:
				_message = "Time cheio (%d/%d)." % [_roster.size(), _roster.capacity()]
		Mode.SWAP:
			_swap_to(_rows[index])
		_:
			pass
	_render()


## Troca de modelo — só chega aqui com o ativo vazio (`_swap_rows` só lista
## opções quando `_roster.size() == 0`). Novo `PlayerRelic` do zero: nível e
## XP não atravessam a troca, é um relicário diferente, não o mesmo mais forte.
func _swap_to(relic_code: String) -> void:
	var new_relic := PlayerRelic.from_bestiary(_db, relic_code)
	if new_relic == null:
		_message = "Modelo invalido."
		return
	_relic = new_relic
	_roster.set_capacity(_relic.slot_capacity(_db))
	relic_swapped.emit(_relic)
	_message = "Equipado: %s." % _relic.display_name(_db)


# ---------------------------------------------------------------------------
# desenho
# ---------------------------------------------------------------------------

func _render() -> void:
	if _label == null or _db == null:
		return

	var lines: Array[String] = []
	lines.append("[color=%s][b]posto do relicario[/b][/color]" % COL_BONE)
	lines.append("")

	# INFO não tem lista; quem tem sobrescreve em `_paged`.
	_page_total = 1

	if _relic == null:
		lines.append("[color=%s]nenhum relicario equipado[/color]" % COL_SLATE)
	else:
		lines.append_array(_info_lines())

	lines.append("")
	match _mode:
		Mode.INFO:
			pass
		Mode.DEPOSIT:
			lines.append("[color=%s]DEPOSITAR[/color]   [color=%s]· manda pro storage[/color]"
				% [COL_MOSS, COL_SLATE])
			lines.append("")
			lines.append_array(_deposit_rows())
		Mode.WITHDRAW:
			lines.append("[color=%s]RETIRAR[/color]   [color=%s]· traz do storage[/color]"
				% [COL_MOSS, COL_SLATE])
			lines.append("")
			lines.append_array(_withdraw_rows())
		Mode.SWAP:
			lines.append("[color=%s]TROCAR MODELO[/color]" % COL_MOSS)
			lines.append("")
			lines.append_array(_swap_rows())

	lines.append("")
	var paging := ""
	if _page_total > 1:
		paging = "   ·   pag %d/%d  ←/→" % [_page + 1, _page_total]
	lines.append("[color=%s][Tab] modo   ·   1-%d escolhe%s   ·   [Esc] sai[/color]"
		% [COL_SLATE, MAX_ROWS, paging])
	if _message != "":
		lines.append("")
		lines.append("[color=%s]%s[/color]" % [COL_EMBER, _message])

	_label.text = "\n".join(lines)


func _info_lines() -> Array[String]:
	var out: Array[String] = []
	var cap := _relic.max_level(_db)
	out.append("[color=%s]%s[/color]   [color=%s]nivel %d%s[/color]" % [
		COL_BONE, _relic.display_name(_db), COL_MOSS, _relic.level,
		("/%d" % cap) if cap > 0 else "",
	])
	var to_next := _relic.xp_to_next(_db)
	out.append("[color=%s]xp[/color]  %d/%d" % [COL_SLATE, _relic.xp, to_next])
	out.append("[color=%s]slots[/color]  %d   [color=%s]taxa de captura[/color]  %.0f" % [
		COL_SLATE, _relic.slot_capacity(_db),
		COL_SLATE, _relic.capture_rate(_db),
	])
	# A mesma frase da janela do set — o starter neutro diz "sem classe: nao
	# sobe de nivel" em vez de exibir uma barra cheia sem saída.
	var progress := _relic.progress(_db)
	out.append("%s   %s" % [
		ProgressText.bar(progress), ProgressText.status_line(_db, progress, _inventory, "captura")])
	out.append("[color=%s]time[/color]  %d/%d   [color=%s]storage[/color]  %d" % [
		COL_SLATE, _roster.size(), _roster.capacity(), COL_SLATE, _roster.storage_size(),
	])
	return out


func _deposit_rows() -> Array[String]:
	_rows = []
	var out: Array[String] = []
	if _roster.size() <= 1:
		out.append("[color=%s][ precisa sobrar uma ativa ][/color]" % COL_SLATE)
		return out
	var codes := _roster.codes()
	for i in _paged(codes.size()):
		_rows.append(str(i))  # índice do ativo, não um código — ver _choose
		var marker := "  (ativa)" if i == _roster.active_index() else ""
		out.append("[color=%s][%d][/color] %s%s" % [
			COL_BONE, _rows.size(),
			_member_line(codes[i], _roster.level_at(i), _roster.hp_at(i), _roster.max_hp_at(i),
				_roster.progress_at(i)),
			marker,
		])
	return out


func _withdraw_rows() -> Array[String]:
	_rows = []
	var out: Array[String] = []
	var codes := _roster.storage_entries()
	if codes.is_empty():
		out.append("[color=%s][ storage vazio ][/color]" % COL_SLATE)
		return out
	for i in _paged(codes.size()):
		_rows.append(str(i))
		out.append("[color=%s][%d][/color] %s" % [
			COL_BONE, _rows.size(),
			_member_line(codes[i], _roster.storage_level_at(i), _roster.storage_hp_at(i),
				_roster.storage_max_hp_at(i), _roster.storage_progress_at(i)),
		])
	return out


## Uma criatura numa linha, igual nos dois sentidos: quem deposita e quem
## retira decide pelas mesmas três coisas — nível, HP e se está pronta pra
## subir. Antes DEPOSITAR mostrava só o nome e RETIRAR só o HP, e o jogador
## tinha de retirar pra descobrir o nível de quem estava guardada.
func _member_line(code: String, level: int, hp: int, max_hp: int, progress: Dictionary) -> String:
	var hp_color := COL_EMBER if hp <= 0 else COL_BONE
	var line := "%-20s [color=%s]Lv %d[/color]   [color=%s]HP %d/%d[/color]   %s" % [
		_creature_name(code), COL_SLATE, level, hp_color, hp, max_hp,
		ProgressText.xp_label(progress),
	]
	if bool(progress.get("xp_full", false)):
		line += "   [color=%s]pronta pra subir[/color]" % COL_EMBER
	return line


func _swap_rows() -> Array[String]:
	_rows = []
	var out: Array[String] = []
	if _roster.size() > 0:
		out.append("[color=%s][ esvazie os slots ativos primeiro ][/color]" % COL_SLATE)
		return out
	var codes := _db.relic_codes()
	for i in _paged(codes.size()):
		var code: String = str(codes[i])
		_rows.append(code)
		var r := _db.relic(code)
		out.append("[color=%s][%d][/color] %-28s [color=%s]%s · %s[/color]" % [
			COL_BONE, _rows.size(), str(r.get("name", code)),
			COL_SLATE, _element_name(BestiaryData.relic_element_code(r)), _class_name(BestiaryData.relic_class_code(r)),
		])
	return out


func _creature_name(code: String) -> String:
	var c := _db.creature(code)
	return str(c.get("name", code))


func _element_name(code: String) -> String:
	if code == "":
		return "—"
	var e := _db.element(code)
	return str(e.get("name", code))


func _class_name(code: String) -> String:
	if code == "":
		return "—"
	var c := _db.creature_class(code)
	return str(c.get("name", code))
