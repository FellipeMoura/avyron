extends SceneTree

## Prova o Amplificador e o Encantador de ponta a ponta: o catálogo, a
## exclusividade do minério glacial, a bancada que cobra, a posse que barra, e
## o combate que finalmente lê o modificador.
##
## A pergunta que esta suíte responde é "minerar longe compra alguma coisa?".
## Antes dela o mapa tinha cinco biomas e **um** motivo para andar até
## qualquer um deles — a taxa de minério —, e nada que o jogador quisesse o
## bastante para atravessar o mar gelado. O que está sob teste não é
## `modifier *= 1.15`: é a cadeia de cavar num lugar específico, gastar o que
## se cavou, e sentir a diferença numa luta.
##
## Duas asserções negativas são as que mais importam, e é por elas que a
## suíte existe:
##
## - **Minério glacial não sai de nenhum outro bioma.** Se sair, o Encantador
##   deixa de ter lugar e o bioma inteiro vira decoração. A checagem varre os
##   catorze, não só o vizinho.
## - **Receita incompleta não cobra nada.** Faltando um dos três ingredientes,
##   os outros dois têm de continuar na bolsa — cobrar parcialmente deixaria o
##   jogador sem o material e sem a peça, e é o modo de falha que uma varredura
##   ingênua (`for line: remove(...)`) produz sem nenhum sintoma.
##
##     godot --headless --script res://scripts/dev/test_equipment.gd

const AMP_T1 := "EQP-001"
const AMP_T3 := "EQP-003"
const ENC_T1 := "EQP-004"
const ENC_T3 := "EQP-006"

const GLACIAL_BIOME := "BIO-014"
const GLACIAL_ORES := ["ITM-024", "ITM-025", "ITM-026"]

## Investida Bruta — o golpe de suporte que sobe o próprio ataque gastando a
## rodada. É a régua contra a qual o passivo tem de ser mais fraco.
const REFERENCE_BUFF_ABILITY := "HAB-020"

const STARTER := "CRT-002"
const RESERVE := "CRT-023"
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
			_test_bundle_contract()
			_test_glacial_exclusivity()
			_test_recipe_mirror()
			_test_loadout_ownership()
			_test_crafting()
			_test_battle_modifiers()
			_phase = "done"
		"done":
			_finish()
			return true
	return false


# ---------------------------------------------------------------------------
# contrato com o bestiário
# ---------------------------------------------------------------------------

func _test_bundle_contract() -> void:
	print("\n-- catalogo --")
	_check_true("o bundle traz equipamento", _db.has_equipment(),
		"%d modelos" % _db.equipment_codes().size())

	var amps := _db.equipment_in_slot(BestiaryData.SLOT_AMPLIFIER)
	var encs := _db.equipment_in_slot(BestiaryData.SLOT_ENCHANTER)
	_check_true("ha amplificador", not amps.is_empty(), "%d" % amps.size())
	_check_true("ha encantador", not encs.is_empty(), "%d" % encs.size())

	# A ordem é contrato de tela: a bancada e a janela do set desenham nesta
	# ordem, e o gesto rápido (`1`) tem de cair sempre no tier mais barato.
	for slot_models in [amps, encs]:
		var previous := 0
		for model in slot_models:
			var tier := int(model["tier"])
			_check_true_quiet("tier cresce na lista", tier > previous)
			previous = tier
	print("  ok   os dois slots saem ordenados do tier menor para o maior")

	for code: String in _db.equipment_codes():
		var effect := _db.equipment_effect_code(code)
		# Só os quatro modificadores. `damage`/`heal`/`charge_gain` são eventos
		# de turno e não têm como ser um passivo permanente — se um entrar aqui,
		# `Battle._apply_modifier` o ignora em silêncio e o modelo mente na tela.
		_check_true_quiet("efeito e um modificador",
			effect in ["buff_attack", "buff_defense", "debuff_attack", "debuff_defense"])
		_check_true_quiet("efeito tem valor", _db.equipment_effect_value(code) > 0.0)
		# Modelo sem receita nunca aparece na bancada, que é a única fonte —
		# ele existiria no catálogo prometendo ser conquistável e não seria.
		_check_true_quiet("modelo tem receita", not _db.equipment_recipe(code).is_empty())
		for line in _db.equipment_recipe(code):
			var item_code := str(line["itemCode"])
			_check_true_quiet("ingrediente e mineral",
				not _db.mineral(item_code).is_empty())
			_check_true_quiet("ingrediente pede quantidade", int(line["quantity"]) >= 1)
	print("  ok   todo modelo tem efeito valido, receita, e so pede mineral")

	# O passivo é de graça e permanente; a habilidade custa a rodada. Se o
	# passivo empatar com ela, o golpe de suporte vira conteúdo morto — esta é
	# a regra de balanceamento do sistema, e ela mora aqui porque é a única
	# que não dá para ler num número isolado.
	var strongest_passive := 0.0
	for code: String in _db.equipment_codes():
		strongest_passive = maxf(strongest_passive, _db.equipment_effect_value(code))
	# `HAB-020` (Investida Bruta) é a referência escrita à mão, mesmo estilo
	# dos `ITM-*` de `test_items`: é o golpe de suporte que sobe o próprio
	# ataque, e o valor dele sai do bundle — não do teste.
	var reference := _db.ability(REFERENCE_BUFF_ABILITY)
	var strongest_ability := float(reference.get("effectValue", 0.0)) if not reference.is_empty() \
		else 0.0
	_check_true("o passivo e mais fraco que o golpe que custa a rodada",
		strongest_ability <= 0.0 or strongest_passive < strongest_ability,
		"equipamento %d%% x habilidade %d%%" % [int(strongest_passive), int(strongest_ability)])


# ---------------------------------------------------------------------------
# exclusividade glacial
# ---------------------------------------------------------------------------

## O minério do Encantador só pode sair da Plataforma Glacial.
##
## A exclusividade **não** é uma regra de código — é a ausência de linha em
## `mining_rates`, que `MiningTable._weight_of` lê como peso zero. Justamente
## por ser ausência, ela some sem sintoma: alguém cadastra a taxa "faltante"
## num outro bioma achando que está preenchendo cobertura, e o Encantador
## passa a ser fabricável sem nunca sair da vila. É o que este teste vigia.
func _test_glacial_exclusivity() -> void:
	print("\n-- exclusividade do minerio glacial --")

	var classes := _db.class_codes()
	# Todos os biomas que algum mapa usa. É o conjunto que importa: um bioma
	# que nenhum mapa lista não tem como vazar para o jogador, porque ele
	# nunca pisa lá.
	var biomes := _all_biomes()
	_check_true("ha biomas para varrer", biomes.size() > 1, "%d biomas" % biomes.size())

	var found_in_glacial := {}
	var leaks: Array[String] = []
	for biome_code: String in biomes:
		for class_code: String in classes:
			for entry in MiningTable.distribution(_db, class_code, biome_code):
				var ore := str(entry["code"])
				if not (ore in GLACIAL_ORES):
					continue
				if biome_code == GLACIAL_BIOME:
					found_in_glacial[ore] = true
				else:
					leaks.append("%s em %s (%s)" % [ore, biome_code, class_code])

	_check("nenhum minerio glacial vaza para outro bioma", leaks.size(), 0)
	if not leaks.is_empty():
		printerr("       vazamentos: %s" % ", ".join(leaks))

	for ore in GLACIAL_ORES:
		_check_true("%s sai no glacial" % ore, found_in_glacial.has(ore),
			_db.mineral_name(ore))

	# O espelho: o material do Amplificador tem de sair em algum lugar que NÃO
	# é o glacial, senão as duas peças pedem a mesma viagem e a escolha de
	# desenho — "uma é perto, a outra é longe" — não existe em jogo.
	var amp_ores := {}
	for line in _db.equipment_recipe(AMP_T1):
		amp_ores[str(line["itemCode"])] = true
	var amp_outside := false
	for biome_code: String in biomes:
		if biome_code == GLACIAL_BIOME:
			continue
		for class_code: String in classes:
			for entry in MiningTable.distribution(_db, class_code, biome_code):
				if amp_ores.has(str(entry["code"])):
					amp_outside = true
	_check_true("o material do amplificador sai fora do glacial", amp_outside)


# ---------------------------------------------------------------------------
# o espelho de custo
# ---------------------------------------------------------------------------

## Amplificador e Encantador do mesmo tier custam o mesmo em óbolos.
##
## É a decisão de design inteira em um número: o Encantador não é a peça cara,
## é a peça **longe**. Se os valores divergirem, o eixo passa a ser preço e o
## bioma glacial vira só um lugar mais rico — que é outro jogo.
func _test_recipe_mirror() -> void:
	print("\n-- espelho de custo entre os dois slots --")
	var amps := _db.equipment_in_slot(BestiaryData.SLOT_AMPLIFIER)
	var encs := _db.equipment_in_slot(BestiaryData.SLOT_ENCHANTER)
	_check("os dois slots tem o mesmo numero de tiers", amps.size(), encs.size())

	for i in mini(amps.size(), encs.size()):
		var amp_code := str(amps[i]["code"])
		var enc_code := str(encs[i]["code"])
		_check("T%d custa o mesmo dos dois lados" % (i + 1),
			_recipe_value(amp_code), _recipe_value(enc_code))
		_check("T%d tem a mesma potencia dos dois lados" % (i + 1),
			int(_db.equipment_effect_value(amp_code)),
			int(_db.equipment_effect_value(enc_code)))


## Os biomas de todos os mapas, sem repetição.
func _all_biomes() -> Array:
	var seen := {}
	for map_code: String in _db.map_codes():
		for biome_code in _db.biomes_in_map(str(map_code)):
			seen[str(biome_code)] = true
	return seen.keys()


func _recipe_value(code: String) -> int:
	var total := 0
	for line in _db.equipment_recipe(code):
		total += _db.item_value(str(line["itemCode"])) * int(line["quantity"])
	return total


# ---------------------------------------------------------------------------
# posse
# ---------------------------------------------------------------------------

func _test_loadout_ownership() -> void:
	print("\n-- posse --")
	var loadout := PlayerLoadout.new()

	_check_true("comeca sem nada", not loadout.has_anything())
	# A checagem que o posto do Relicário não tem. Sem ela, a bancada seria
	# decoração: bastaria abrir a janela do set e escolher o T3.
	_check_true("nao veste o que nao e seu",
		not loadout.equip(AMP_T3, BestiaryData.SLOT_AMPLIFIER))
	_check("e o slot continua vazio", loadout.equipped_in(BestiaryData.SLOT_AMPLIFIER), "")

	_check_true("fabricar registra a posse",
		loadout.acquire(AMP_T1, BestiaryData.SLOT_AMPLIFIER))
	_check("e ja veste", loadout.equipped_in(BestiaryData.SLOT_AMPLIFIER), AMP_T1)
	_check_true("fabricar de novo o mesmo modelo e recusado",
		not loadout.acquire(AMP_T1, BestiaryData.SLOT_AMPLIFIER))

	# Slots independentes: vestir um encantador não pode desalojar o
	# amplificador — são peças simultâneas, não alternativas.
	loadout.acquire(ENC_T1, BestiaryData.SLOT_ENCHANTER)
	_check("o amplificador continua vestido",
		loadout.equipped_in(BestiaryData.SLOT_AMPLIFIER), AMP_T1)
	_check("e o encantador entrou no slot dele",
		loadout.equipped_in(BestiaryData.SLOT_ENCHANTER), ENC_T1)

	_check_true("tirar esvazia o slot", loadout.unequip(BestiaryData.SLOT_ENCHANTER))
	_check("o slot fica vazio", loadout.equipped_in(BestiaryData.SLOT_ENCHANTER), "")
	# Tirar não é perder: o modelo continua sendo do jogador, senão desequipar
	# por um duelo custaria trinta cobres.
	_check_true("mas a posse permanece", loadout.owns(ENC_T1))


# ---------------------------------------------------------------------------
# a bancada cobra
# ---------------------------------------------------------------------------

func _test_crafting() -> void:
	print("\n-- a bancada --")
	var inventory := _world.get("_inventory") as PlayerInventory
	var loadout := _world.get("_loadout") as PlayerLoadout
	if inventory == null or loadout == null:
		_check_true("o mundo expoe bolsa e loadout", false)
		return

	var recipe := _db.equipment_recipe(AMP_T1)
	_check_true("a receita do T1 tem ingredientes", recipe.size() >= 1, "%d" % recipe.size())

	# --- bolsa vazia: recusa e não cobra ---
	for line in recipe:
		inventory.remove(str(line["itemCode"]), inventory.quantity(str(line["itemCode"])))
	_world.craft_equipment(AMP_T1)
	_check_true("sem material nao fabrica", not loadout.owns(AMP_T1))

	# --- falta UM ingrediente: os outros continuam na bolsa ---
	# Esta é a asserção de "tudo ou nada". Uma implementação que gasta
	# enquanto varre passa em todos os outros testes desta suíte e falha só
	# aqui — e em jogo custaria o material do jogador sem nada em troca.
	var short_item := str(recipe[recipe.size() - 1]["itemCode"])
	for line in recipe:
		var item_code := str(line["itemCode"])
		var need := int(line["quantity"])
		inventory.add(item_code, need - (1 if item_code == short_item else 0))
	_world.craft_equipment(AMP_T1)
	_check_true("faltando um ingrediente, nao fabrica", not loadout.owns(AMP_T1))
	var kept := true
	for line in recipe:
		var item_code := str(line["itemCode"])
		var expected := int(line["quantity"]) - (1 if item_code == short_item else 0)
		if inventory.quantity(item_code) != expected:
			kept = false
	_check_true("e nao cobrou nada do que sobrou", kept)

	# --- completa: fabrica, cobra exato, e equipa ---
	inventory.add(short_item, 1)
	var before := {}
	for line in recipe:
		before[str(line["itemCode"])] = inventory.quantity(str(line["itemCode"]))
	_world.craft_equipment(AMP_T1)
	_check_true("com o material completo, fabrica", loadout.owns(AMP_T1))
	_check("e ja sai equipado", loadout.equipped_in(BestiaryData.SLOT_AMPLIFIER), AMP_T1)
	var exact := true
	for line in recipe:
		var item_code := str(line["itemCode"])
		if inventory.quantity(item_code) != int(before[item_code]) - int(line["quantity"]):
			exact = false
	_check_true("cobrou exatamente a receita, nem um a mais", exact)

	_world.craft_equipment(AMP_T1)
	_check_true("fabricar duas vezes o mesmo modelo nao cobra de novo",
		inventory.quantity(str(recipe[0]["itemCode"]))
			== int(before[str(recipe[0]["itemCode"])]) - int(recipe[0]["quantity"]))


# ---------------------------------------------------------------------------
# o combate lê o modificador
# ---------------------------------------------------------------------------

func _test_battle_modifiers() -> void:
	print("\n-- o modificador na batalha --")
	# `Combatant` direto, não `PlayerRoster.to_party()`: aquele devolve
	# `{code, hp, level}` e é a `DuelScreen` quem monta os combatentes a partir
	# dele. O que está sob teste aqui é o que `Battle` faz com combatentes
	# prontos, então montá-los aqui é o recorte certo.
	var party := _party_of([STARTER, RESERVE])
	var foe := Combatant.from_bestiary(_db, STARTER, LEVEL)
	if party.is_empty() or foe == null:
		_check_true("montou combatentes", false)
		return

	var battle := Battle.new(_db, party, foe, true)
	_check("sem loadout o ataque do time e neutro",
		snappedf(party[0].attack_modifier, 0.001), 1.0)
	_check("e o do adversario tambem",
		snappedf(foe.attack_modifier, 0.001), 1.0)

	var loadout := PlayerLoadout.new()
	loadout.acquire(AMP_T3, BestiaryData.SLOT_AMPLIFIER)
	loadout.acquire(ENC_T3, BestiaryData.SLOT_ENCHANTER)
	battle.apply_loadout(loadout)

	var amp_value := _db.equipment_effect_value(AMP_T3)
	var enc_value := _db.equipment_effect_value(ENC_T3)
	_check("o amplificador sobe o ataque do time",
		snappedf(party[0].attack_modifier, 0.001),
		snappedf(1.0 + amp_value / 100.0, 0.001))
	_check("o encantador baixa o do adversario",
		snappedf(foe.attack_modifier, 0.001),
		snappedf(1.0 - enc_value / 100.0, 0.001))
	# A peça é do domador, não da criatura: quem está no banco também tem de
	# entrar buffado, senão trocar no meio da luta desligaria o equipamento.
	var all_buffed := true
	for c: Combatant in party:
		if snappedf(c.attack_modifier, 0.001) != snappedf(1.0 + amp_value / 100.0, 0.001):
			all_buffed = false
	_check_true("o time inteiro recebe, nao so quem esta em campo", all_buffed,
		"%d criatura(s)" % party.size())
	# A defesa não é o eixo destes modelos — se ela se mexer, algum efeito
	# entrou no stat errado.
	_check("a defesa fica intocada", snappedf(party[0].defense_modifier, 0.001), 1.0)

	# Slot vazio não aplica nada: é o estado de quem tirou a peça para lutar
	# sem ela, e tem de ser mesmo neutro.
	var party2 := _party_of([STARTER])
	var foe2 := Combatant.from_bestiary(_db, STARTER, LEVEL)
	var battle2 := Battle.new(_db, party2, foe2, true)
	var empty := PlayerLoadout.new()
	empty.acquire(AMP_T3, BestiaryData.SLOT_AMPLIFIER)
	empty.unequip(BestiaryData.SLOT_AMPLIFIER)
	battle2.apply_loadout(empty)
	_check("peca guardada nao aplica nada",
		snappedf(party2[0].attack_modifier, 0.001), 1.0)


func _party_of(codes: Array) -> Array:
	var out: Array = []
	for code in codes:
		var c := Combatant.from_bestiary(_db, str(code), LEVEL)
		if c != null:
			out.append(c)
	return out


# ---------------------------------------------------------------------------
# harness
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


## Conta e só fala quando falha — usado nas varreduras que fazem centenas de
## verificações, onde uma linha por item afogaria o relatório.
func _check_true_quiet(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("  FAIL %s" % label)
