extends SceneTree

## Prova o loop de mineração: F minera, inventário cresce, cooldown bloqueia
## a segunda mineração imediata, e zerar o cooldown libera a terceira.
##
##     godot --headless --script res://scripts/dev/test_mining.gd

var _world: WorldRoot
var _frames := 0
var _phase := "init"
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_world = load("res://scenes/main.tscn").instantiate() as WorldRoot
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	match _phase:
		"init":
			_test_ore_table()
			_test_inventory()
			_test_mining_flow()
			_phase = "done"
		"done":
			_finish()
			return true
	return false


func _test_ore_table() -> void:
	print("OreTable:")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# Amostras suficientes para confirmar que todas as espécies aparecem.
	var seen := {}
	for _i in 500:
		var ore := OreTable.sample(rng, "PZ-01")
		_check_true_quiet("sample retorna dicionario nao vazio", not ore.is_empty())
		if not ore.is_empty():
			seen[str(ore["code"])] = true
	_check_true("todas as 5 especies de minerio aparecem em 500 amostras",
		seen.size() == 5, "%d especies vistas" % seen.size())

	var empty := OreTable.sample(rng, "MAPA-INEXISTENTE")
	_check_true("mapa desconhecido retorna vazio", empty.is_empty())
	_check("ore_name ORE-001", OreTable.ore_name("ORE-001"), "Calcário")
	_check("ore_name desconhecido retorna o proprio codigo",
		OreTable.ore_name("ORE-999"), "ORE-999")


func _test_inventory() -> void:
	print("PlayerInventory:")
	var inv := PlayerInventory.new()
	_check("total inicial zero", inv.total_items(), 0)
	_check("quantity inicial zero", inv.quantity("ORE-001"), 0)

	inv.add("ORE-001")
	_check("apos add, total = 1", inv.total_items(), 1)
	_check("apos add, quantity ORE-001 = 1", inv.quantity("ORE-001"), 1)

	inv.add("ORE-001", 3)
	_check("apos add x3, quantity = 4", inv.quantity("ORE-001"), 4)

	inv.add("ORE-002")
	var entries := inv.entries()
	_check("entries tem 2 tipos", entries.size(), 2)
	_check_true("entries ordenado por codigo", str(entries[0]["code"]) < str(entries[1]["code"]))

	inv.add("")  # codigo vazio nao deve mudar nada
	_check("codigo vazio ignorado", inv.total_items(), 5)


func _test_mining_flow() -> void:
	print("mineracao no WorldRoot:")
	var inv := _world.inventory()
	_check("inventario inicial vazio", inv.total_items(), 0)

	_world.trigger_mine()
	_check_true("apos trigger_mine, inventario cresceu", inv.total_items() == 1,
		"%d itens" % inv.total_items())

	# Cooldown ativo: segunda chamada imediata não deve adicionar.
	_world.trigger_mine()
	_check("cooldown bloqueia 2a mineracao", inv.total_items(), 1)

	# Zera o cooldown manualmente — equivale a esperar MINE_COOLDOWN_SEC.
	_world._mine_cooldown = 0.0
	_world.trigger_mine()
	_check_true("apos zerar cooldown, 3a mineracao funciona", inv.total_items() == 2,
		"%d itens" % inv.total_items())

	# Painel atualizado após as minerações.
	var panel: InventoryPanel = _world.get_node_or_null("HudLayer/InventoryPanel")
	_check_true("painel de inventario existe na HUD", panel != null)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	_checks += 1
	if actual == expected:
		print("  ok   %s = %s" % [label, str(actual)])
	else:
		_failures += 1
		printerr("  FAIL %s = %s (esperado %s)" % [label, str(actual), str(expected)])


func _check_true(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s%s" % [label, (" — " + detail) if detail != "" else ""])
	else:
		_failures += 1
		printerr("  FAIL %s%s" % [label, (" — " + detail) if detail != "" else ""])


func _check_true_quiet(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("  FAIL %s" % label)
