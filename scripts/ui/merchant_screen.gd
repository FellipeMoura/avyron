class_name MerchantScreen
extends PanelContainer

## A tela de troca. Overlay sobre o mundo congelado, como o duelo — mesmo
## enquadramento, mesma razão: negociar não é outro lugar, é o mesmo lugar
## com a atenção em outra coisa.
##
## Instrumento de playtest, texto puro, pelo mesmo motivo do duelo: o que
## precisa ser avaliado é a *economia* — se o preço de um consumível corresponde
## a um tempo de mineração que se sente justo —, e para isso a tabela crua é
## melhor do que qualquer vitrine.
##
## Duas listas, uma de cada vez. Mostrar comprar e vender lado a lado caberia
## na tela, mas dobra o significado do número que se digita, e digitar o
## número é a única coisa que se faz aqui.
##
## Teclas: Tab alterna comprar/vender · 1-9 negocia uma unidade · Esc sai

signal closed

const COL_BONE  := "#F2EDE0"
const COL_MOSS  := "#7A8C6B"
const COL_EMBER := "#C6552F"
const COL_SLATE := "#6B7280"

## Quantas linhas a lista mostra. Nove porque as teclas vão de 1 a 9 — uma
## décima linha seria visível e inalcançável.
const MAX_ROWS := 9

var _db: BestiaryData
var _inventory: PlayerInventory
var _merchant: Dictionary = {}
var _selling := false
var _message := ""

var _label: RichTextLabel
## Códigos na ordem desenhada. É o que traduz "tecla 3" para um item, e
## precisa ser reconstruído a cada `_render` — o inventário muda de tamanho a
## cada venda, e um índice velho venderia a coisa errada.
var _rows: Array[String] = []


func setup(db: BestiaryData, inventory: PlayerInventory, merchant_code: String) -> void:
	_db = db
	_inventory = inventory
	_merchant = db.merchant(merchant_code)
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
		_selling = not _selling
		_message = ""
		_render()
	elif key.keycode >= KEY_1 and key.keycode < KEY_1 + MAX_ROWS:
		_trade(key.keycode - KEY_1)
	else:
		return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# negócio
# ---------------------------------------------------------------------------

func _trade(index: int) -> void:
	if index < 0 or index >= _rows.size():
		_message = "Nao ha nada nessa posicao."
		_render()
		return

	var code := _rows[index]
	if _selling:
		_sell(code)
	else:
		_buy(code)
	_render()


func _buy(code: String) -> void:
	var price := _price_of(code)
	if price <= 0:
		_message = "%s nao esta a venda." % _db.item_name(code)
		return
	# Debita antes de creditar, e só credita se o débito passou: `spend`
	# devolve false sem mexer na bolsa, então não existe estado intermediário
	# em que o jogador pagou e não recebeu.
	if not _inventory.spend(price):
		_message = "Faltam %d %s." % [
			price - _inventory.currency, _db.currency_name(price - _inventory.currency)
		]
		return
	_inventory.add(code)
	_message = "Comprou %s por %d." % [_db.item_name(code), price]


func _sell(code: String) -> void:
	var price := _db.sell_price(code)
	if price <= 0:
		_message = "%s nao tem valor de troca." % _db.item_name(code)
		return
	if not _inventory.remove(code):
		_message = "Voce nao tem %s." % _db.item_name(code)
		return
	_inventory.add_currency(price)
	_message = "Vendeu %s por %d." % [_db.item_name(code), price]


## Preço deste comerciante para o item. O bundle já resolveu o override, então
## aqui é só busca — a regra "null cobra o base" mora no export, num lugar só.
func _price_of(code: String) -> int:
	for offer in _merchant.get("offers", []):
		if str(offer.get("itemCode", "")) == code:
			return int(offer.get("price", 0))
	return 0


# ---------------------------------------------------------------------------
# desenho
# ---------------------------------------------------------------------------

func _render() -> void:
	if _label == null or _db == null:
		return

	var lines: Array[String] = []
	var purse := _inventory.currency

	lines.append("[color=%s][b]%s[/b][/color]   [color=%s]%s[/color]" % [
		COL_BONE, str(_merchant.get("name", "Comerciante")),
		COL_SLATE, str(_merchant.get("faction", ""))
	])
	lines.append("[color=%s]bolsa[/color]  [color=%s][b]%d[/b] %s[/color]" % [
		COL_SLATE, COL_EMBER, purse, _db.currency_name(purse)
	])
	lines.append("")

	if _selling:
		lines.append("[color=%s]VENDER[/color]   [color=%s]· comerciante paga %d%% do valor[/color]"
			% [COL_MOSS, COL_SLATE, int(round(_db.sell_ratio() * 100.0))])
		lines.append("")
		lines.append_array(_sell_rows())
	else:
		lines.append("[color=%s]COMPRAR[/color]" % COL_MOSS)
		lines.append("")
		lines.append_array(_buy_rows())

	lines.append("")
	lines.append("[color=%s][Tab] %s   ·   1-%d negocia   ·   [Esc] sai[/color]" % [
		COL_SLATE, "comprar" if _selling else "vender", MAX_ROWS
	])
	if _message != "":
		lines.append("")
		lines.append("[color=%s]%s[/color]" % [COL_EMBER, _message])

	_label.text = "\n".join(lines)


func _buy_rows() -> Array[String]:
	_rows = []
	var out: Array[String] = []
	var offers: Array = _merchant.get("offers", [])
	if offers.is_empty():
		out.append("[color=%s][ nada a venda ][/color]" % COL_SLATE)
		return out

	for offer in offers:
		if _rows.size() >= MAX_ROWS:
			break
		var code := str(offer.get("itemCode", ""))
		var price := int(offer.get("price", 0))
		_rows.append(code)

		# Cinza no que não dá para pagar: a lista continua informando o preço,
		# que é metade da decisão de continuar minerando.
		var affordable := _inventory.can_afford(price)
		var name_color := COL_BONE if affordable else COL_SLATE
		var price_color := COL_MOSS if affordable else COL_SLATE

		out.append("[color=%s][%d][/color] [color=%s]%-20s[/color] [color=%s]%5d[/color]  [color=%s]%s[/color]" % [
			COL_BONE, _rows.size(), name_color, _db.item_name(code),
			price_color, price, COL_SLATE, _effect_label(code),
		])
	return out


func _sell_rows() -> Array[String]:
	_rows = []
	var out: Array[String] = []
	var entries := _inventory.entries()
	if entries.is_empty():
		out.append("[color=%s][ inventario vazio ][/color]" % COL_SLATE)
		return out

	for entry in entries:
		if _rows.size() >= MAX_ROWS:
			break
		var code := str(entry["code"])
		var price := _db.sell_price(code)
		_rows.append(code)
		out.append("[color=%s][%d][/color] [color=%s]%-20s[/color] [color=%s]x%-3d[/color] [color=%s]%5d[/color]" % [
			COL_BONE, _rows.size(), COL_BONE, _db.item_name(code),
			COL_SLATE, int(entry["qty"]), COL_MOSS, price,
		])

	if entries.size() > MAX_ROWS:
		out.append("[color=%s]... e mais %d tipos[/color]" % [COL_SLATE, entries.size() - MAX_ROWS])
	return out


## Resumo curto do que o item faz. Sai dos números, não da prosa: o texto de
## `items.effect` é para o app web, aqui o que importa é a grandeza.
func _effect_label(code: String) -> String:
	var effect := _db.item_effect_code(code)
	var value := _db.item_effect_value(code)
	match effect:
		"capture_bonus":
			return "captura x%.1f" % value
		"heal_percent":
			return "cura %d%%" % int(value)
		"heal_flat":
			return "cura %d HP" % int(value)
		_:
			return ""
