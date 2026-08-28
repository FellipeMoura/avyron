class_name CraftingScreen
extends PanelContainer

## A tela da bancada: fabricar Amplificador e Encantador com o minério da
## bolsa, e escolher qual modelo de cada slot está vestido.
##
## Overlay sobre o mundo congelado, mesmo enquadramento e mesma razão do
## comerciante e do posto do Relicário — fabricar não é outro lugar, é o mesmo
## lugar com a atenção em outra coisa.
##
## ## Uma tecla por linha, e a ação depende do estado
##
## A linha do modelo diz o que a tecla faz agora: **fabricar** o que ainda não
## é seu, **vestir** o que é seu e está fora, **tirar** o que está vestido.
## Um verbo por estado, nunca dois na mesma linha — o gesto rápido nunca é
## ambíguo, que é a mesma razão pela qual a janela de cura ordena do item
## barato para o caro.
##
## ## Nada aqui decide nada
##
## A tela não gasta minério nem registra posse: ela emite `craft_requested` e
## `equip_requested`, e o `WorldRoot` — que tem a bolsa **e** o loadout —
## mede, recusa e aplica. Mesmo contrato de `RosterWindow.item_use_requested`,
## e pela mesma razão: uma peça fabricada sem o minério ter saído da bolsa é
## exatamente o erro que a separação torna impossível.
##
## Especificação: documento `equipamentos` no bestiário.

signal closed
## Fabricar este modelo. O mundo confere a receita contra a bolsa.
signal craft_requested(equipment_code: String)
## Vestir/tirar. `equip = false` é tirar — o slot fica vazio de propósito,
## para o jogador poder lutar sem a peça.
signal equip_requested(equipment_code: String, equip: bool)

const COL_BONE  := "#F2EDE0"
const COL_MOSS  := "#7A8C6B"
const COL_EMBER := "#C6552F"
const COL_SLATE := "#6B7280"

const MAX_ROWS := 9

var _db: BestiaryData
var _inventory: PlayerInventory
var _loadout: PlayerLoadout

## Slot em exibição. Um de cada vez porque as duas listas juntas passariam da
## altura útil da tela com a receita de cada modelo aberta — mesma razão pela
## qual o comerciante não mostra comprar e vender lado a lado.
var _slot := BestiaryData.SLOT_AMPLIFIER
var _message := ""

var _label: RichTextLabel
## Reconstruído a cada `_render`, pelo mesmo motivo de `MerchantScreen._rows`:
## uma tecla nunca pode apontar para uma linha que já não existe.
var _rows: Array[String] = []


func setup(db: BestiaryData, inventory: PlayerInventory, loadout: PlayerLoadout) -> void:
	_db = db
	_inventory = inventory
	_loadout = loadout
	_render()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -350
	offset_right = 350
	offset_top = 0
	offset_bottom = 0
	# `PRESET_CENTER` sozinho só cresce para baixo — mesma correção das outras
	# janelas centrais, pela mesma razão.
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
		_cycle_slot()
	elif key.keycode >= KEY_1 and key.keycode < KEY_1 + MAX_ROWS:
		_choose(key.keycode - KEY_1)
	else:
		return
	get_viewport().set_input_as_handled()


func _cycle_slot() -> void:
	_message = ""
	_slot = BestiaryData.SLOT_ENCHANTER if _slot == BestiaryData.SLOT_AMPLIFIER \
		else BestiaryData.SLOT_AMPLIFIER
	_render()


## Uma tecla, três destinos, decididos pelo estado do modelo — o mesmo que a
## linha mostra ao jogador antes de ele apertar.
func _choose(index: int) -> void:
	if index < 0 or index >= _rows.size():
		_message = "Nao ha nada nessa posicao."
		_render()
		return

	var code := _rows[index]
	if not _loadout.owns(code):
		craft_requested.emit(code)
	elif _loadout.equipped_in(_slot) == code:
		equip_requested.emit(code, false)
	else:
		equip_requested.emit(code, true)
	# Sem `_render()` aqui: quem aplicou responde com `refresh()`, e redesenhar
	# antes disso mostraria o estado velho por um quadro.


## Chamado pelo mundo depois de aplicar (ou recusar) o pedido. `message`
## vazia limpa a linha anterior — recusa sem texto é tecla que não faz nada.
func refresh(message: String = "") -> void:
	_message = message
	_render()


# ---------------------------------------------------------------------------
# desenho
# ---------------------------------------------------------------------------

func _slot_label(slot: String) -> String:
	return "amplificador" if slot == BestiaryData.SLOT_AMPLIFIER else "encantador"


func _render() -> void:
	if _label == null or _db == null:
		return

	var lines: Array[String] = []
	lines.append("[color=%s][b]bancada[/b][/color]" % COL_BONE)
	lines.append("")

	var other := BestiaryData.SLOT_ENCHANTER if _slot == BestiaryData.SLOT_AMPLIFIER \
		else BestiaryData.SLOT_AMPLIFIER
	var worn := _loadout.equipped_in(_slot) if _loadout else ""
	lines.append("[color=%s]%s[/color]   [color=%s]· vestido: %s[/color]" % [
		COL_MOSS, _slot_label(_slot).to_upper(), COL_SLATE,
		_db.equipment_name(worn) if worn != "" else "nada",
	])
	lines.append("")
	lines.append_array(_model_rows())

	lines.append("")
	lines.append("[color=%s][Tab] %s   ·   1-%d age na linha   ·   [Esc] sai[/color]" % [
		COL_SLATE, _slot_label(other), MAX_ROWS,
	])
	if _message != "":
		lines.append("")
		lines.append("[color=%s]%s[/color]" % [COL_EMBER, _message])

	_label.text = "\n".join(lines)


func _model_rows() -> Array[String]:
	_rows = []
	var out: Array[String] = []
	var models := _db.equipment_in_slot(_slot)
	if models.is_empty():
		out.append("[color=%s][ nada fabricavel aqui ][/color]" % COL_SLATE)
		return out

	for model in models:
		if _rows.size() >= MAX_ROWS:
			break
		var code := str(model["code"])
		_rows.append(code)
		out.append_array(_model_lines(_rows.size(), code, model))
		out.append("")
	return out


## Duas linhas por modelo: o cabeçalho com potência e verbo, e a receita com
## `tem/precisa` por ingrediente.
##
## A receita mostra **o que falta**, não só o que custa. É o mesmo raciocínio
## do "restaura 12 (desperdicia 92)" da janela de cura: o número que decide o
## próximo gesto do jogador é a diferença, e obrigá-lo a subtrair de cabeça
## contra o painel da bolsa é onde o erro caro acontece.
func _model_lines(slot_number: int, code: String, model: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var owned := _loadout.owns(code) if _loadout else false
	var worn := (_loadout.equipped_in(_slot) == code) if _loadout else false
	var affordable := _can_afford(code)

	var verb := ""
	var verb_color := COL_SLATE
	if worn:
		verb = "vestido · [%d] tira" % slot_number
		verb_color = COL_MOSS
	elif owned:
		verb = "[%d] veste" % slot_number
		verb_color = COL_BONE
	elif affordable:
		verb = "[%d] fabrica" % slot_number
		verb_color = COL_MOSS
	else:
		verb = "falta material"
		verb_color = COL_EMBER

	out.append("[color=%s]T%d %s[/color]   [color=%s]%s[/color]   [color=%s]%s[/color]" % [
		COL_BONE, int(model.get("tier", 0)), str(model.get("name", code)),
		COL_MOSS, _effect_label(code),
		verb_color, verb,
	])

	# Modelo já do jogador não precisa mais da receita: ela responde "posso
	# fabricar?", e essa pergunta morreu no instante em que ele fabricou.
	if not owned:
		out.append("    [color=%s]%s[/color]" % [COL_SLATE, _recipe_text(code)])
	return out


## `+15%` / `-15%`, com o sinal saindo do código do efeito. O mesmo cuidado de
## `ItemEffects.heal_label`: quem sabe que `debuff_*` é uma redução é o código,
## e escrever o sinal à mão numa tela criaria a segunda fonte que discorda da
## primeira quando um efeito novo aparecer.
func _effect_label(code: String) -> String:
	var effect := _db.equipment_effect_code(code)
	var value := int(_db.equipment_effect_value(code))
	if effect.begins_with("debuff_"):
		return "-%d%% %s do adversario" % [value, _stat_label(effect)]
	return "+%d%% %s" % [value, _stat_label(effect)]


func _stat_label(effect_code: String) -> String:
	return "defesa" if effect_code.ends_with("_defense") else "ataque"


func _recipe_text(code: String) -> String:
	var parts: Array[String] = []
	for line in _db.equipment_recipe(code):
		var item_code := str(line["itemCode"])
		var need := int(line["quantity"])
		var have := _inventory.quantity(item_code) if _inventory else 0
		parts.append("%s %d/%d" % [_db.item_name(item_code), have, need])
	return "  ·  ".join(parts) if not parts.is_empty() else "sem receita"


func _can_afford(code: String) -> bool:
	if _inventory == null:
		return false
	var recipe := _db.equipment_recipe(code)
	if recipe.is_empty():
		return false
	for line in recipe:
		if not _inventory.has(str(line["itemCode"]), int(line["quantity"])):
			return false
	return true
