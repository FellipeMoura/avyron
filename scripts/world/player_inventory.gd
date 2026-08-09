class_name PlayerInventory
extends RefCounted

## O que o jogador carrega: itens por código, e a bolsa.
##
## Os códigos são os do bestiário — minerais e consumíveis chegam como
## `ITM-001`. Nada aqui sabe o que um código significa: nome, preço e efeito
## são consulta ao bundle na hora de desenhar ou de usar. É o que deixa item
## novo entrar pelo bestiário sem tocar nesta classe.
##
## A moeda mora aqui, e não numa classe separada, porque é a mesma pergunta —
## "o que o jogador tem" — e porque toda operação do comerciante move os dois
## lados de uma vez. Um sinal só evita a HUD ficar meio atualizada.

signal changed

var _items: Dictionary = {}   # code -> int
var currency := 0


func add(code: String, qty: int = 1) -> void:
	if code == "" or qty <= 0:
		return
	_items[code] = _items.get(code, 0) + qty
	changed.emit()


## Tira do inventário. Devolve `false` sem mexer em nada se não houver
## quantidade suficiente — venda e uso de item dependem desse "tudo ou nada"
## para não deixar o jogador pagando por algo que não saiu.
func remove(code: String, qty: int = 1) -> bool:
	if code == "" or qty <= 0 or quantity(code) < qty:
		return false
	var left: int = int(_items[code]) - qty
	if left > 0:
		_items[code] = left
	else:
		_items.erase(code)
	changed.emit()
	return true


func quantity(code: String) -> int:
	return _items.get(code, 0)


func has(code: String, qty: int = 1) -> bool:
	return quantity(code) >= qty


func total_items() -> int:
	var n := 0
	for qty in _items.values():
		n += int(qty)
	return n


## Array de {code, qty} ordenado por código, sem zeros.
func entries() -> Array:
	var out: Array = []
	for code in _items.keys():
		var qty: int = _items[code]
		if qty > 0:
			out.append({"code": code, "qty": qty})
	out.sort_custom(func(a, b): return str(a["code"]) < str(b["code"]))
	return out


# ---------------------------------------------------------------------------
# bolsa
# ---------------------------------------------------------------------------

func add_currency(amount: int) -> void:
	if amount <= 0:
		return
	currency += amount
	changed.emit()


## Gasta, se der. Como o `remove`, é tudo ou nada: um débito parcial deixaria
## o jogador mais pobre sem receber a compra.
func spend(amount: int) -> bool:
	if amount < 0 or currency < amount:
		return false
	currency -= amount
	changed.emit()
	return true


func can_afford(amount: int) -> bool:
	return currency >= amount
