class_name RelicStationScreen
extends PanelContainer

## O posto do Relicário. Overlay sobre o mundo congelado, mesmo enquadramento
## e razão do comerciante (`MerchantScreen`): gerenciar o time não é outro
## lugar, é o mesmo lugar com a atenção em outra coisa.
##
## Quatro modos, um de cada vez — Tab circula entre eles:
##   INFO      status do relicário equipado (nível, XP, capacidade, taxa, buff)
##   DEPOSIT   manda um ativo pro storage
##   WITHDRAW  traz um guardado de volta pro ativo
##   SWAP      troca de modelo — só habilitado com o time ativo vazio
##            (documento `relicario`: "esvaziar os slots" é obrigatório antes)
##
## Teclas: Tab circula modo · 1-9 escolhe linha · Esc sai

signal closed
signal relic_swapped(new_relic: PlayerRelic)

const COL_BONE  := "#F2EDE0"
const COL_MOSS  := "#7A8C6B"
const COL_EMBER := "#C6552F"
const COL_SLATE := "#6B7280"

const MAX_ROWS := 9

enum Mode { INFO, DEPOSIT, WITHDRAW, SWAP }

var _db: BestiaryData
var _roster: PlayerRoster
var _relic: PlayerRelic
var _mode := Mode.INFO
var _message := ""

var _label: RichTextLabel
## Mesma razão de `MerchantScreen._rows`: reconstruído a cada `_render`, pra
## uma tecla nunca apontar pra uma linha que já não existe mais.
var _rows: Array[String] = []


func setup(db: BestiaryData, roster: PlayerRoster, relic: PlayerRelic) -> void:
	_db = db
	_roster = roster
	_relic = relic
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
	else:
		return
	get_viewport().set_input_as_handled()


func _cycle_mode() -> void:
	_message = ""
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
	lines.append("[color=%s][Tab] modo   ·   1-%d escolhe   ·   [Esc] sai[/color]" % [COL_SLATE, MAX_ROWS])
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
	out.append("[color=%s]slots[/color]  %d   [color=%s]taxa de captura[/color]  %.0f   [color=%s]buff[/color]  %.1f" % [
		COL_SLATE, _relic.slot_capacity(_db),
		COL_SLATE, _relic.capture_rate(_db),
		COL_SLATE, _relic.combat_buff(_db),
	])
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
	for i in codes.size():
		if _rows.size() >= MAX_ROWS:
			break
		_rows.append(str(i))  # índice do ativo, não um código — ver _choose
		var marker := " (ativa)" if i == _roster.active_index() else ""
		out.append("[color=%s][%d][/color] %-20s%s" % [
			COL_BONE, _rows.size(), _creature_name(codes[i]), marker,
		])
	return out


func _withdraw_rows() -> Array[String]:
	_rows = []
	var out: Array[String] = []
	var codes := _roster.storage_entries()
	if codes.is_empty():
		out.append("[color=%s][ storage vazio ][/color]" % COL_SLATE)
		return out
	for i in codes.size():
		if _rows.size() >= MAX_ROWS:
			break
		_rows.append(str(i))
		out.append("[color=%s][%d][/color] %-20s [color=%s]%d/%d[/color]" % [
			COL_BONE, _rows.size(), _creature_name(codes[i]),
			COL_MOSS, _roster.storage_hp_at(i), _roster.storage_max_hp_at(i),
		])
	return out


func _swap_rows() -> Array[String]:
	_rows = []
	var out: Array[String] = []
	if _roster.size() > 0:
		out.append("[color=%s][ esvazie os slots ativos primeiro ][/color]" % COL_SLATE)
		return out
	for code in _db.relic_codes():
		if _rows.size() >= MAX_ROWS:
			break
		_rows.append(str(code))
		var r := _db.relic(code)
		out.append("[color=%s][%d][/color] %-28s [color=%s]%s · %s[/color]" % [
			COL_BONE, _rows.size(), str(r.get("name", code)),
			COL_SLATE, _element_name(str(r.get("element", ""))), _class_name(str(r.get("class", ""))),
		])
	return out


func _creature_name(code: String) -> String:
	var c := _db.creature(code)
	return str(c.get("name", code))


func _element_name(code: String) -> String:
	var e := _db.element(code)
	return str(e.get("name", code))


func _class_name(code: String) -> String:
	var c := _db.creature_class(code)
	return str(c.get("name", code))
