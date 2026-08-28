extends SceneTree

## Prova o time do jogador: composição, HP que persiste entre batalhas,
## recuperação por tempo, e o combate lutado com o time inteiro.
##
## A pergunta que esta suíte responde é "uma expedição custa alguma coisa?".
## Sem HP persistente, seis criaturas são seis opções e nenhuma é um recurso —
## então o que está sob teste não é `hp = hp - dano`, é a cadeia inteira:
## sair ferido de uma batalha, entrar ferido na próxima, e a espera no mapa
## sendo o único jeito de desfazer isso.
##
##     godot --headless --script res://scripts/dev/test_team.gd

const STARTER := "CRT-002"    # Anomalocaris, Arambi
const RESERVE := "CRT-023"    # Scutosaurus, Yaruki
const LEVEL := 10

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
			_test_composition()
			_test_hp_state()
			_test_regen()
			_test_storage_and_capacity()
			_test_progression()
			_test_battle_party()
			_test_replacement()
			_test_persistence_round_trip()
			_test_world_wiring()
			_phase = "done"
		"done":
			_finish()
			return true
	return false


func _new_roster() -> PlayerRoster:
	var r := PlayerRoster.new()
	r.setup(_db, LEVEL, STARTER)
	return r


# ---------------------------------------------------------------------------
# composição
# ---------------------------------------------------------------------------

func _test_composition() -> void:
	print("composicao do time:")
	var r := _new_roster()
	_check("comeca com a criatura inicial", r.size(), 1)
	_check("a inicial e a ativa", r.active(), STARTER)
	_check("sem reservas no inicio", r.reserves().size(), 0)

	_check_true("captura entra como reserva", r.add(RESERVE))
	_check("time cresceu", r.size(), 2)
	_check("a ativa nao mudou com a captura", r.active(), STARTER)
	_check("agora ha uma reserva", r.reserves().size(), 1)

	_check_true("trocar a ativa funciona", r.set_active(1))
	_check("a reserva foi a frente", r.active(), RESERVE)
	_check("a antiga ativa virou reserva", r.reserves()[0], STARTER)
	# Trocar não reordena: o slot 0 continua sendo a criatura inicial.
	_check("a ordem de captura nao muda com a troca", r.codes()[0], STARTER)

	_check_true("trocar para a propria ativa e no-op", not r.set_active(1))
	_check_true("indice fora da lista e no-op", not r.set_active(9))
	_check_true("indice negativo e no-op", not r.set_active(-1))

	var copy := r.codes()
	copy.append("CRT-001")
	_check("codes() devolve copia", r.size(), 2)

	_check_true("codigo inexistente e recusado", not r.add("CRT-999"))

	while not r.is_full():
		r.add("CRT-001")
	_check("time enche na capacidade atual", r.size(), r.capacity())
	_check_true("time cheio recusa captura", not r.add("CRT-003"))


# ---------------------------------------------------------------------------
# HP
# ---------------------------------------------------------------------------

func _test_hp_state() -> void:
	print("estado de HP:")
	var r := _new_roster()
	var top := r.max_hp_at(0)
	_check_true("o teto de HP vem do nivel", top > 0, "%d no Lv %d" % [top, LEVEL])
	_check("comeca com HP cheio", r.hp_at(0), top)
	_check_true("nao comeca caida", not r.is_fainted_at(0))

	r.set_hp_at(0, top - 10)
	_check("HP grava", r.hp_at(0), top - 10)
	r.set_hp_at(0, top + 999)
	_check("HP nao passa do teto", r.hp_at(0), top)
	r.set_hp_at(0, -50)
	_check("HP nao fica negativo", r.hp_at(0), 0)
	_check_true("zero e caida", r.is_fainted_at(0))
	_check("time inteiro caido tem zero de pe", r.alive_count(), 0)
	_check("sem ninguem de pe, first_alive e -1", r.first_alive_index(), -1)

	# Captura entra com o HP com que a criatura saiu da batalha.
	r.add(RESERVE, 7)
	_check("capturada entra ferida", r.hp_at(1), 7)
	_check("e conta como de pe", r.alive_count(), 1)
	_check("first_alive aponta para ela", r.first_alive_index(), 1)

	# Uma criatura caída pode ir à frente no mapa — quem barra desmaiada é o
	# combate, não a exploração. Sai do slot 0 antes de voltar a ele, senão o
	# no-op de "já é a ativa" mascararia o que está sendo testado.
	r.set_active(1)
	_check_true("caida pode ser ativa no mapa", r.set_active(0))
	_check("e ela esta mesmo a frente, caida", r.hp_at(r.active_index()), 0)


func _test_regen() -> void:
	print("recuperacao por tempo:")
	var r := _new_roster()
	var top := r.max_hp_at(0)
	r.set_hp_at(0, 0)

	# Um minuto de mapa, em passos de 1/60 s — o mesmo caminho que o
	# `_process` percorre, e o que prova que a fração não some no
	# arredondamento quadro a quadro.
	for _i in 60:
		r.regenerate(1.0)
	var after_minute := r.hp_at(0)
	var expected := int(float(top) * PlayerRoster.REGEN_FRACTION_PER_MINUTE)
	_check_true("um minuto recupera ~10%% do teto",
		absi(after_minute - expected) <= 1,
		"%d de %d (esperado ~%d)" % [after_minute, top, expected])

	# O passo fino não pode perder cura: 3600 quadros de 1/60 s são o mesmo
	# minuto. Sem o acumulador fracionário isto daria zero.
	var fine := _new_roster()
	fine.set_hp_at(0, 0)
	for _i in 3600:
		fine.regenerate(1.0 / 60.0)
	_check_true("passo de quadro recupera o mesmo que passo de segundo",
		absi(fine.hp_at(0) - after_minute) <= 1,
		"%d vs %d" % [fine.hp_at(0), after_minute])

	# Caída regenera: desmaiar é interdição temporária, não estado terminal.
	_check_true("criatura caida volta a ficar de pe", fine.hp_at(0) > 0,
		"%d de HP" % fine.hp_at(0))

	# Dez minutos enchem, e não passam disso.
	for _i in 600:
		fine.regenerate(1.0)
	_check("dez minutos enchem o HP", fine.hp_at(0), fine.max_hp_at(0))
	fine.regenerate(60.0)
	_check("cheia nao passa do teto", fine.hp_at(0), fine.max_hp_at(0))


# ---------------------------------------------------------------------------
# storage e capacidade dinamica (Relicario)
# ---------------------------------------------------------------------------

func _test_storage_and_capacity() -> void:
	print("storage e capacidade:")
	var r := _new_roster()
	_check("capacidade padrao antes de qualquer relicario", r.capacity(), 6)

	r.set_capacity(3)
	_check("set_capacity ajusta o teto", r.capacity(), 3)
	r.set_capacity(999)
	_check("set_capacity clampa no HARD_CEILING", r.capacity(), PlayerRoster.HARD_CEILING)
	r.set_capacity(3)

	_check_true("nao deposita a unica ativa", not r.deposit(0))
	r.add(RESERVE)
	_check_true("deposita quando sobra pelo menos uma", r.deposit(0))
	_check("foi para o storage", r.storage_size(), 1)
	_check("saiu do ativo", r.size(), 1)
	_check("quem sobrou vira a ativa", r.active(), RESERVE)

	_check_true("retira do storage", r.withdraw(0))
	_check("storage esvaziou", r.storage_size(), 0)
	_check("voltou pro ativo", r.size(), 2)

	# Lota o ativo (capacidade 3, já tem 2) com algo guardado à espera, pra
	# provar que retirar respeita o teto mesmo com storage não vazio.
	while not r.is_full():
		r.add("CRT-001")
	_check_true("time cheio", r.is_full())
	_check_true("abre vaga e guarda algo", r.deposit(0))
	r.add("CRT-001")
	_check_true("time cheio de novo, com algo no storage", r.is_full() and r.storage_size() > 0)
	_check_true("time cheio recusa retirada mesmo com storage nao vazio", not r.withdraw(0))
	_check_true("deposita para abrir vaga", r.deposit(0))
	_check_true("agora ha vaga, retirada funciona", r.withdraw(0))

	# Regen alcança o storage, não só o ativo — a guardada também cura sem
	# estar no mapa. Fere ANTES de depositar, senão ela já entraria cheia e a
	# regen não teria o que provar.
	var storage_check := _new_roster()
	storage_check.add(RESERVE)
	storage_check.set_hp_at(0, 0)  # fere a STARTER, ainda ativa
	storage_check.deposit(0)       # STARTER vai pro storage ferida; RESERVE fica ativa
	_check("STARTER esta guardada", storage_check.storage_entries()[0], STARTER)
	_check("entrou no storage ferida", storage_check.storage_hp_at(0), 0)
	for _i in 60:
		storage_check.regenerate(1.0)
	_check_true("guardada regenera sem estar no mapa", storage_check.storage_hp_at(0) > 0,
		"%d de HP apos 1 min" % storage_check.storage_hp_at(0))


# ---------------------------------------------------------------------------
# progressão de nível — XP de criatura, mesma lógica do Relicário
# ---------------------------------------------------------------------------

func _test_progression() -> void:
	print("progressao de nivel:")
	var xp_rules: Dictionary = _db.progression_rules().get("xp", {})
	var cost_rules: Dictionary = _db.progression_rules().get("levelUpCost", {})
	_check_true("bundle tem regras de progressao", not xp_rules.is_empty() and not cost_rules.is_empty())

	var r := _new_roster()
	_check("comeca no nivel do setup", r.level_at(0), LEVEL)
	_check("sem xp no comeco", r.xp_at(0), 0)

	var threshold := ProgressionMath.xp_to_next(
		float(xp_rules["curveBase"]), float(xp_rules["curveExponent"]), LEVEL)
	_check("xp_to_next_at bate com a formula", r.xp_to_next_at(0), threshold)

	# STARTER (CRT-002) é Arambi — o material e' o dela mesma, nao o de
	# quem foi derrotado.
	var class_code := str(_db.creature(STARTER).get("class", ""))
	var material := _db.class_material_item(class_code)
	_check_true("Arambi tem material de classe", material != "", material)

	var inv := PlayerInventory.new()

	# XP abaixo do limiar: acumula, sem subir, sem tocar a bolsa.
	var partial := r.grant_xp_at(0, 1, inv)
	_check_true("xp parcial nao sobe de nivel", not partial["leveled_up"])
	_check("xp foi somado", r.xp_at(0), 1)

	# Enche o limiar sem ter o material: trava no teto, avisa, nao rouba a bolsa.
	var filled := r.grant_xp_at(0, threshold, inv)
	_check_true("sem material, nao sobe", not filled["leveled_up"])
	_check_true("mas fica esperando", filled["waiting_material"])
	_check("xp trava exatamente no limiar", r.xp_at(0), threshold)
	_check("nivel nao mudou", r.level_at(0), LEVEL)

	# Com o material em mãos, o próximo ganho (por menor que seja) resolve.
	inv.add(material, int(cost_rules["base"]) + 5)  # folga generosa
	var qty_before := inv.quantity(material)
	var leveled := r.grant_xp_at(0, 1, inv)
	_check_true("com material, sobe de nivel", leveled["leveled_up"])
	_check("nivel foi pra frente", r.level_at(0), LEVEL + 1)
	_check("new_level bate com level_at", leveled["new_level"], r.level_at(0))
	var cost := ProgressionMath.material_cost(int(cost_rules["base"]), int(cost_rules["levelStep"]), LEVEL)
	_check("material foi consumido na quantidade certa", qty_before - inv.quantity(material), cost)
	# threshold + 1 - threshold = 1: o resto atravessa o level-up, nao some.
	_check("resto de xp atravessa o level-up", r.xp_at(0), 1)

	# Teto maximo de HP cresceu junto — a curva de stats le o novo nivel.
	var top_before: int = int(_db.stats_at_level(STARTER, LEVEL)["hp"])
	var top_after := r.max_hp_at(0)
	_check_true("HP maximo cresceu com o nivel", top_after > top_before,
		"%d -> %d" % [top_before, top_after])

	# Um salto de XP gigante sobe mais de um nivel numa unica chamada, desde
	# que a bolsa aguente o material de cada degrau.
	var big := _new_roster()
	var big_inv := PlayerInventory.new()
	big_inv.add(material, 999)
	var jump := big.grant_xp_at(0, threshold * 10, big_inv)
	_check_true("xp grande sobe de nivel", jump["leveled_up"])
	_check_true("mais de um nivel de uma vez", big.level_at(0) > LEVEL + 1,
		"foi ate %d" % big.level_at(0))

	# Indice invalido e quantidade zero sao no-op seguro.
	var noop := r.grant_xp_at(9, 10, inv)
	_check_true("indice invalido nao sobe nada", not noop["leveled_up"])
	var noop2 := r.grant_xp_at(0, 0, inv)
	_check_true("xp zero nao faz nada", not noop2["leveled_up"] and not noop2["waiting_material"])


# ---------------------------------------------------------------------------
# combate com time
# ---------------------------------------------------------------------------

func _test_battle_party() -> void:
	print("o duelo recebe o time inteiro:")
	var r := _new_roster()
	r.add(RESERVE)
	r.set_hp_at(1, 20)

	var duel := _make_duel(r, "CRT-017")
	_check("o time inteiro entrou em campo", duel.battle.player_party.size(), 2)
	_check("a ativa do mundo e a ativa da batalha",
		duel.battle.player_active().code, STARTER)
	_check_true("o HP ferido atravessou para a batalha",
		duel.battle.player_party[1].hp == 20,
		"%d" % duel.battle.player_party[1].hp)
	_check_true("quem estava cheia entrou cheia",
		duel.battle.player_party[0].hp == duel.battle.player_party[0].max_hp)

	# Troca em campo: custa a rodada e tem prioridade sobre golpe.
	var before := duel.battle.round_number
	duel.battle.resolve_round(BattleAction.switch_to(1), duel.battle.choose_enemy_action())
	_check("a troca gastou a rodada", duel.battle.round_number, before + 1)
	_check("a reserva entrou em campo", duel.battle.player_active().code, RESERVE)
	duel.queue_free()

	# Ativa caída na hora do encontro não entra em campo.
	var r2 := _new_roster()
	r2.add(RESERVE)
	r2.set_hp_at(0, 0)
	var duel2 := _make_duel(r2, "CRT-017")
	_check("ativa caida cede o campo para quem esta de pe",
		duel2.battle.player_active().code, RESERVE)
	duel2.queue_free()


func _test_replacement() -> void:
	print("substituicao da caida:")
	var r := _new_roster()
	r.add(RESERVE)
	var duel := _make_duel(r, "CRT-017")
	var b := duel.battle

	# Derruba a ativa direto no combatente: o que se testa aqui é a reação da
	# máquina ao tombo, não a fórmula de dano que leva até ele.
	b.player_party[0].hp = 0
	b._check_faints()

	_check_true("a batalha nao acabou com reserva de pe", not b.is_over())
	_check_true("a rodada trava esperando quem entra", b.needs_replacement())
	_check("so a reserva esta de pe", b.living_party_indices().size(), 1)

	_check_true("nao da para pedir quem ja caiu", not b.replace_active(0))
	_check_true("indice invalido e recusado", not b.replace_active(9))
	_check_true("a reserva entra", b.replace_active(1))
	_check("agora ela esta em campo", b.player_active().code, RESERVE)
	_check_true("a trava saiu", not b.needs_replacement())
	_check_true("substituir nao gastou rodada", b.round_number == 0,
		"rodada %d" % b.round_number)
	_check_true("substituir fora da trava e recusado", not b.replace_active(0))

	# Última de pé cai: aí sim é derrota.
	b.player_party[1].hp = 0
	b._check_faints()
	_check("time inteiro caido e derrota", b.outcome, Battle.Outcome.PLAYER_LOST)
	duel.queue_free()


func _test_persistence_round_trip() -> void:
	print("o dano volta para o time:")
	var r := _new_roster()
	r.add(RESERVE)
	var duel := _make_duel(r, "CRT-017")
	var b := duel.battle

	var lead: Combatant = b.player_party[0]
	var hurt := lead.max_hp - 17
	lead.hp = hurt
	(b.player_party[1] as Combatant).hp = 0
	b.player_active_index = 1

	r.absorb_party(b.player_party, b.player_active_index)

	_check("o HP da que lutou voltou para o time", r.hp_at(0), hurt)
	_check("a que caiu voltou caida", r.hp_at(1), 0)
	_check("quem terminou em campo virou a ativa do mundo", r.active_index(), 1)

	# E o próximo combate herda isso.
	var next_duel := _make_duel(r, "CRT-018")
	_check("a proxima batalha comeca com o HP de antes",
		next_duel.battle.player_party[0].hp, hurt)
	# A ativa do mundo está caída, então quem entra é a outra.
	_check("a caida nao entra em campo na proxima",
		next_duel.battle.player_active().code, STARTER)

	duel.queue_free()
	next_duel.queue_free()


# ---------------------------------------------------------------------------
# mundo
# ---------------------------------------------------------------------------

func _test_world_wiring() -> void:
	print("no WorldRoot:")
	var r := _world.roster()
	_check("o mundo comeca com um time de um", r.size(), 1)
	_check_true("com HP cheio", r.hp_at(0) == r.max_hp_at(0),
		"%d/%d" % [r.hp_at(0), r.max_hp_at(0)])

	# A regen do mundo passa pelo _process; um quadro longo prova a ligação.
	r.set_hp_at(0, 1)
	var before := r.hp_at(0)
	_world._process(120.0)
	_check_true("o mundo regenera o time no _process", r.hp_at(0) > before,
		"%d → %d" % [before, r.hp_at(0)])

	# Time inteiro caído barra o encontro em vez de abrir um duelo travado.
	r.set_hp_at(0, 0)
	_check("nenhuma de pe", r.alive_count(), 0)
	var spawner: CreatureSpawner = _world.get_node_or_null("CreatureSpawner")
	var target: CreatureActor = spawner.actors()[0] if spawner and not spawner.actors().is_empty() else null
	if target:
		_world.handle_click_on(target)
		_world.handle_click_on(target)
		_check_true("time caido nao abre combate",
			_world.get_node_or_null("DuelLayer") == null)

	# Recupera e o encontro volta a valer.
	r.set_hp_at(0, r.max_hp_at(0))
	if target:
		_world.handle_click_on(target)
		_world.handle_click_on(target)
		_check_true("com o time de pe o combate abre",
			_world.get_node_or_null("DuelLayer") != null)
		var layer := _world.get_node_or_null("DuelLayer")
		if layer:
			var duel: DuelScreen = layer.get_child(0)
			duel.closed.emit(Battle.Outcome.FLED)
		root.get_tree().paused = false


## Monta uma tela de duelo alimentada por um time, como o `WorldRoot` faz.
func _make_duel(roster: PlayerRoster, enemy: String) -> DuelScreen:
	var duel := load("res://scenes/duel.tscn").instantiate() as DuelScreen
	duel.player_code = roster.active()
	duel.player_party = roster.to_party()
	duel.player_active_index = roster.active_index()
	duel.enemy_code = enemy
	duel.duel_level = LEVEL
	root.add_child(duel)
	return duel


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
