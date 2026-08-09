extends SceneTree

## Prova a mineração data-driven e o time do jogador.
##
## O que está sob teste é a promessa central do sistema: **a criatura ativa
## muda o que sai do chão**. Um Loricati e um Draconis minerando o mesmo bioma
## têm de produzir distribuições diferentes — se produzirem a mesma, a fórmula
## está ignorando um dos dois fatores e ninguém notaria só jogando.
##
##     godot --headless --script res://scripts/dev/test_mining.gd

const BIOME := "BIO-001"

var _world: WorldRoot
var _db: BestiaryData
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
			_db = root.get_node_or_null("/root/Bestiary") as BestiaryData
			if _db == null:
				_db = BestiaryData.new()
				var err := _db.load_bundle()
				if err != "":
					_check_true("bundle carregou", false, err)
					_finish()
					return true
			_test_mining_data()
			_test_distribution()
			_test_sampling()
			_test_work_function()
			_test_inventory()
			_test_mining_flow()
			_test_roster_ui()
			_phase = "done"
		"done":
			_finish()
			return true
	return false


# ---------------------------------------------------------------------------
# dados
# ---------------------------------------------------------------------------

func _test_mining_data() -> void:
	print("bloco mining do bundle:")
	_check_true("o bundle traz mineracao", _db.has_mining(),
		"%d minerais" % _db.mineral_codes().size())
	_check_true("os minerais sao enderecados por ITM-*",
		str(_db.mineral_codes()[0]).begins_with("ITM-"),
		str(_db.mineral_codes()[0]))
	_check_true("mineral resolve nome pelo codigo",
		_db.mineral_name("ITM-001") != "ITM-001", _db.mineral_name("ITM-001"))
	_check("codigo desconhecido cai no proprio codigo",
		_db.mineral_name("ITM-999"), "ITM-999")

	for class_code in ["CLS-001", "CLS-002", "CLS-003"]:
		_check_true("classe %s tem pesos de minerio" % class_code,
			not _db.class_mining_weights(class_code).is_empty())
	_check_true("bioma %s tem pesos de minerio" % BIOME,
		not _db.biome_mining_weights(BIOME).is_empty())


# ---------------------------------------------------------------------------
# fórmula
# ---------------------------------------------------------------------------

func _test_distribution() -> void:
	print("distribuicao normalizar(classe x bioma):")

	var loricati := MiningTable.distribution(_db, "CLS-001", BIOME)
	_check_true("distribuicao nao vazia", not loricati.is_empty(),
		"%d minerais" % loricati.size())

	var total := 0.0
	for e in loricati:
		total += float(e["chance"])
	_check_true("as chances somam 1", absf(total - 1.0) < 0.0001, "%.6f" % total)

	_check_true("vem ordenada da maior chance para a menor",
		float(loricati[0]["chance"]) >= float(loricati[-1]["chance"]),
		"%.3f → %.3f" % [float(loricati[0]["chance"]), float(loricati[-1]["chance"])])

	# O ponto do sistema, e a razão de o painel da criatura ativa existir: cada
	# classe tem uma especialidade, e ela tem de aparecer no número. Loricati
	# escava âmbar fóssil (ITM-006); Draconis prospecta prata (ITM-005). Se um
	# dia essas duas comparações empatarem, a fórmula parou de ler um dos
	# lados — e o jogo inteiro fica igual com qualquer criatura à frente.
	var draconis := MiningTable.distribution(_db, "CLS-003", BIOME)
	var amber_loricati := _chance_of(loricati, "ITM-006")
	var amber_draconis := _chance_of(draconis, "ITM-006")
	var silver_loricati := _chance_of(loricati, "ITM-005")
	var silver_draconis := _chance_of(draconis, "ITM-005")

	_check_true("Loricati acha mais ambar fossil que Draconis",
		amber_loricati > amber_draconis,
		"%.1f%% vs %.1f%%" % [amber_loricati * 100.0, amber_draconis * 100.0])
	_check_true("Draconis acha mais prata que Loricati",
		silver_draconis > silver_loricati,
		"%.1f%% vs %.1f%%" % [silver_draconis * 100.0, silver_loricati * 100.0])

	# Sem criatura ativa o bioma decide sozinho, em vez de a mineração morrer.
	var biome_only := MiningTable.distribution(_db, "", BIOME)
	_check_true("sem classe, o bioma decide sozinho", not biome_only.is_empty(),
		"%d minerais" % biome_only.size())

	var nowhere := MiningTable.distribution(_db, "CLS-999", "BIO-999")
	_check_true("classe e bioma inexistentes devolvem vazio", nowhere.is_empty())


func _test_sampling() -> void:
	print("amostragem:")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var dist := MiningTable.distribution(_db, "CLS-001", BIOME)
	var expected := {}
	for e in dist:
		expected[str(e["code"])] = float(e["chance"])

	var counts := {}
	var draws := 4000
	for _i in draws:
		var m := MiningTable.sample(rng, _db, "CLS-001", BIOME)
		_check_true_quiet("sample devolve mineral valido", not m.is_empty())
		if m.is_empty():
			continue
		var code := str(m["code"])
		counts[code] = int(counts.get(code, 0)) + 1

	_check_true("nenhum codigo fora da distribuicao apareceu",
		_keys_within(counts, expected), str(counts.keys()))

	# O mineral mais provável tem de dominar a amostra. Não checo cada
	# frequência contra o peso: com 4000 sorteios os caudais raros (cristal a
	# 0,003%) têm ruído maior que o próprio valor, e o teste ficaria instável.
	var top_expected := str(dist[0]["code"])
	var top_sampled := ""
	var best := 0
	for code: String in counts:
		if int(counts[code]) > best:
			best = int(counts[code])
			top_sampled = code
	_check("o mineral mais provavel e o mais sorteado", top_sampled, top_expected)

	var no_data := MiningTable.sample(rng, _db, "CLS-999", "BIO-999")
	_check_true("sample sem dado devolve vazio", no_data.is_empty())


func _chance_of(dist: Array, code: String) -> float:
	for e in dist:
		if str(e["code"]) == code:
			return float(e["chance"])
	return 0.0


func _keys_within(counts: Dictionary, expected: Dictionary) -> bool:
	for code: String in counts:
		if not expected.has(code):
			return false
	return true


func _test_work_function() -> void:
	print("perfil de trabalho da classe:")
	_check_true("Theria escava mais rapido",
		MiningTable.speed_modifier(_db, "CLS-002") > 1.0,
		"x%.2f" % MiningTable.speed_modifier(_db, "CLS-002"))
	_check_true("Draconis escava mais devagar",
		MiningTable.speed_modifier(_db, "CLS-003") < 1.0,
		"x%.2f" % MiningTable.speed_modifier(_db, "CLS-003"))
	_check("classe inexistente e neutra", MiningTable.speed_modifier(_db, "CLS-999"), 1.0)

	_check_true("papel vem traduzido", MiningTable.role_label(_db, "CLS-001") == "escavadora",
		MiningTable.role_label(_db, "CLS-001"))
	_check("classe inexistente nao tem papel", MiningTable.role_label(_db, "CLS-999"), "")

	var preferred := MiningTable.preferred_names(_db, "CLS-001", BIOME, 3)
	_check("preferidos devolve 3 nomes", preferred.size(), 3)


# ---------------------------------------------------------------------------
# inventário e time
# ---------------------------------------------------------------------------

func _test_inventory() -> void:
	print("PlayerInventory:")
	var inv := PlayerInventory.new()
	_check("total inicial zero", inv.total_items(), 0)
	_check("quantity inicial zero", inv.quantity("ITM-001"), 0)

	inv.add("ITM-001")
	_check("apos add, total = 1", inv.total_items(), 1)
	_check("apos add, quantity ITM-001 = 1", inv.quantity("ITM-001"), 1)

	inv.add("ITM-001", 3)
	_check("apos add x3, quantity = 4", inv.quantity("ITM-001"), 4)

	inv.add("ITM-002")
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

	var collected := str(inv.entries()[0]["code"])
	_check_true("o que entrou e um mineral do bundle",
		not _db.mineral(collected).is_empty(), collected)

	# Cooldown ativo: segunda chamada imediata não deve adicionar.
	_world.trigger_mine()
	_check("cooldown bloqueia 2a mineracao", inv.total_items(), 1)

	# O cooldown gravado é o base dividido pelo modificador da classe ativa —
	# CRT-002 é Loricati (×1.0), então bate com a constante.
	_check_true("cooldown reflete o perfil da classe ativa",
		absf(_world._mine_cooldown - WorldRoot.MINE_COOLDOWN_SEC) < 0.01,
		"%.2fs" % _world._mine_cooldown)

	_world._mine_cooldown = 0.0
	_world.trigger_mine()
	_check_true("apos zerar cooldown, 3a mineracao funciona", inv.total_items() == 2,
		"%d itens" % inv.total_items())

	var panel: InventoryPanel = _world.get_node_or_null("HudLayer/InventoryPanel")
	_check_true("painel de inventario existe na HUD", panel != null)


# ---------------------------------------------------------------------------
# janelas
# ---------------------------------------------------------------------------

func _test_roster_ui() -> void:
	print("janelas de time:")
	var active_panel := _world.get_node_or_null("HudLayer/ActiveCreaturePanel")
	_check_true("painel da criatura ativa existe", active_panel != null)

	var window: RosterWindow = _world.get_node_or_null("HudLayer/RosterWindow")
	_check_true("janela do time existe", window != null)
	if window == null:
		return
	_check_true("a janela comeca fechada", not window.is_open())

	_world.toggle_roster_window()
	_check_true("T abre a janela", window.is_open())
	_world.toggle_roster_window()
	_check_true("T de novo fecha", not window.is_open())

	# Troca de ativa pelo mundo. O reserva é um Draconis de propósito: a
	# inicial é Loricati, então a troca tem de mudar classe, distribuição e
	# ritmo de mineração — os três de uma vez. Trocar por outro Loricati
	# passaria no teste sem provar nada.
	var r := _world.roster()
	var before := MiningTable.distribution(_db, _world._active_class_code(), BIOME)
	r.add("CRT-023")
	_world.activate_slot(1)
	_check("a criatura do slot 2 foi a frente", r.active(), "CRT-023")

	var companion: CompanionActor = _world.get_node_or_null("Companion")
	_check_true("a companheira acompanhou a troca",
		companion != null and companion.creature_code == "CRT-023",
		companion.creature_code if companion else "sem companheira")

	_check("a classe ativa mudou junto", _world._active_class_code(), "CLS-003")

	var after := MiningTable.distribution(_db, _world._active_class_code(), BIOME)
	_check_true("a distribuicao de minerio mudou com a troca",
		str(before[0]["code"]) != str(after[0]["code"])
			or absf(float(before[0]["chance"]) - float(after[0]["chance"])) > 0.01,
		"%s %.2f → %s %.2f" % [str(before[0]["name"]), float(before[0]["chance"]),
			str(after[0]["name"]), float(after[0]["chance"])])

	# E o ritmo: Draconis é ×0.9, então a espera cresce.
	_world._mine_cooldown = 0.0
	_world.trigger_mine()
	_check_true("o cooldown seguiu o perfil da classe nova",
		_world._mine_cooldown > WorldRoot.MINE_COOLDOWN_SEC,
		"%.2fs (base %.1fs)" % [_world._mine_cooldown, WorldRoot.MINE_COOLDOWN_SEC])

	_world.activate_slot(0)
	_check("volta para a inicial", r.active(), "CRT-002")


# ---------------------------------------------------------------------------

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
