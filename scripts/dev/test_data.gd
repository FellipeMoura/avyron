extends SceneTree

## Validação headless do contrato de dados com o bestiário.
##
##     godot --headless --script res://scripts/dev/test_data.gd
##
## Não é suíte de testes de gameplay — é o guarda do *contrato*. Se o formato
## do bundle mudar, se uma fórmula sair do lugar ou se o export deixar passar
## uma criatura incompleta, é aqui que estoura, antes de virar bug de runtime.

var _failures := 0
var _warnings := 0
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
	_test_known_abilities(db)
	_test_turn_order()
	_test_contract_integrity(db)
	_test_palette_contract(db)
	_test_mining_contract(db)
	_test_biome_contract(db)
	_test_relics_contract(db)
	_test_relic_math(db)

	db.free()

	print("")
	if _failures == 0:
		var suffix := "" if _warnings == 0 else " (%d aviso(s))" % _warnings
		print("OK — %d verificacoes passaram%s" % [_checks, suffix])
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


## Meta de conteúdo, não invariante: reporta e não reprova.
##
## A distinção existe porque as duas coisas estavam misturadas — a suíte
## reprovava em cobertura de Despertar, que `docs/DATA_WORKFLOW.md` chama de
## passo opcional, e não checava o golpe de assinatura sem Despertar, que é
## erro de dado de verdade. Suíte vermelha tem de significar "quebrado"; o que
## é alvo sai por aqui. Mesmo critério do `pnpm game:export`, que aborta num e
## avisa no outro.
func _warn(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok   %s%s" % [label, (" — " + detail) if detail != "" else ""])
	else:
		_warnings += 1
		print("  AVISO %s%s" % [label, (" — " + detail) if detail != "" else ""])


# ---------------------------------------------------------------------------
# testes
# ---------------------------------------------------------------------------

## Paleta do elemento — o par exato do que `export-game-data.mjs` cobra, pelo
## critério da casa: contradição de dado REPROVA, meta de conteúdo AVISA.
##
## Elemento sem paleta nenhuma avisa: as criaturas dele saem no corpo neutro e
## o jogo roda. Paleta pela METADE reprova: rampa sem uma parada não é rampa,
## e o jogo teria de inventar a cor que falta — a criatura sairia errada em
## silêncio, que é a classe de furo que `CRT-013` custou caro para ensinar.
##
## O comportamento da recoloração e da aura vive em `test_palette.gd`; aqui é
## só o contrato do bundle, que é o que esta suíte guarda.
func _test_palette_contract(db: BestiaryData) -> void:
	print("-- contrato da paleta dos elementos")
	var hex := RegEx.new()
	hex.compile("^#[0-9a-fA-F]{6}$")

	var missing: Array[String] = []
	for code in db.element_codes():
		var raw: Variant = db.element(code).get("palette")
		if not (raw is Dictionary) or (raw as Dictionary).is_empty():
			missing.append(code)
			continue
		var p: Dictionary = raw
		var absent: Array[String] = []
		for key in ["shadow", "mid", "highlight", "aura"]:
			if not p.has(key):
				absent.append(key)
			elif hex.search(str(p[key])) == null:
				_check_true("%s paleta %s e #RRGGBB" % [code, key], false, str(p[key]))
		_check_true("%s tem a rampa completa" % code, absent.is_empty(),
			"faltam %s" % ", ".join(absent) if not absent.is_empty() else "")
		var spread := float(p.get("spread", -1.0))
		_check_true("%s spread em [0, 0.5]" % code, spread >= 0.0 and spread <= 0.5, str(spread))

	_warn("todo elemento tem paleta", missing.is_empty(),
		"sem paleta: %s" % ", ".join(missing) if not missing.is_empty() else "")
	print("")


func _test_inventory(db: BestiaryData) -> void:
	print("inventario:")
	# Contagens crescem com o catálogo — travar um número fixo faria este teste
	# quebrar a cada criatura nova cadastrada no bestiário sem nenhum bug real.
	# O que importa guardar é que o bundle não está vazio.
	_check_true("tem criaturas", db.creature_count() > 0, "%d" % db.creature_count())
	_check_true("tem habilidades", db.ability_count() > 0, "%d" % db.ability_count())
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

	# Golpes utilitários não têm elemento. `str(null)` em GDScript devolve
	# "<null>", então ler o campo cru passaria despercebido em qualquer
	# checagem de string vazia.
	_check("golpe sem elemento devolve vazio",
		BestiaryData.ability_element(db.ability("HAB-024")), "")
	_check("golpe elemental devolve o codigo",
		BestiaryData.ability_element(db.ability("HAB-001")), "ELE-001")


func _test_damage(db: BestiaryData) -> void:
	print("dano:")

	# O esperado é derivado das regras do bundle, não fixado num número.
	# Balancear é mudar as constantes; se o teste travasse o resultado, todo
	# ajuste legítimo quebraria a suíte e ninguém confiaria mais nela. O que
	# precisa ser guardado é a FORMA da conta.
	var k := float(db.rules["damage"]["constant"])
	var expected := int(floor((65.0 * 85.0 / 50.0) * k * 2.0 * 1.0))
	_check("poder 65, atk 85, def 50, x2 (constante %.2f)" % k,
		CombatMath.damage(65, 85, 50, 2.0, db.rules, 1.0), expected)

	# Dobrar o poder dobra o dano; dobrar a defesa o corta pela metade.
	var base := CombatMath.damage(60, 100, 50, 1.0, db.rules, 1.0)
	_check_true("dano escala linear com o poder",
		absi(CombatMath.damage(120, 100, 50, 1.0, db.rules, 1.0) - base * 2) <= 1,
		"%d -> %d" % [base, CombatMath.damage(120, 100, 50, 1.0, db.rules, 1.0)])
	_check_true("dano cai pela metade com o dobro da defesa",
		absi(CombatMath.damage(60, 100, 100, 1.0, db.rules, 1.0) - base / 2) <= 1)

	# Movimento de status não causa dano.
	_check("poder 0 (status)", CombatMath.damage(0, 85, 50, 1.0, db.rules, 1.0), 0)
	# Piso: mesmo o golpe mais fraco contra a defesa mais alta tira o mínimo.
	_check("piso de dano", CombatMath.damage(1, 1, 999, 0.5, db.rules, 1.0),
		int(db.rules["damage"]["minimum"]))


func _test_charge(db: BestiaryData) -> void:
	print("carga do Despertar:")
	var c: Dictionary = db.rules["charge"]
	var neutral := int(c["neutralCharge"])

	# Como no dano, o esperado sai das regras: uma criatura de carga neutra
	# que sofre 20% do próprio HP ganha 20% do medidor vezes o peso do lado.
	var taken := CombatMath.charge_from_damage_taken(20, 100, neutral, db.rules)
	var dealt := CombatMath.charge_from_damage_dealt(20, 100, neutral, db.rules)
	_check("sofrer 20%% do HP com carga neutra", taken,
		0.2 * float(c["max"]) * float(c["takenMultiplier"]))
	_check("causar 20%% do HP do alvo", dealt,
		0.2 * float(c["max"]) * float(c["dealtMultiplier"]))

	# O invariante de design: apanhar precisa encher mais que bater, senão
	# quem está ganhando desperta primeiro e o Despertar vira amplificador de
	# vitória em vez de virada de jogo.
	_check_true("sofrer enche mais que causar", taken > dealt,
		"%.1f vs %.1f" % [taken, dealt])

	# Carga acima da neutra enche proporcionalmente mais rápido.
	var high := CombatMath.charge_from_damage_taken(20, 100, neutral + 25, db.rules)
	_check_true("carga acima da neutra enche mais", high > taken,
		"%.1f vs %.1f" % [high, taken])

	# Sanidade de tuning: uma criatura neutra não deve precisar sofrer mais
	# que o próprio HP para despertar — se precisar, ela morre antes.
	var hp_needed := float(c["max"]) / (float(c["takenMultiplier"]) * float(c["max"])) * 100.0
	_check_true("desperta antes de morrer", hp_needed < 100.0,
		"precisa sofrer %.0f%% do HP maximo" % hp_needed)


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
	var bad_drops := 0

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
		# `creature_drops` não pode estourar nem devolver algo que não seja
		# array — é o que `LootTable.roll` itera direto em combate.
		if typeof(db.creature_drops(code)) != TYPE_ARRAY:
			bad_drops += 1

	_check("criaturas sem stats", no_stats.size(), 0)
	_check("criaturas sem regra de captura", no_capture.size(), 0)
	_check("criaturas sem golpes", no_abilities.size(), 0)
	_check("criaturas com elemento invalido", bad_element.size(), 0)
	_check("criaturas com bloco de drops invalido", bad_drops, 0)
	# Golpe de assinatura sem Despertar é erro de dado, não meta: `Combatant`
	# filtra `awakeningOnly` por `is_awakened`, e criatura que nunca desperta
	# nunca pode usar o golpe. Ele aparece na ficha e não serve pra nada.
	# `CRT-013` jogou assim com 5 golpes contra 6 do resto do elenco.
	var dead_signature: Array = []
	for code in db.creature_codes():
		var c := db.creature(code)
		if c.get("awakening", null) != null:
			continue
		for entry in c.get("abilities", []):
			var a := db.ability(str(entry["code"]))
			if not a.is_empty() and bool(a.get("awakeningOnly", false)):
				dead_signature.append("%s/%s" % [code, str(entry["code"])])
	_check("golpes de assinatura inalcancaveis", dead_signature.size(), 0)

	# A cobertura em si é meta, não invariante — o Despertar é o passo
	# opcional do `DATA_WORKFLOW`, e sem ele a criatura ainda joga, só não usa
	# o medidor de carga. Mesmo critério do `pnpm game:export`, que avisa aqui
	# e aborta no golpe morto acima.
	_warn("cobertura de Despertar 1:1", no_awakening.is_empty(),
		"sem despertar: %s" % str(no_awakening) if not no_awakening.is_empty()
		else "%d de %d" % [db.creature_codes().size(), db.creature_codes().size()])


## O bloco `mining` é opcional para `load_bundle` — o jogo sobe sem ele com um
## aviso, porque combate não depende de minério. Aqui não é opcional: um export
## sem mineração é um export velho, e é este teste que tem de dizer isso em vez
## de o jogador descobrir que `F` não faz nada.
func _test_mining_contract(db: BestiaryData) -> void:
	print("contrato de mineracao:")
	_check_true("bloco mining presente", db.has_mining(),
		"%d minerais" % db.mineral_codes().size())
	if not db.has_mining():
		return

	var unnamed: Array = []
	for code in db.mineral_codes():
		if db.mineral_name(str(code)) == str(code):
			unnamed.append(code)
	_check("minerais sem nome", unnamed.size(), 0)

	# Toda classe do elenco precisa de pesos: sem eles, a criatura ativa dessa
	# classe minera pelo bioma puro e o perfil de trabalho vira decoração.
	var classes_seen := {}
	for code in db.creature_codes():
		classes_seen[str(db.creature(str(code)).get("class", ""))] = true

	var no_weights: Array = []
	var no_profile: Array = []
	for class_code: String in classes_seen:
		if db.class_mining_weights(class_code).is_empty():
			no_weights.append(class_code)
		if db.class_work_function(class_code).is_empty():
			no_profile.append(class_code)
	_check("classes sem pesos de minerio", no_weights.size(), 0)
	_check("classes sem perfil de trabalho", no_profile.size(), 0)

	# Peso que aponta para um mineral inexistente some numa distribuição
	# normalizada, sem sintoma. O export passou a abortar nisso em 2026-08;
	# esta checagem continua porque ela guarda o bundle já escrito, não a
	# escrita — bundle antigo no disco não passou pelo portão novo.
	var orphan := 0
	for class_code: String in classes_seen:
		for item_code: String in db.class_mining_weights(class_code):
			if db.mineral(item_code).is_empty():
				orphan += 1
	_check("pesos apontando para mineral inexistente", orphan, 0)


## O bioma é metade da fórmula de mineração, e a metade que some calada.
##
## `MiningTable` trata lado ausente como neutro (×1) de propósito — sem
## criatura ativa o bioma decide sozinho. O efeito colateral é que um bioma
## sem taxa nenhuma não dá erro: a fórmula simplesmente vira só-classe e a
## picareta continua funcionando, entregando outra distribuição. Por isso o
## bioma que o mundo declara é verificado aqui, não confiado ao runtime.
##
## Erro e alvo saem por portas diferentes, como no resto do arquivo: bioma
## declarado fora do mapa ou sem taxas é `_check` (o mundo está errado);
## bioma do mapa que ninguém preencheu ainda é `_warn` (o catálogo está
## incompleto, e o export avisa a mesma coisa).
func _test_biome_contract(db: BestiaryData) -> void:
	print("contrato de bioma:")

	var of_map := db.biomes_in_map(WorldRoot.DEFAULT_MAP)
	_check_true("mapa %s lista biomas no bundle" % WorldRoot.DEFAULT_MAP, not of_map.is_empty(),
		"%d biomas" % of_map.size())
	if of_map.is_empty():
		return

	_check_true("bioma do mundo pertence ao mapa", of_map.has(WorldRoot.DEFAULT_BIOME),
		"%s em %s" % [WorldRoot.DEFAULT_BIOME, str(of_map)])

	_check_true("bioma do mundo tem taxas de mineracao",
		not db.biome_mining_weights(WorldRoot.DEFAULT_BIOME).is_empty(),
		"%d pesos" % db.biome_mining_weights(WorldRoot.DEFAULT_BIOME).size())

	var no_rates: Array = []
	for code in of_map:
		if db.biome_mining_weights(str(code)).is_empty():
			no_rates.append(code)
	_warn("biomas do mapa com taxas de mineracao", no_rates.is_empty(),
		"sem taxas: %s" % str(no_rates) if not no_rates.is_empty()
		else "%d de %d" % [of_map.size(), of_map.size()])


## Mesmo espírito de `_test_mining_contract`: `relics` é opcional em
## `load_bundle` (bundle antigo ainda sobe, só com o Relicário desligado), mas
## aqui é obrigatório — um export sem relics é um export velho, e é este teste
## que tem de dizer isso.
func _test_relics_contract(db: BestiaryData) -> void:
	print("contrato do relicario:")
	_check_true("bloco relics presente", db.has_relics(),
		"%d modelos" % db.relic_codes().size())
	if not db.has_relics():
		return

	var bad_element: Array = []
	var bad_class: Array = []
	var bad_stats: Array = []
	for code in db.relic_codes():
		var r := db.relic(code)
		# "" é o starter neutro (documento `relicario`) — ausência válida, não
		# referência quebrada. Só um código presente que não resolve a nada é
		# invalido.
		var element_code := BestiaryData.relic_element_code(r)
		if element_code != "" and db.element(element_code).is_empty():
			bad_element.append(code)
		var class_code := BestiaryData.relic_class_code(r)
		if class_code != "" and db.creature_class(class_code).is_empty():
			bad_class.append(code)
		# Campos numéricos achatados de relic_stats pelo exportador — ausência
		# de qualquer um significa relic sem a linha em relic_stats.
		for field in ["slotCapacity", "baseCaptureRate", "captureRatePerLevel", "maxLevel"]:
			if not r.has(field):
				bad_stats.append("%s.%s" % [code, field])
	_check("relics com elemento invalido", bad_element.size(), 0)
	_check("relics com classe invalida", bad_class.size(), 0)
	_check("relics sem stats completos", bad_stats.size(), 0)

	var rr := db.relic_rules()
	_check_true("relic_rules presente", not rr.is_empty())
	if not rr.is_empty():
		_check_true("captureFloorPct <= captureCeilPct",
			float(rr["captureFloorPct"]) <= float(rr["captureCeilPct"]),
			"%.1f / %.1f" % [float(rr["captureFloorPct"]), float(rr["captureCeilPct"])])

	# baseCaptureRate é o valor no nível 1 por definição — a curva não pode
	# somar incremento nenhum ali, senão o bug de (nível vs nível-1) voltou.
	var level1_ok := true
	for code in db.relic_codes():
		var r := db.relic(code)
		if db.relic_capture_rate_at_level(code, 1) != float(r["baseCaptureRate"]):
			level1_ok = false
	_check_true("taxa de captura no nivel 1 == baseCaptureRate", level1_ok)


## `RelicMath` é uma classe de fórmula pura, mesmo contrato de `CombatMath` —
## e por isso testada do mesmo jeito, aqui dentro, com o esperado derivado das
## regras do bundle em vez de números travados.
func _test_relic_math(db: BestiaryData) -> void:
	print("formula do relicario:")
	if not db.has_relics():
		print("  (pulado — bundle sem relics)")
		return

	# Nível 1 é a base pura; a curva só entra a partir do nível 2.
	_check("rate_at_level(80, 4, 1)", RelicMath.rate_at_level(80.0, 4.0, 1), 80.0)
	_check("rate_at_level(80, 4, 5)", RelicMath.rate_at_level(80.0, 4.0, 5), 96.0)

	_check("resistance(catchRate=200)", RelicMath.resistance(200), 56)
	_check("resistance(catchRate=1)", RelicMath.resistance(1), 255)

	var rr := db.relic_rules()
	# Precisa de um modelo *especializado* — o starter neutro (`RLC-000`, sem
	# elemento/classe) não serve pra testar bônus de mesmo elemento/classe ou
	# desvantagem, então pula ele em vez de assumir índice 0.
	var code := ""
	for candidate in db.relic_codes():
		var r := db.relic(candidate)
		if BestiaryData.relic_element_code(r) != "" and BestiaryData.relic_class_code(r) != "":
			code = candidate
			break
	if code == "":
		print("  (pulado — nenhum relic especializado no bundle)")
		return
	var relic := db.relic(code)
	var relic_element := BestiaryData.relic_element_code(relic)
	var relic_class := BestiaryData.relic_class_code(relic)
	var rate := db.relic_capture_rate_at_level(code, 1)

	# Criatura neutra: elemento e classe diferentes dos do relicário, sem
	# vantagem/desvantagem elemental — só o termo base entra.
	var other_element := "ELE-999"
	var other_class := "CLS-999"
	var neutral := RelicMath.capture_chance(db, rate, relic_element, relic_class, 128, other_element, other_class)
	var expected_base := clampf(
		(rate / float(RelicMath.resistance(128))) * 100.0,
		float(rr["captureFloorPct"]), float(rr["captureCeilPct"])) / 100.0
	_check_true("caso neutro bate com base% clampado",
		absf(neutral - expected_base) < 0.0001,
		"%.4f vs %.4f" % [neutral, expected_base])

	# Mesmo elemento soma o bônus — chance sobe (a menos que já estivesse no teto).
	var same_element := RelicMath.capture_chance(db, rate, relic_element, relic_class, 128, relic_element, other_class)
	_check_true("mesmo elemento nao reduz a chance", same_element >= neutral,
		"%.4f vs %.4f" % [same_element, neutral])

	# Mesma classe soma o bônus.
	var same_class := RelicMath.capture_chance(db, rate, relic_element, relic_class, 128, other_element, relic_class)
	_check_true("mesma classe nao reduz a chance", same_class >= neutral,
		"%.4f vs %.4f" % [same_class, neutral])

	# Desvantagem elemental: acha o elemento que bate o do relicário (mesmo
	# oráculo que `RelicMath.capture_chance` usa por dentro, via
	# `element_multiplier`) e confirma que a penalidade reduz a chance.
	var disadvantage_element := ""
	for candidate in ["ELE-001", "ELE-002", "ELE-003", "ELE-004", "ELE-005", "ELE-006"]:
		if db.element_multiplier(relic_element, candidate) < 1.0:
			disadvantage_element = candidate
			break
	if disadvantage_element != "":
		var disadvantaged := RelicMath.capture_chance(
			db, rate, relic_element, relic_class, 128, disadvantage_element, other_class)
		_check_true("desvantagem elemental reduz a chance", disadvantaged <= neutral,
			"%.4f vs %.4f" % [disadvantaged, neutral])

	# Floor/ceil seguram os dois extremos.
	var near_impossible := RelicMath.capture_chance(db, 0.01, relic_element, relic_class, 255, other_element, other_class)
	var near_certain := RelicMath.capture_chance(db, 100000.0, relic_element, relic_class, 1, other_element, other_class)
	_check("piso respeitado", near_impossible, float(rr["captureFloorPct"]) / 100.0)
	_check("teto respeitado", near_certain, float(rr["captureCeilPct"]) / 100.0)
