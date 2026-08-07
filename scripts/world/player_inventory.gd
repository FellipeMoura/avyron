class_name PlayerInventory
extends RefCounted

## Inventário do jogador: quantidades de cada item por código.
##
## Minérios usam "ORE-001" etc.; futuros itens de loja ou construção entram
## com seus próprios prefixos sem precisar mudar esta classe.

signal changed

var _items: Dictionary = {}   # code -> int


func add(code: String, qty: int = 1) -> void:
	if code == "":
		return
	_items[code] = _items.get(code, 0) + qty
	changed.emit()


func quantity(code: String) -> int:
	return _items.get(code, 0)


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
