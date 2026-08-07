extends SceneTree

## Validação headless da máquina de batalha.
##
##     godot --headless --script res://scripts/dev/test_battle.gd
##
## O RNG de cada batalha é semeado, então precisão, variância de dano e
## sorteio de captura ficam determinísticos — um teste que falha aqui falha
## sempre, não uma vez a cada dez execuções.

var _failures := 0
var _checks := 0
var _db: BestiaryData


func _init() -> void:
	_db = BestiaryData.new()
	var err := _db.load_bundle()
	if err != "":
		printerr("FALHA ao carregar o bundle: ", err)
		_db.free()
		quit(1)
		return

	_test_combatant_build()
	_test_turn_order()
	_test_damage_and_charge()
	_test_awakening_cycle()
	_test_switching()
	_test_capture()
	_test_status_effects()
	_test_full_battle()

	_db.free()

	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
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


## Batalha com semente fixa. CRT-021 Inostrancevia (Fogo, rápida, ofensiva)
## contra CRT-023 Scutosaurus (Terra, lenta, muralha).
func _battle(seed_value: int = 1234, level: int = 20) -> Battle:
	var hero := Combatant.from_bestiary(_db, "CRT-021", level)
	var foe := Combatant.from_bestiary(_db, "CRT-023", level)
	var b := Battle.new(_db, [hero], foe)
	b.rng.seed = seed_value
	return b


# ---------------------------------------------------------------------------

func _test_combatant_build() -> void:
	print("montagem do combatente:")
	var c := Combatant.from_bestiary(_db, "CRT-021", 1)
	_check("HP nivel 1", c.max_hp, 70)
	_check("ataque nivel 1", c.base_attack, 85)
	_check("comeca com HP cheio", c.hp, c.max_hp)
	_check("carga comeca zerada", c.charge_meter, 0.0)
	_check_true("tem Despertar", c.has_awakening, c.awakening_name)

	var lv30 := Combatant.from_bestiary(_db, "CRT-021", 30)
	_check_true("nivel 30 e mais forte", lv30.max_hp > c.max_hp,
		"%d vs %d de HP" % [c.max_hp, lv30.max_hp])

	# A assinatura do Despertar não aparece na lista até a transformação.
	var usable := c.available_abilities()
	var has_signature := false
	for a in usable:
		if a["awakeningOnly"]:
			has_signature = true
	_check_true("assinatura escondida fora do Despertar", not has_signature)

	_check_true("criatura inexistente devolve null",
		Combatant.from_bestiary(_db, "CRT-999", 1) == null)


func _test_turn_order() -> void:
	print("ordem de turno:")
	var b := _battle()
	# Inostrancevia tem velocidade 60, Scutosaurus 25.
	_check_true("heroi e mais rapido",
		b.player_active().effective_speed() > b.enemy.effective_speed(),
		"%d vs %d" % [b.player_active().effective_speed(), b.enemy.effective_speed()])

	var events := b.resolve_round(
		BattleAction.use_ability("HAB-001"),   # Brasa, prioridade 0
		BattleAction.use_ability("HAB-010")    # Seixo, prioridade 0
	)
	_check_true("mais rapido agiu primeiro", events[0]["actor"] == "CRT-021",
		"primeiro a agir foi %s" % events[0]["actor"])

	# Bote (HAB-024) tem prioridade 1 e deve agir antes mesmo vindo da
	# criatura muito mais lenta.
	#
	# O repertório de cada criatura é derivado do stat dominante dela, então
	# só quem tem velocidade como maior stat aprende o Bote — e a partir do
	# nível 8. Hylonomus nível 8 contra Meganeura nível 40 dá a diferença de
	# velocidade necessária com o golpe do lado certo.
	var slow := Combatant.from_bestiary(_db, "CRT-024", 8)
	var fast := Combatant.from_bestiary(_db, "CRT-009", 40)
	var b2 := Battle.new(_db, [slow], fast)
	b2.rng.seed = 5150

	_check_true("heroi e o mais lento", slow.effective_speed() < fast.effective_speed(),
		"%d vs %d" % [slow.effective_speed(), fast.effective_speed()])
	_check_true("o lento conhece o Bote", slow.uses_left("HAB-024") > 0)

	var slow_first := b2.resolve_round(
		BattleAction.use_ability("HAB-024"),   # Bote, prioridade 1
		BattleAction.use_ability("HAB-007")    # Esporo, prioridade 0
	)
	_check_true("prioridade vence velocidade", slow_first[0]["actor"] == "CRT-024",
		"primeiro a agir foi %s" % slow_first[0]["actor"])


func _test_damage_and_charge() -> void:
	print("dano e carga:")
	var b := _battle()
	var hero := b.player_active()
	var foe := b.enemy
	var foe_hp_before := foe.hp

	b.resolve_round(BattleAction.use_ability("HAB-001"), BattleAction.use_ability("HAB-010"))

	_check_true("inimigo perdeu HP", foe.hp < foe_hp_before,
		"%d -> %d" % [foe_hp_before, foe.hp])
	_check_true("heroi perdeu HP", hero.hp < hero.max_hp,
		"%d -> %d" % [hero.max_hp, hero.hp])
	_check_true("ambos ganharam carga", hero.charge_meter > 0.0 and foe.charge_meter > 0.0,
		"heroi %.1f, inimigo %.1f" % [hero.charge_meter, foe.charge_meter])

	# Usos são consumidos.
	_check("usos de HAB-001 caem", hero.uses_left("HAB-001"), 24)

	# Fogo contra Terra é neutro; Natureza contra Terra é super eficaz. O log
	# precisa refletir isso.
	var b2 := _battle()
	var ev := b2.resolve_round(
		BattleAction.use_ability("HAB-001"), BattleAction.use_ability("HAB-010"))
	for e in ev:
		if e["type"] == "damage" and e["actor"] == "CRT-021":
			_check("Fogo vs Terra e neutro", e["element_multiplier"], 1.0)


func _test_awakening_cycle() -> void:
	print("ciclo do Despertar:")
	var b := _battle()
	var hero := b.player_active()

	_check_true("nao desperta com medidor vazio", not b.activate_awakening(true))

	hero.charge_meter = 100.0
	var atk_before := hero.effective_attack()
	_check_true("desperta com medidor cheio", b.activate_awakening(true))
	_check_true("ataque sobe durante o Despertar", hero.effective_attack() > atk_before,
		"%d -> %d" % [atk_before, hero.effective_attack()])
	_check("medidor zera ao ativar", hero.charge_meter, 0.0)
	_check("duracao de 3 turnos", hero.awakened_rounds_left, 3)

	# A assinatura fica disponível durante a transformação.
	var has_signature := false
	for a in hero.available_abilities():
		if a["awakeningOnly"]:
			has_signature = true
	_check_true("assinatura liberada no Despertar", has_signature)

	# O medidor não acumula enquanto a transformação está ativa.
	hero.add_charge(50.0, b.charge_max())
	_check("carga nao acumula durante o Despertar", hero.charge_meter, 0.0)

	# Três rodadas e reverte.
	for i in 3:
		if not b.is_over():
			b.resolve_round(
				BattleAction.use_ability("HAB-001"), BattleAction.use_ability("HAB-010"))
	_check_true("reverteu apos 3 turnos", not hero.is_awakened,
		"turnos restantes: %d" % hero.awakened_rounds_left)
	_check("ataque volta ao normal", hero.effective_attack(), atk_before)


func _test_switching() -> void:
	print("troca de criatura:")
	var a := Combatant.from_bestiary(_db, "CRT-021", 20)
	var reserve := Combatant.from_bestiary(_db, "CRT-009", 20)
	var foe := Combatant.from_bestiary(_db, "CRT-023", 20)
	var b := Battle.new(_db, [a, reserve], foe)
	b.rng.seed = 99

	a.charge_meter = 100.0
	b.activate_awakening(true)
	_check_true("desperto antes da troca", a.is_awakened)

	b.resolve_round(BattleAction.switch_to(1), BattleAction.use_ability("HAB-010"))
	_check("ativo mudou", b.player_active().code, "CRT-009")
	_check_true("sair de campo reverte o Despertar", not a.is_awakened)

	# Trocar para a criatura que já está em campo é ignorado.
	var before := b.player_active().code
	b.resolve_round(BattleAction.switch_to(1), BattleAction.use_ability("HAB-010"))
	_check("troca redundante ignorada", b.player_active().code, before)


func _test_capture() -> void:
	print("captura:")
	# Inimigo quase derrotado e catchRate alto: captura praticamente certa.
	var hero := Combatant.from_bestiary(_db, "CRT-021", 20)
	var weak := Combatant.from_bestiary(_db, "CRT-024", 20)   # catchRate 200
	weak.hp = 1
	var b := Battle.new(_db, [hero], weak)
	b.rng.seed = 7

	b.resolve_round(BattleAction.capture(3.0), BattleAction.use_ability("HAB-007"))
	_check("capturou", b.outcome, Battle.Outcome.CAPTURED)
	_check_true("batalha terminou", b.is_over())

	# Com HP cheio a chance despenca — com a mesma semente, escapa.
	var healthy := Combatant.from_bestiary(_db, "CRT-023", 20)   # catchRate 65
	var b2 := Battle.new(_db, [Combatant.from_bestiary(_db, "CRT-021", 20)], healthy)
	b2.rng.seed = 7
	b2.resolve_round(BattleAction.capture(), BattleAction.use_ability("HAB-010"))
	_check_true("chefe com HP cheio escapa", b2.outcome != Battle.Outcome.CAPTURED)


func _test_status_effects() -> void:
	print("efeitos de status:")
	var b := _battle()
	var hero := b.player_active()

	# HAB-020 Investida Bruta: +30% de ataque em si mesmo.
	var before := hero.effective_attack()
	b.resolve_round(BattleAction.use_ability("HAB-020"), BattleAction.use_ability("HAB-010"))
	_check_true("buff de ataque aplicado", hero.effective_attack() > before,
		"%d -> %d" % [before, hero.effective_attack()])

	# HAB-025 Concentrar: +25 de carga.
	var b2 := _battle()
	var h2 := b2.player_active()
	var charge_before := h2.charge_meter
	b2.resolve_round(BattleAction.use_ability("HAB-025"), BattleAction.use_ability("HAB-010"))
	_check_true("Concentrar enche a carga", h2.charge_meter > charge_before + 20.0,
		"%.1f -> %.1f" % [charge_before, h2.charge_meter])

	# Golpe travado pelo Despertar é recusado fora dele.
	var b3 := _battle()
	var ev := b3.resolve_round(
		BattleAction.use_ability("HAB-026"), BattleAction.use_ability("HAB-010"))
	var refused := false
	for e in ev:
		if e["type"] == "invalid":
			refused = true
	_check_true("assinatura recusada sem Despertar", refused)


func _test_full_battle() -> void:
	print("batalha completa:")
	var b := _battle(2024, 25)
	var rounds := 0

	while not b.is_over() and rounds < 60:
		rounds += 1
		var hero := b.player_active()
		# Desperta assim que puder — é o que um jogador faria.
		if hero.can_awaken(b.charge_max()):
			b.activate_awakening(true)
		if b.enemy.can_awaken(b.charge_max()):
			b.activate_awakening(false)

		var options := hero.available_abilities()
		var pick := "HAB-001"
		for a in options:
			if str(a["effectCode"]) == "damage":
				pick = str(a["code"])
				break

		b.resolve_round(BattleAction.use_ability(pick), b.choose_enemy_action())

	_check_true("batalha terminou", b.is_over(), "em %d rodadas" % rounds)
	_check_true("terminou em tempo razoavel", rounds >= 3 and rounds <= 40,
		"%d rodadas" % rounds)
	_check_true("houve Despertar em algum momento",
		_log_has(b, "awaken"), "eventos: %d" % b.log_events.size())
	_check_true("alguem foi derrotado", _log_has(b, "faint"))

	print("     resumo da luta:")
	for e in b.log_events:
		if e["type"] in ["awaken", "revert", "faint"]:
			print("       r%d %s" % [e["round"], e["text"]])


func _log_has(b: Battle, type: String) -> bool:
	for e in b.log_events:
		if e["type"] == type:
			return true
	return false
