extends SceneTree

## Validação headless do contrato de dados com o bestiário.
##
##     godot --headless --script res://scripts/dev/test_data.gd
##
## Não é suíte de testes de gameplay — é o guarda do *contrato*. Se o formato
## do bundle mudar, se uma fórmula sair do lugar ou se o export deixar passar
## uma criatura incompleta, é aqui que estoura, antes de virar bug de runtime.

var _failures := 0
var _checks := 0


func _init() -> void:
	# Fora da árvore de cena: nada libera este Node por nós, então o free()
	# é manual em todos os caminhos de saída.
	var db := BestiaryData.new()
	var err := db.load_bundle()
	if err != "":
		printerr("FALHA ao carregar o bundle: ", err)
		db.free()
		quit(1)
		return

	print("bundle: dataVersion %s, de %s" % [db.data_version, db.source])
	print("")

	_test_inventory(db)
	_test_stat_curve(db)
	_test_element_ring(db)
	_test_damage(db)
	_test_charge(db)
	_test_capture(db)
	_test_known_abilities(db)
	_test_turn_order()
	_test_contract_integrity(db)

	db.free()

	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# testes
# ---------------------------------------------------------------------------

func _test_inventory(db: BestiaryData) -> void:
	print("inventario:")
	_check("criaturas", db.creature_count(), 26)
	_check("habilidades", db.ability_count(), 31)
	_check_true("dataVersion preenchida", db.data_version != "")
	_check_true("bloco rules presente", not db.rules.is_empty())


func _test_stat_curve(db: BestiaryData) -> void:
	print("curva de nivel:")

	# Invariante: no nível 1 o valor efetivo é exatamente a base.
	_check("stat_at_level(85, 0.037, 1)", CombatMath.stat_at_level(85, 0.037, 1), 85)

	# floor(85 * (1 + 0.037 * 49)) = floor(239.105)
	_check("stat_at_level(85, 0.037, 50)", CombatMath.stat_at_level(85, 0.037, 50), 239)

	var lv1 := db.stats_at_level("CRT-021", 1)
	var lv50 := db.stats_at_level("CRT-021", 50)
	_check("CRT-021 ataque nivel 1", lv1["attack"], 85)
	_check_true("stats crescem com o nivel",
		lv50["attack"] > lv1["attack"] and lv50["hp"] > lv1["hp"],
		"atk %d -> %d" % [lv1["attack"], lv50["attack"]])


func _test_element_ring(db: BestiaryData) -> void:
	print("anel elemental:")
	# Agua -> Fogo -> Natureza -> Terra -> Gelo -> Eletricidade -> Agua
	_check("Agua vs Fogo", db.element_multiplier("ELE-002", "ELE-001"), 2.0)
	_check("Fogo vs Agua", db.element_multiplier("ELE-001", "ELE-002"), 0.5)
	_check("Eletricidade vs Agua", db.element_multiplier("ELE-005", "ELE-002"), 2.0)
	_check("Fogo vs Terra (neutro)", db.element_multiplier("ELE-001", "ELE-004"), 1.0)

	# Cada elemento vence exatamente um e perde para exatamente um.
	var ring := ["ELE-002", "ELE-001", "ELE-003", "ELE-004", "ELE-006", "ELE-005"]
	var strong_ok := true
	for i in ring.size():
		var atk: String = ring[i]
		var def: String = ring[(i + 1) % ring.size()]
		if db.element_multiplier(atk, def) != 2.0 or db.element_multiplier(def, atk) != 0.5:
			strong_ok = false
	_check_true("anel fechado nos 6 pares", strong_ok)


func _test_damage(db: BestiaryData) -> void:
	print("dano:")
	# (65 * 85 / 50) * 0.4 * 2.0 * 1.0 = 88.4 -> 88
	_check("poder 65, atk 85, def 50, x2", CombatMath.damage(65, 85, 50, 2.0, db.rules, 1.0), 88)
	# Movimento de status não causa dano.
	_check("poder 0 (status)", CombatMath.damage(0, 85, 50, 1.0, db.rules, 1.0), 0)
	# Piso: mesmo o golpe mais fraco contra a defesa mais alta tira 1.
	_check("piso de dano", CombatMath.damage(1, 1, 999, 0.5, db.rules, 1.0), 1)


func _test_charge(db: BestiaryData) -> void:
	print("carga do Despertar:")
	var taken := CombatMath.charge_from_damage_taken(20, 100, 50, db.rules)
	var dealt := CombatMath.charge_from_damage_dealt(20, 100, 50, db.rules)
	_check("sofrer 20 de 100 HP, carga 50", taken, 20.0)
	_check("causar 20 de 100 HP, carga 50", dealt, 10.0)
	_check_true("sofrer enche o dobro de causar", is_equal_approx(taken, dealt * 2.0),
		"%.1f vs %.1f" % [taken, dealt])

	# Carga acima de 50 enche proporcionalmente mais rápido.
	var high := CombatMath.charge_from_damage_taken(20, 100, 75, db.rules)
	_check_true("carga 75 enche mais que carga 50", high > taken, "%.1f vs %.1f" % [high, taken])


func _test_capture(db: BestiaryData) -> void:
	print("captura:")
	var full := CombatMath.capture_chance(190, 100, 100, db.rules)
	var hurt := CombatMath.capture_chance(190, 5, 100, db.rules)
	_check_true("enfraquecer aumenta a chance", hurt > full,
		"%.3f cheio vs %.3f ferido" % [full, hurt])

	var awake := CombatMath.capture_chance(190, 5, 100, db.rules, 1.0, 0.35, true)
	_check_true("Despertar dificulta a captura", awake < hurt,
		"%.3f desperto vs %.3f normal" % [awake, hurt])

	# Nunca garantida, nunca impossível.
	var ceiling := CombatMath.capture_chance(255, 1, 100, db.rules, 10.0)
	var floor_ := CombatMath.capture_chance(1, 100, 100, db.rules)
	_check("teto de 95%", ceiling, 0.95)
	_check("piso de 1%", floor_, 0.01)


func _test_known_abilities(db: BestiaryData) -> void:
	print("repertorio:")
	var at1 := db.known_abilities("CRT-021", 1)
	var at30 := db.known_abilities("CRT-021", 30)
	_check_true("nivel 1 ja conhece golpes", at1.size() >= 2, "%d golpes" % at1.size())
	_check("nivel 30 conhece os 6", at30.size(), 6)
	_check_true("repertorio cresce com o nivel", at30.size() > at1.size())

	# A assinatura do Despertar entra no nível 1 — é travada pela transformação
	# estar ativa, não pelo nível.
	var has_signature := false
	for a in at1:
		if a["awakeningOnly"]:
			has_signature = true
	_check_true("assinatura do Despertar disponivel desde o nivel 1", has_signature)


func _test_turn_order() -> void:
	print("ordem de turno:")
	_check_true("mais rapido age primeiro", CombatMath.turn_order_compare(0, 80, 0, 40) > 0)
	_check_true("prioridade vence velocidade", CombatMath.turn_order_compare(1, 10, 0, 99) > 0)
	_check("empate", CombatMath.turn_order_compare(0, 50, 0, 50), 0)


func _test_contract_integrity(db: BestiaryData) -> void:
	print("integridade do contrato:")
	var no_stats: Array = []
	var no_capture: Array = []
	var no_abilities: Array = []
	var no_awakening: Array = []
	var bad_element: Array = []

	for code in db.creature_codes():
		var c := db.creature(code)
		if c.get("stats", null) == null:
			no_stats.append(code)
		if c.get("capture", null) == null:
			no_capture.append(code)
		if c.get("abilities", []).is_empty():
			no_abilities.append(code)
		if c.get("awakening", null) == null:
			no_awakening.append(code)
		if db.element(str(c.get("element", ""))).is_empty():
			bad_element.append(code)

	_check("criaturas sem stats", no_stats.size(), 0)
	_check("criaturas sem regra de captura", no_capture.size(), 0)
	_check("criaturas sem golpes", no_abilities.size(), 0)
	_check("criaturas com elemento invalido", bad_element.size(), 0)
	# Despertar é opcional no schema, mas a meta do elenco é cobertura 1:1.
	_check_true("cobertura de Despertar 1:1", no_awakening.is_empty(),
		"sem despertar: %s" % str(no_awakening) if not no_awakening.is_empty() else "26 de 26")
