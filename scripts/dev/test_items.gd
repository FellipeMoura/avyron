extends SceneTree

## Prova o uso de item de cura no mapa: a fórmula, o time que recebe, a janela
## que escolhe, e o `WorldRoot` que consome a bolsa.
##
## A pergunta que esta suíte responde é "comprar cura serve para alguma
## coisa?". Antes dela os emplastros eram compráveis, vendíveis e precificados,
## e **nada os consumia** — o laço econômico terminava numa vitrine. O que está
## sob teste não é `hp = hp + n`: é a cadeia de sair ferido do combate, gastar
## óbolo para não esperar os 10 %/min, e o item sumindo da bolsa exatamente uma
## vez.
##
## A asserção que mais importa é negativa: **cura nula não consome o item**.
## Um emplastro de 600 óbolos gasto num arranhão é o jeito mais caro de
## descobrir que a UI não checou nada.
##
##     godot --headless --script res://scripts/dev/test_items.gd

const STARTER := "CRT-002"    # Anomalocaris, Loricati
const RESERVE := "CRT-023"    # Scutosaurus, Draconis
const LEVEL := 10

const WEAK   := "ITM-016"     # Emplastro de Limo, +30%
const MEDIUM := "ITM-017"     # Emplastro Espesso, +70%
const FULL   := "ITM-018"     # Seiva Primordial, +100%

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
			_test_bundle_contract()
			_test_formula()
			_test_roster_heal()
			_test_window_flow()
			_test_world_use()
			_phase = "done"
		"done":
			_finish()
			return true
	return false


# ---------------------------------------------------------------------------
# contrato com o bestiário
# ---------------------------------------------------------------------------

func _test_bundle_contract() -> void:
	print("contrato dos itens de cura:")

	for code in [WEAK, MEDIUM, FULL]:
		var item := _db.item(code)
		_check_true("%s existe no bundle" % code, not item.is_empty())
		_check("%s e da categoria heal" % code, _db.item_category(code), "heal")
		_check_true("%s tem efeito de cura" % code,
			ItemEffects.is_heal(_db.item_effect_code(code)),
			_db.item_effect_code(code))
		_check_true("%s tem preco" % code, _db.item_value(code) > 0,
			"%d obolos" % _db.item_value(code))

	# Ordem de potência: se um dia o bestiário inverter isso, a lista da janela
	# passa a pôr o item caro na tecla `1` e o gesto rápido vira o caro.
	_check_true("a potencia cresce com o preco",
		_db.item_effect_value(WEAK) < _db.item_effect_value(MEDIUM)
		and _db.item_effect_value(MEDIUM) < _db.item_effect_value(FULL))

	# Cura não pode sair do chão: é a mesma armadilha que `test_merchant`
	# guarda para as resinas, e vale para toda categoria de consumível.
	var mineable := _db.mineral_codes()
	for code in [WEAK, MEDIUM, FULL]:
		_check_true("%s nao e mineravel" % code, not mineable.has(code))

	# O laço fecha no comerciante: sem oferta, comprar cura seria impossível e
	# o sistema inteiro ficaria inalcançável em jogo.
	var sells_heal := false
	for merchant in _db.merchants_in_map("PZ-01"):
		for offer in merchant.get("offers", []):
			if ItemEffects.is_heal(_db.item_effect_code(str(offer.get("itemCode", "")))):
				sells_heal = true
	_check_true("o comerciante do PZ-01 vende cura", sells_heal)


# ---------------------------------------------------------------------------
# fórmula
# ---------------------------------------------------------------------------

func _test_formula() -> void:
	print("formula de cura:")

	_check("30% de 200 sao 60",
		ItemEffects.heal_amount(ItemEffects.HEAL_PERCENT, 30.0, 200), 60)
	_check("100% de 200 enchem",
		ItemEffects.heal_amount(ItemEffects.HEAL_PERCENT, 100.0, 200), 200)
	# `heal_percent` traz pontos percentuais, não fração. Ler 30 como 30× é o
	# erro que transformaria o emplastro barato em cura infinita.
	_check_true("30 e trinta por cento, nao trinta vezes",
		ItemEffects.heal_amount(ItemEffects.HEAL_PERCENT, 30.0, 200) < 200)
	_check("arredonda para baixo",
		ItemEffects.heal_amount(ItemEffects.HEAL_PERCENT, 30.0, 11), 3)
	# Piso de 1: sem ele um teto pequeno faz o item ser consumido curando zero.
	_check("teto pequeno ainda cura 1",
		ItemEffects.heal_amount(ItemEffects.HEAL_PERCENT, 30.0, 2), 1)

	_check("heal_flat e ponto de HP cru",
		ItemEffects.heal_amount(ItemEffects.HEAL_FLAT, 40.0, 200), 40)

	_check("capture_bonus nao cura",
		ItemEffects.heal_amount(ItemEffects.CAPTURE_BONUS, 1.5, 200), 0)
	_check("efeito desconhecido nao cura",
		ItemEffects.heal_amount("teleporte", 9.0, 200), 0)
	_check("teto zero nao cura",
		ItemEffects.heal_amount(ItemEffects.HEAL_PERCENT, 30.0, 0), 0)

	_check_true("capture_bonus nao passa por is_heal",
		not ItemEffects.is_heal(ItemEffects.CAPTURE_BONUS))
	_check_true("none nao passa por is_heal",
		not ItemEffects.is_heal(ItemEffects.NONE))

	_check("rotulo percentual",
		ItemEffects.heal_label(ItemEffects.HEAL_PERCENT, 70.0), "+70%")
	_check("rotulo plano",
		ItemEffects.heal_label(ItemEffects.HEAL_FLAT, 40.0), "+40")

	# Os três itens do bundle, medidos contra o teto real da criatura inicial.
	var top := _new_roster().max_hp_at(0)
	var weak := ItemEffects.heal_amount(
		_db.item_effect_code(WEAK), _db.item_effect_value(WEAK), top)
	var full := ItemEffects.heal_amount(
		_db.item_effect_code(FULL), _db.item_effect_value(FULL), top)
	_check("a Seiva Primordial cobre o teto inteiro", full, top)
	_check_true("o Emplastro de Limo cobre so parte", weak > 0 and weak < top,
		"%d de %d" % [weak, top])


# ---------------------------------------------------------------------------
# time
# ---------------------------------------------------------------------------

func _test_roster_heal() -> void:
	print("cura no time:")
	var r := _new_roster()
	var top := r.max_hp_at(0)

	_check("cheia nao tem o que curar", r.missing_hp_at(0), 0)
	_check("curar quem esta cheia devolve zero", r.heal_at(0, 50), 0)

	r.set_hp_at(0, top - 30)
	_check("o que falta e medido", r.missing_hp_at(0), 30)
	_check("cura devolve o que entrou", r.heal_at(0, 10), 10)
	_check("e o HP subiu", r.hp_at(0), top - 20)

	# Excesso é aparado, e o retorno diz quanto entrou de fato — é esse número
	# que a janela mostra como "desperdicia N".
	_check("cura maior que o buraco entra so o que cabe", r.heal_at(0, 999), 20)
	_check("e para no teto", r.hp_at(0), top)

	_check("indice invalido devolve zero", r.heal_at(9, 50), 0)
	_check("indice negativo devolve zero", r.heal_at(-1, 50), 0)
	_check("quantidade zero devolve zero", r.heal_at(0, 0), 0)

	# Caída se cura: desmaiar é interdição temporária, a mesma regra da
	# regeneração por tempo.
	r.set_hp_at(0, 0)
	_check_true("caida esta caida", r.is_fainted_at(0))
	var healed := r.heal_at(0, 25)
	_check_true("caida pode ser curada", healed == 25, "%d de HP" % healed)
	_check_true("e volta a ficar de pe", not r.is_fainted_at(0))

	# O sinal é o que mantém companheira, painel e janela em dia; uma cura que
	# não avisa deixaria a HUD mostrando o HP de antes.
	var r2 := _new_roster()
	var beeps := [0]
	r2.changed.connect(func() -> void: beeps[0] += 1)
	r2.set_hp_at(0, 5)
	var before: int = beeps[0]
	r2.heal_at(0, 10)
	_check("cura efetiva emite changed", beeps[0], before + 1)
	r2.set_hp_at(0, r2.max_hp_at(0))
	before = beeps[0]
	r2.heal_at(0, 10)
	_check("cura nula nao emite changed", beeps[0], before)


# ---------------------------------------------------------------------------
# janela
# ---------------------------------------------------------------------------

func _test_window_flow() -> void:
	print("a janela do time escolhendo item:")
	var r := _new_roster()
	r.add(RESERVE)
	var top := r.max_hp_at(1)
	r.set_hp_at(1, top - 40)

	var bag := PlayerInventory.new()
	var window := RosterWindow.new()
	root.add_child(window)
	window.setup(_db, bag)
	window.refresh(r, LEVEL)

	_check_true("sem cura na bolsa o modo nao abre", not window.open_item_mode())
	_check("e o modo continua o normal", window.mode(), RosterWindow.Mode.LIST)

	bag.add(WEAK, 2)
	bag.add(FULL)
	# Resina na bolsa não pode virar item de cura na lista: o filtro é por
	# efeito, e é ele que separa as duas famílias de consumível.
	bag.add("ITM-013")
	_check_true("com cura na bolsa o modo abre", window.open_item_mode())
	_check("entra escolhendo o alvo", window.mode(), RosterWindow.Mode.PICK_TARGET)

	# Alvo cheio é recusado: o item seria consumido curando zero.
	window.choose_row(0)
	_check("criatura cheia nao vira alvo", window.mode(), RosterWindow.Mode.PICK_TARGET)
	window.choose_row(9)
	_check("slot vazio nao vira alvo", window.mode(), RosterWindow.Mode.PICK_TARGET)

	window.choose_row(1)
	_check("a ferida vira alvo", window.mode(), RosterWindow.Mode.PICK_ITEM)

	# `Esc` volta um passo por vez, e só devolve o `Esc` para quem chamou
	# quando já não há passo para voltar.
	_check_true("volta da lista de itens", window.back())
	_check("de volta ao alvo", window.mode(), RosterWindow.Mode.PICK_TARGET)
	_check_true("volta do alvo", window.back())
	_check("de volta a lista normal", window.mode(), RosterWindow.Mode.LIST)
	_check_true("na lista normal o Esc sobra para quem chamou", not window.back())

	# O pedido carrega alvo e item, e a janela não toca em nenhum dos dois.
	var asked: Array = []
	window.item_use_requested.connect(func(i: int, code: String) -> void:
		asked.append({"index": i, "code": code}))
	window.open_item_mode()
	window.choose_row(1)
	window.choose_row(0)
	_check("pediu um uso", asked.size(), 1)
	_check("com o alvo escolhido", int(asked[0]["index"]), 1)
	# Posição 0 é a cura mais fraca: o gesto rápido nunca é o item caro.
	_check("e com o item mais barato na tecla 1", str(asked[0]["code"]), WEAK)
	_check("a bolsa nao foi tocada pela janela", bag.quantity(WEAK), 2)
	_check("nem o time", r.hp_at(1), top - 40)
	# Depois do pedido a janela espera o próximo alvo — curar um time inteiro
	# depois de um tombo não deve custar um `I` por criatura.
	_check("volta a escolher alvo apos o uso", window.mode(), RosterWindow.Mode.PICK_TARGET)

	# Fechar solta o modo: reabrir no meio de uma escolha, com um alvo que pode
	# nem estar mais ferido, seria estado velho disfarçado de continuidade.
	window.open_item_mode()
	window.choose_row(1)
	window.close()
	_check("fechar volta ao modo normal", window.mode(), RosterWindow.Mode.LIST)

	# Bolsa esvaziada com a janela aberta cai sozinha para a lista normal.
	window.refresh(r, LEVEL)
	window.open_item_mode()
	bag.remove(WEAK, 2)
	bag.remove(FULL)
	window.refresh(r, LEVEL)
	_check("bolsa vazia derruba o modo", window.mode(), RosterWindow.Mode.LIST)

	window.free()


# ---------------------------------------------------------------------------
# mundo
# ---------------------------------------------------------------------------

func _test_world_use() -> void:
	print("no WorldRoot:")
	var r := _world.roster()
	var bag := _world.inventory()
	var top := r.max_hp_at(0)

	# Nada na bolsa: a tecla fala em vez de não fazer nada.
	_world.toggle_roster_window()
	_check_true("a janela abriu", _world.get_node_or_null("HudLayer") != null)
	_world.open_item_menu()

	bag.add(WEAK, 2)
	r.set_hp_at(0, 1)
	var expected := ItemEffects.heal_amount(
		_db.item_effect_code(WEAK), _db.item_effect_value(WEAK), top)

	_world.use_item_on_slot(0, WEAK)
	_check("o item saiu da bolsa uma vez", bag.quantity(WEAK), 1)
	_check("e a criatura curou o previsto", r.hp_at(0), 1 + expected)

	# Cura nula não consome: é a asserção que impede a Seiva Primordial de
	# evaporar num arranhão.
	r.set_hp_at(0, top)
	_world.use_item_on_slot(0, WEAK)
	_check("curar quem esta cheia nao gasta o item", bag.quantity(WEAK), 1)
	_check("e nao mexe no HP", r.hp_at(0), top)

	# Item que não cura não passa por aqui, mesmo estando na bolsa.
	bag.add("ITM-013")
	r.set_hp_at(0, 1)
	_world.use_item_on_slot(0, "ITM-013")
	_check("resina nao e usada como cura", bag.quantity("ITM-013"), 1)
	_check("e o HP fica onde estava", r.hp_at(0), 1)

	# Item que não está na bolsa não cura ninguém.
	_world.use_item_on_slot(0, FULL)
	_check("item ausente nao cura", r.hp_at(0), 1)

	# Slot inexistente é ignorado sem gastar nada.
	_world.use_item_on_slot(5, WEAK)
	_check("slot vazio nao gasta item", bag.quantity(WEAK), 1)

	# O caminho completo pela janela: I → alvo → item.
	r.set_hp_at(0, 1)
	var window: RosterWindow = _world.get_node("HudLayer").get_node("RosterWindow")
	_world.open_item_menu()
	_check("a janela entrou no modo de item", window.mode(), RosterWindow.Mode.PICK_TARGET)
	window.choose_row(0)
	_check("com a ferida como alvo", window.mode(), RosterWindow.Mode.PICK_ITEM)
	window.choose_row(0)
	_check_true("o fluxo pela janela curou", r.hp_at(0) > 1,
		"%d de HP" % r.hp_at(0))
	_check("e gastou o ultimo emplastro", bag.quantity(WEAK), 0)
	_check("sem cura na bolsa o modo cai", window.mode(), RosterWindow.Mode.LIST)

	_world.toggle_roster_window()


# ---------------------------------------------------------------------------

func _new_roster() -> PlayerRoster:
	var r := PlayerRoster.new()
	r.setup(_db, LEVEL, STARTER)
	return r


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
