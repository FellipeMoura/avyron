extends SceneTree

## Valida o efeito visual de golpe/status em duelo — ausente até 2026-09
## (golpe e buff só mudavam texto; os corpos ficavam parados em `Idle`).
## Três peças, cada uma com contrato próprio:
##
## 1. `Battle._log` marca `is_player` por REFERÊNCIA (não por `actor.code`) —
##    sem isso, um duelo espécie-contra-a-mesma-espécie atribuiria todo
##    evento ao lado errado.
## 2. `ElementPalette.play_battle_effect` instancia a forma certa por
##    categoria (golpe: swing/claw por sorteio estável; status: shield;
##    carga: charge) e recolore pelas cores certas.
## 3. `EncounterDirector._play_one_battle_effect` despacha pro corpo certo —
##    dano no ALVO, status em quem usou, debuff no oponente — e nunca
##    reprocessa um evento já visto.
##
##     godot --headless --script res://scripts/dev/test_battle_effects.gd

var _db: BestiaryData
var _failures := 0
var _checks := 0
var _frames := 0


func _initialize() -> void:
	_db = BestiaryData.new()
	var err := _db.load_bundle()
	if err != "":
		printerr("FALHA ao carregar o bundle: ", err)
		quit(1)
		return

	_test_log_is_player()


## `ElementPalette.play_battle_effect` precisa de um `Node3D` DENTRO da
## árvore (usa `get_tree().create_timer`) — e, como o resto da suíte de
## atores, um nó criado dentro de `_initialize()` não conta como "na árvore"
## até o primeiro `_process` (mesma pegadinha do `CLAUDE.md`). Por isso as
## partes 2 e 3 esperam 2 quadros.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	_test_play_battle_effect_shapes()
	_test_director_dispatch()

	_db.free()
	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)
	return true


# ---------------------------------------------------------------------------
# 1. is_player por referência
# ---------------------------------------------------------------------------

func _test_log_is_player() -> void:
	print("-- Battle._log marca is_player")

	# Espécies DIFERENTES — o caso comum.
	var hero := Combatant.from_bestiary(_db, "CRT-021", 20)
	var foe := Combatant.from_bestiary(_db, "CRT-023", 20)
	var b := Battle.new(_db, [hero], foe)
	b.rng.seed = 1234
	var events := b.resolve_round(BattleAction.use_ability("HAB-001"), BattleAction.use_ability("HAB-010"))
	var by_player := events.filter(func(e: Dictionary) -> bool: return bool(e.get("is_player", false)))
	var by_enemy := events.filter(func(e: Dictionary) -> bool: return not bool(e.get("is_player", false)))
	_check_true("evento do jogador tem is_player=true", not by_player.is_empty())
	_check_true("evento do inimigo tem is_player=false", not by_enemy.is_empty())
	for e in by_player:
		_check_true("is_player=true -> actor é o codigo do heroi (%s)" % str(e.get("actor")),
			str(e.get("actor")) == hero.code)

	# MESMA espécie dos dois lados — o caso que `actor.code` sozinho não
	# resolveria. `is_player` continua certo porque compara por referência.
	var hero2 := Combatant.from_bestiary(_db, "CRT-001", 20)
	var foe2 := Combatant.from_bestiary(_db, "CRT-001", 20)
	var b2 := Battle.new(_db, [hero2], foe2)
	b2.rng.seed = 1234
	var ev2 := b2.resolve_round(BattleAction.use_ability("HAB-001"), BattleAction.use_ability("HAB-001"))
	var hero_side := ev2.filter(func(e: Dictionary) -> bool: return bool(e.get("is_player", false)))
	var enemy_side := ev2.filter(func(e: Dictionary) -> bool: return not bool(e.get("is_player", false)))
	_check_true("mesmo codigo dos dois lados: ainda separa jogador de inimigo",
		not hero_side.is_empty() and not enemy_side.is_empty())


# ---------------------------------------------------------------------------
# 2. ElementPalette.play_battle_effect
# ---------------------------------------------------------------------------

func _test_play_battle_effect_shapes() -> void:
	print("\n-- ElementPalette.play_battle_effect")
	var actor := CreatureActor.create(_db.creature("CRT-021"), Vector3.ZERO, 1)
	root.add_child(actor)

	actor.play_battle_effect("damage", "ELE-001", "HAB-001")
	var attack_children := actor.find_children("*", "VFXBattleSwingBB", true, false)
	_check_true("golpe instanciou swing/claw (VFXBattleSwingBB)", attack_children.size() == 1)
	if not attack_children.is_empty():
		var vfx := attack_children[0] as VFXBattleSwingBB
		_check("cor primaria = highlight do elemento",
			vfx.primary_color, ElementPalette.highlight_color("ELE-001"))
		# Duelo pausa a árvore inteira; sem isto o golpe nasce e trava no
		# quadro zero — invisível, porque a forma inteira depende da
		# animação abrir. Foi exatamente o bug relatado: "status anima,
		# golpe não".
		_check("golpe processa com a arvore pausada (PROCESS_MODE_ALWAYS)",
			vfx.process_mode, Node.PROCESS_MODE_ALWAYS)

	actor.play_battle_effect("buff", "ELE-002", "")
	var shield_children := actor.find_children("*", "VFXBattleShieldBB", true, false)
	_check_true("buff instanciou shield (VFXBattleShieldBB)", not shield_children.is_empty())
	if not shield_children.is_empty():
		_check("status tambem processa com a arvore pausada",
			(shield_children[0] as Node).process_mode, Node.PROCESS_MODE_ALWAYS)

	actor.play_battle_effect("charge", "ELE-003", "")
	_check_true("carga instanciou charge (VFXBattleChargeBB)",
		not actor.find_children("*", "VFXBattleChargeBB", true, false).is_empty())

	# Mesmo código -> mesma CENA, sempre (sorteio ESTÁVEL, não aleatório).
	# `swing` e `claw` compartilham a mesma classe de script (`VFXBattleSwingBB`
	# serve as duas cenas), então só o tipo não prova a escolha — o caminho da
	# cena de origem prova.
	var actor2 := CreatureActor.create(_db.creature("CRT-021"), Vector3(5, 0, 0), 1)
	root.add_child(actor2)
	actor2.play_battle_effect("damage", "ELE-001", "HAB-001")
	var repeat_children := actor2.find_children("*", "VFXBattleSwingBB", true, false)
	_check_true("mesmo codigo de habilidade -> mesma cena de origem (estavel)",
		not attack_children.is_empty() and not repeat_children.is_empty()
		and (attack_children[0] as Node).scene_file_path == (repeat_children[0] as Node).scene_file_path)

	actor.free()
	actor2.free()


# ---------------------------------------------------------------------------
# 3. EncounterDirector despacha pro corpo certo
# ---------------------------------------------------------------------------

func _test_director_dispatch() -> void:
	print("\n-- EncounterDirector despacha pro corpo certo")

	var hero := Combatant.from_bestiary(_db, "CRT-021", 20)
	var foe := Combatant.from_bestiary(_db, "CRT-023", 20)
	var battle := Battle.new(_db, [hero], foe)
	battle.rng.seed = 1234

	var duel := DuelScreen.new()
	duel.battle = battle

	# `_companion` é tipado `CompanionActor` em produção, não `CreatureActor` —
	# passar o tipo errado por `.set()` não dá erro nenhum, só deixa o campo
	# null em silêncio (reflexão não confere tipo estático). Usar o tipo real
	# aqui é o que prova o despacho de verdade, não um double emprestado.
	var fake_player := Node3D.new()
	root.add_child(fake_player)
	var companion := CompanionActor.create(_db, "CRT-021", fake_player)
	root.add_child(companion)
	var enemy_actor := CreatureActor.create(_db.creature("CRT-023"), Vector3(3, 0, 0), 1)
	root.add_child(enemy_actor)

	var director := EncounterDirector.new()
	director.set("_duel", duel)
	director.set("_companion", companion)
	director.set("_engaged_actor", enemy_actor)
	director.set("_battle_events_seen", 0)

	# HAB-001 (Brasa, dano) do jogador contra HAB-010 (dano) do inimigo — os
	# DOIS lados atacam na mesma rodada, e dano aparece no ALVO de cada um:
	# o golpe do jogador acerta o inimigo, o contra-ataque do inimigo acerta a
	# própria companheira. Exatamente 1 de cada, nunca os dois no mesmo corpo.
	battle.resolve_round(BattleAction.use_ability("HAB-001"), BattleAction.use_ability("HAB-010"))
	director.call("_play_battle_effects")

	_check("golpe do jogador acertou o inimigo (alvo)",
		enemy_actor.find_children("*", "VFXBattleSwingBB", true, false).size(), 1)
	_check("contra-ataque do inimigo acertou a propria companheira (alvo)",
		companion.find_children("*", "VFXBattleSwingBB", true, false).size(), 1)

	# Reprocessar sem rodada nova não deve duplicar.
	var swing_count_before := enemy_actor.find_children("*", "VFXBattleSwingBB", true, false).size()
	director.call("_play_battle_effects")
	_check("chamada repetida sem evento novo nao duplica efeito",
		enemy_actor.find_children("*", "VFXBattleSwingBB", true, false).size(), swing_count_before)

	# HAB-020 (buff_attack, em si mesmo) do jogador — tem de aparecer na
	# PRÓPRIA companheira, nunca no inimigo.
	battle.resolve_round(BattleAction.use_ability("HAB-020"), BattleAction.use_ability("HAB-010"))
	director.call("_play_battle_effects")
	_check_true("buff do jogador apareceu na propria companheira",
		not companion.find_children("*", "VFXBattleShieldBB", true, false).is_empty())

	companion.free()
	enemy_actor.free()
	fake_player.free()
	duel.free()


# ---------------------------------------------------------------------------
# relatório
# ---------------------------------------------------------------------------

func _check(label: String, actual: Variant, expected: Variant) -> void:
	_checks += 1
	if actual == expected:
		print("  ok   %s = %s" % [label, str(actual)])
	else:
		_failures += 1
		printerr("  FAIL %s = %s (esperado %s)" % [label, str(actual), str(expected)])


func _check_true(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
