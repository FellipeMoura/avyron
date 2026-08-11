extends SceneTree

## Validação headless de Glifos de arena (documento `glifos-e-portais`).
##
##     godot --headless --script res://scripts/dev/test_glyphs.gd
##
## Cobre `PlayerProgress` isolado (concessão, consulta, idempotência,
## persistência em disco) e a mesma condição que `WorldRoot._on_duel_closed`
## usa para conceder Glifo — vitória (`Battle.Outcome.PLAYER_WON`) numa
## batalha de arena (`is_wild = false`), nunca numa vitória contra criatura
## selvagem. `Battle` é `RefCounted` puro, então dá para testar a condição
## sem montar `WorldRoot` na árvore de cena (o padrão `_initialize`/`_process`
## descrito no `CLAUDE.md` daqui, reservado para o que depende de nó vivo).

const TEST_SAVE_PATH := "user://test_progress.cfg"

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

	_test_player_progress()
	_test_arena_win_grants_glyph()
	_test_wild_win_does_not_grant_glyph()

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


# ---------------------------------------------------------------------------

## Instância de teste isolada do save real do jogador (`use_path_for_test`) —
## rodar isto não pode apagar nem sujar o `user://progress.cfg` de quem está
## jogando na mesma máquina.
func _fresh_progress() -> PlayerProgress:
	var p := PlayerProgress.new()
	p.use_path_for_test(TEST_SAVE_PATH)
	return p


func _test_player_progress() -> void:
	print("PlayerProgress:")
	DirAccess.remove_absolute(TEST_SAVE_PATH)  # sem lixo de uma execucao anterior

	var p := _fresh_progress()
	_check_true("comeca sem Glifo", not p.has_glyph("DALETH"))

	_check_true("concede na primeira vez", p.grant_glyph("DALETH"))
	_check_true("posse reconhecida logo em seguida", p.has_glyph("DALETH"))

	_check_true("segunda concessao e idempotente (devolve false)", not p.grant_glyph("DALETH"))
	_check("so uma entrada apos concessao repetida", p.glyphs().size(), 1)

	# Simula reabrir o jogo: instancia nova, mesmo arquivo em disco.
	var reloaded := _fresh_progress()
	reloaded._load()
	_check_true("Glifo sobrevive a recarregar do disco", reloaded.has_glyph("DALETH"))

	_check_true("Glifo nao concedido continua ausente", not reloaded.has_glyph("ZAYIN"))

	p.free()
	reloaded.free()
	DirAccess.remove_absolute(TEST_SAVE_PATH)  # nao deixa andaime de teste


## Mesma matéria-prima de `test_battle.gd::_test_full_battle` — dirige uma
## batalha real até `is_over()` — mas com a config de uma arena: `is_wild =
## false` e uma vantagem de nível grande o bastante pra garantir vitória
## dentro do teto de rodadas, já que o RNG entra na variância de dano.
func _test_arena_win_grants_glyph() -> void:
	print("vitoria de arena concede Glifo:")
	DirAccess.remove_absolute(TEST_SAVE_PATH)
	var progress := _fresh_progress()

	var hero := Combatant.from_bestiary(_db, "CRT-021", 30)
	var foe := Combatant.from_bestiary(_db, "CRT-001", 5)
	var battle := Battle.new(_db, [hero], foe, false)
	battle.rng.seed = 99

	var rounds := 0
	while not battle.is_over() and rounds < 60:
		rounds += 1
		var options := hero.available_abilities()
		var pick := "HAB-001"
		for a in options:
			if str(a["effectCode"]) == "damage":
				pick = str(a["code"])
				break
		battle.resolve_round(BattleAction.use_ability(pick), battle.choose_enemy_action())

	_check("arena termina em vitoria do jogador", battle.outcome, Battle.Outcome.PLAYER_WON)
	_check_true("captura desligada (is_wild = false)", not battle.is_wild)

	# Mesma condição de `WorldRoot._on_duel_closed`: `_engaged_arena` presente
	# (aqui, simulado por sabermos que veio de arena) e `PLAYER_WON`.
	if battle.outcome == Battle.Outcome.PLAYER_WON:
		_check_true("concede o Glifo Daleth", progress.grant_glyph("DALETH"))
	_check_true("posse registrada", progress.has_glyph("DALETH"))

	progress.free()
	DirAccess.remove_absolute(TEST_SAVE_PATH)


## Mesma condição, mas o lado "mundo" nunca chama `grant_glyph` fora de uma
## arena — uma vitória contra criatura selvagem (`is_wild = true`) não passa
## por `_engaged_arena` em `WorldRoot`, então não há nada a conceder aqui.
## O teste prova a metade que cabe testar sem a árvore de cena: um
## `PlayerProgress` que nunca recebe a chamada continua sem o Glifo.
func _test_wild_win_does_not_grant_glyph() -> void:
	print("vitoria selvagem nao concede Glifo:")
	DirAccess.remove_absolute(TEST_SAVE_PATH)
	var progress := _fresh_progress()

	var hero := Combatant.from_bestiary(_db, "CRT-021", 30)
	var foe := Combatant.from_bestiary(_db, "CRT-001", 5)
	var battle := Battle.new(_db, [hero], foe, true)  # is_wild = true, como CreatureActor
	battle.rng.seed = 99

	var rounds := 0
	while not battle.is_over() and rounds < 60:
		rounds += 1
		var options := hero.available_abilities()
		var pick := "HAB-001"
		for a in options:
			if str(a["effectCode"]) == "damage":
				pick = str(a["code"])
				break
		battle.resolve_round(BattleAction.use_ability(pick), battle.choose_enemy_action())

	_check("mapa selvagem tambem termina em vitoria", battle.outcome, Battle.Outcome.PLAYER_WON)
	_check_true("captura ligada (is_wild = true)", battle.is_wild)
	# `_on_creature_engaged`/`_on_duel_closed` nunca chamam `grant_glyph` neste
	# caminho — nada a fazer aqui além de confirmar que ninguem chamou.
	_check_true("nenhum Glifo concedido", not progress.has_glyph("DALETH"))

	progress.free()
	DirAccess.remove_absolute(TEST_SAVE_PATH)
