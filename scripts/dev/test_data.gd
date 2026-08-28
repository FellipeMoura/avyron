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
	_test_class_contract(db)
	_test_class_bonus(db)
	_test_palette_contract(db)
	_test_mining_contract(db)
	_test_biome_contract(db)
	_test_biome_partition(db)
	_test_progression_contract(db)
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

	# `stats_at_level` devolve o valor JÁ com o bônus da classe, e o esperado
	# é derivado dos dois lados em vez de fixado num número: travar "85" aqui
	# foi o que quebrou quando a classe passou a especializar um stat, e
	# travar "102" só adiaria o mesmo problema para o próximo tuning.
	var base := int(db.creature("CRT-021")["stats"]["attack"])
	var class_code := str(db.creature("CRT-021").get("class", ""))
	var pct := db.class_primary_stat_bonus_pct(class_code) \
		if db.class_primary_stat(class_code) == "attack" else 0.0

	var lv1 := db.stats_at_level("CRT-021", 1)
	var lv50 := db.stats_at_level("CRT-021", 50)
	# Nível 1 zera a curva, então o que sobra é a base mais o bônus da classe.
	_check("CRT-021 ataque nivel 1", lv1["attack"], CombatMath.stat_with_class_bonus(base, pct))
	_check_true("stats crescem com o nivel",
		lv50["attack"] > lv1["attack"] and lv50["hp"] > lv1["hp"],
		"atk %d -> %d" % [lv1["attack"], lv50["attack"]])


## O anel elemental, verificado pela FORMA e não por uma lista escrita à mão.
##
## A lista existia — `["ELE-002", "ELE-001", ...]` — e envelheceu na primeira
## vez que o anel mudou de tamanho: com Gelo removido em 2026-08 ela apontava
## para um elemento que não existe mais, e `element_multiplier` devolvia
## neutro para um par inexistente sem reclamar de nada. O teste teria passado
## por acidente se o par vizinho também tivesse sumido.
##
## O que importa guardar não é QUAIS elementos estão no ciclo — isso é
## conteúdo, e o catálogo decide — mas que o grafo de "vence" seja **um único
## ciclo que passa por todos**. Essa é a simetria que faz nenhum elemento ser
## objetivamente melhor, e ela é derivável.
func _test_element_ring(db: BestiaryData) -> void:
	print("anel elemental:")

	var codes := db.element_codes()
	_check_true("tem elementos", codes.size() >= 3, "%d" % codes.size())

	# Quem cada elemento vence, e quem ele perde. Um elemento com dois de
	# qualquer um dos lados já não é um anel — é uma teia.
	var beats := {}
	var multi: Array[String] = []
	for atk: String in codes:
		var won: Array[String] = []
		var lost: Array[String] = []
		for def: String in codes:
			if atk == def:
				continue
			var m := db.element_multiplier(atk, def)
			if m == 2.0:
				won.append(def)
			elif m == 0.5:
				lost.append(def)
		if won.size() != 1 or lost.size() != 1:
			multi.append("%s vence %d e perde para %d" % [atk, won.size(), lost.size()])
		if won.size() == 1:
			beats[atk] = won[0]
	_check("elementos fora do padrao um-vence-um-perde", multi.size(), 0)

	# Vantagem e desvantagem são o MESMO par lido dos dois lados: se A vence B
	# com 2.0, B tem de perder para A com 0.5. Metade da tabela declarada sem
	# a outra metade daria um elemento que ganha de graça.
	var asymmetric: Array[String] = []
	for atk: String in beats:
		var def: String = beats[atk]
		if db.element_multiplier(def, atk) != 0.5:
			asymmetric.append("%s > %s sem a volta" % [atk, def])
	_check("pares sem a contrapartida 0.5", asymmetric.size(), 0)

	# Um único ciclo cobrindo todos: seguir "vence" a partir de qualquer um
	# tem de visitar cada elemento exatamente uma vez e voltar ao início.
	# Dois ciclos separados passariam nas duas checagens acima e ainda assim
	# partiriam o jogo em duas metades que nunca se enfrentam.
	var start: String = codes[0]
	var walk: Array[String] = []
	var cursor: String = start
	for _i in codes.size():
		walk.append(cursor)
		if not beats.has(cursor):
			break
		cursor = str(beats[cursor])
	_check("elementos visitados pelo ciclo", walk.size(), codes.size())
	_check_true("o ciclo fecha em si mesmo", cursor == start,
		" -> ".join(walk) + " -> " + cursor)

	# Par fora do anel é neutro por omissão, e é a omissão que mantém a tabela
	# pequena: 5 elementos declaram 10 linhas, não 25.
	var neutral_ok := true
	for atk: String in codes:
		for def: String in codes:
			if atk == def or str(beats.get(atk, "")) == def or str(beats.get(def, "")) == atk:
				continue
			if db.element_multiplier(atk, def) != 1.0:
				neutral_ok = false
	_check_true("par fora do anel e neutro por omissao", neutral_ok)

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


## O contrato da classe como **especialização de atributo**.
##
## Até 2026-08 classe era linhagem: CLS-001 era "artrópodes" e uma criatura
## que não coubesse em nenhuma das três não entrava no jogo. O elenco abriu
## para cinco e a classe passou a dizer qual dos cinco stats a criatura
## especializa — taxonomia continua existindo na biologia e deixou de existir
## no dado.
##
## Isso move a classe de descritiva para executável, e é por isso que estas
## checagens são `_check` e não `_warn`: `stats_at_level` multiplica um stat
## por causa delas, e um furo aqui entrega a criatura com o número de outra
## sem sintoma nenhum.
func _test_class_contract(db: BestiaryData) -> void:
	print("contrato das classes:")

	# Invariante 1 — o elenco é fechado em cinco. Diferente das contagens de
	# criatura e golpe (que crescem com o catálogo e por isso só são testadas
	# como "> 0"), esta é uma decisão de design travada: uma sexta classe é
	# uma mudança que precisa passar por aqui de propósito.
	var codes := db.class_codes()
	codes.sort()
	_check("quantidade de classes", codes.size(), 5)
	_check("codigos do elenco", str(codes),
		str(["CLS-001", "CLS-002", "CLS-003", "CLS-004", "CLS-005"]))

	# Invariante 2 — cada classe especializa exatamente um dos cinco stats que
	# `stats_at_level` devolve. Um token fora dessa lista seria um bônus
	# aplicado a uma chave que não existe: perdido, e calado.
	var valid := ["hp", "attack", "defense", "speed", "charge"]
	var bad_stat: Array = []
	var bad_bonus: Array = []
	for class_code: String in codes:
		var stat := db.class_primary_stat(class_code)
		if not valid.has(stat):
			bad_stat.append("%s (%s)" % [class_code, stat if stat != "" else "vazio"])
		var pct := db.class_primary_stat_bonus_pct(class_code)
		if pct <= 0.0:
			bad_bonus.append("%s (%.2f)" % [class_code, pct])
	_check("classes com primaryStat invalido", bad_stat.size(), 0)
	_check("classes sem modificador", bad_bonus.size(), 0)

	# Invariante 3 — toda criatura tem exatamente uma classe, e ela existe.
	# `creature.class` é string única no bundle, então "exatamente uma" é
	# forma; o que dá para furar é apontar para código que não existe.
	var no_class: Array = []
	for code in db.creature_codes():
		var class_code := str(db.creature(str(code)).get("class", ""))
		if class_code == "" or db.creature_class(class_code).is_empty():
			no_class.append("%s (%s)" % [str(code), class_code])
	_check("criaturas sem classe valida", no_class.size(), 0)

	# Invariante 4 — nada no dado amarra classe a linhagem. O campo que fazia
	# isso era `biologicalScope`, e ele saiu do bundle junto com a coluna.
	# Testar a ausência dele é testar que nenhum código do jogo *poderia*
	# validar classe por taxonomia, que é mais forte do que testar que
	# nenhum código faz isso hoje.
	var taxonomic: Array = []
	for class_code: String in codes:
		for key in ["biologicalScope", "lineage", "taxon", "clade"]:
			if db.creature_class(class_code).has(key):
				taxonomic.append("%s.%s" % [class_code, key])
	_check("campos de taxonomia no bloco de classes", taxonomic.size(), 0)

	# Invariante 7 — não existe vantagem de classe contra classe. Duas formas
	# de furar: um bloco de pares no bundle (espelho de `elementalAdvantages`)
	# ou uma classe referenciando outra em algum campo próprio. As duas ficam
	# fechadas aqui, porque a primeira vez que alguém tentar vai ser por uma
	# delas.
	# O bundle cru, lido aqui e não guardado por `BestiaryData`: o índice em
	# memória é o que o jogo usa, e manter o JSON inteiro vivo só para um
	# teste seria pagar memória em runtime por uma checagem de bancada.
	var bundle: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(BestiaryData.BUNDLE_PATH))
	var top_keys: Array = (bundle as Dictionary).keys() if bundle is Dictionary else []
	var advantage_blocks: Array = []
	for key: String in top_keys:
		if key != "elementalAdvantages" and key.to_lower().contains("advantage"):
			advantage_blocks.append(key)
	_check("blocos de vantagem alem do elemental", advantage_blocks.size(), 0)
	var cross: Array = []
	for class_code: String in codes:
		var entry := db.creature_class(class_code)
		for key: String in entry:
			var value := str(entry[key])
			for other: String in codes:
				if other != class_code and value.contains(other):
					cross.append("%s.%s -> %s" % [class_code, key, other])
	_check("classes referenciando outra classe", cross.size(), 0)
	print("")


## Invariantes 5 e 6: o bônus atinge SÓ o `primaryStat`, e o número vem do
## bundle.
##
## As duas juntas são o ponto inteiro da mudança. Uma classe que engrossasse
## os cinco stats seria um buff global disfarçado de especialização; e um
## `1.20` escrito em GDScript seria a regra 1 deste repo quebrada no lugar
## mais caro de descobrir, porque só apareceria como "o PATCH não fez efeito".
func _test_class_bonus(db: BestiaryData) -> void:
	print("bonus da classe:")

	var stats := ["hp", "attack", "defense", "speed", "charge"]
	var checked := 0
	for code in db.creature_codes():
		var creature_code := str(code)
		var c := db.creature(creature_code)
		if c.get("stats", null) == null:
			continue
		var class_code := str(c.get("class", ""))
		var boosted := db.class_primary_stat(class_code)
		if boosted == "":
			continue

		var pct := db.class_primary_stat_bonus_pct(class_code)
		var raw: Dictionary = c["stats"]
		var growth := float(raw["growthRate"])
		var final := db.stats_at_level(creature_code, 1)

		# Nível 1 zera a curva (`1 + growth * 0`), então o que sobra na
		# diferença entre a base do bundle e o valor final é exatamente o
		# bônus da classe — e mais nada.
		var wrong: Array = []
		for stat: String in stats:
			var base := CombatMath.stat_at_level(int(raw[stat]), growth, 1)
			var expected := CombatMath.stat_with_class_bonus(base, pct) if stat == boosted else base
			if int(final[stat]) != expected:
				wrong.append("%s: %d != %d" % [stat, int(final[stat]), expected])
		if not wrong.is_empty():
			_check_true("%s: bonus so no %s" % [creature_code, boosted], false, str(wrong))
			return
		checked += 1

	_check_true("bonus atinge so o primaryStat de cada criatura", checked > 0,
		"%d criaturas conferidas" % checked)

	# Invariante 6: o número é parâmetro, não constante. Se `1.20` estivesse
	# escrito na fórmula, os três resultados abaixo seriam iguais — e é
	# exatamente assim que um valor hardcoded passa despercebido, porque o
	# caso de 20% continuaria certo.
	_check("bonus de 0% nao muda nada", CombatMath.stat_with_class_bonus(100, 0.0), 100)
	_check("bonus de 20% sobre 100", CombatMath.stat_with_class_bonus(100, 20.0), 120)
	_check("bonus de 50% sobre 100", CombatMath.stat_with_class_bonus(100, 50.0), 150)

	# E o valor real vem do catálogo: se o bestiário mudar os 20% para 25, é
	# esta leitura que muda, sem tocar em GDScript.
	var sample := str(db.class_codes()[0])
	_check_true("modificador de %s vem do bundle" % sample,
		db.class_primary_stat_bonus_pct(sample) > 0.0,
		"%.1f%%" % db.class_primary_stat_bonus_pct(sample))
	print("")


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

	# Nomeia os biomas em vez de listar códigos: é a única leitura de
	# `db.biome()` no jogo, e é ela que mantém o array `biomes` do bundle
	# sendo consumido por alguém em vez de exportado no vazio.
	var no_rates: Array = []
	for code in of_map:
		if db.biome_mining_weights(str(code)).is_empty():
			var b := db.biome(str(code))
			no_rates.append("%s (%s)" % [str(code), str(b.get("name", "?"))])
	_warn("biomas do mapa com taxas de mineracao", no_rates.is_empty(),
		"sem taxas: %s" % str(no_rates) if not no_rates.is_empty()
		else "%d de %d" % [of_map.size(), of_map.size()])


## A partição espacial de bioma: a tradução de ±1 para metros, e a promessa
## de cobertura total.
##
## Esta suíte existe por causa de uma armadilha específica. As regiões do
## catálogo vêm em coordenadas NORMALIZADAS, e as notas delas amarram os
## números a constantes daqui — a nota da RGN-001 diz, com todas as letras,
## que `-0.533` é o `COAST_RAMP_START` sobre o meio-lado de 30 m. Nada obriga
## as duas pontas a continuarem de acordo: mexer no `COAST_RAMP_START` sem
## reautorar a região faz a fronteira do bioma descolar da rampa do terreno, e
## o sintoma é o jogador subindo para o seco e a mineração ainda respondendo
## "mar raso" — plausível, silencioso e caro de rastrear meses depois.
##
## Por isso o teste MEDE a fronteira em vez de conferir o número: varre o eixo
## e pergunta onde o bioma troca. É o mesmo raciocínio do teste de direção da
## câmera — provar a aritmética que o olho não pega.
func _test_biome_partition(db: BestiaryData) -> void:
	print("particao de bioma:")

	var half := float(MapTerrain.SIZE) * 0.5
	var mb := MapBiomes.create(db, WorldRoot.DEFAULT_MAP, half)

	_check_true("mapa %s tem particao no bundle" % WorldRoot.DEFAULT_MAP,
		mb.has_partition(), "%d regioes" % mb.region_count())
	if not mb.has_partition():
		return

	# Cobertura total é a promessa do catch-all, e é invariante: sem ela, um
	# ponto do mapa não responde bioma nenhum e a mineração cai no fallback
	# declarado — a fórmula troca de perfil sem nada acusar.
	var cov: Dictionary = mb.coverage_report(1.0)
	_check_true("particao cobre o mapa inteiro", int(cov["uncovered"]) == 0,
		"%d de %d pontos sem bioma%s" % [int(cov["uncovered"]), int(cov["total"]),
			(" — ex.: %s" % str(cov["worst"])) if int(cov["uncovered"]) > 0 else ""])

	# A medição, na LINHA DE CENTRO do lobo: onde, em metros, a costa deixa de
	# responder? Desde que a costa virou lobo, x = 0 não serve — o centro dela
	# está deslocado, e medir fora do eixo daria um alcance menor que o real
	# pela geometria do círculo, não por divergência nenhuma.
	var cx := MapTerrain.COAST_CENTER_X
	var coast := str(mb.biome_at(Vector3(cx, 0.0, -half + 1.0)))
	var boundary := -half
	var z := -half + 1.0
	while z <= 0.0:
		if str(mb.biome_at(Vector3(cx, 0.0, z))) == coast:
			boundary = z
		z += 0.05
	_check_true("fronteira da costa bate com a rampa do terreno",
		absf(boundary - MapTerrain.COAST_RAMP_START) <= 0.25,
		"regiao troca em z=%.2f, COAST_RAMP_START=%.2f" % [boundary, MapTerrain.COAST_RAMP_START])

	# O miolo é o recife, e é a região específica se sobrepondo ao catch-all —
	# se a ordem de avaliação inverter, o centro passa a responder mar aberto.
	_check_true("o miolo responde uma regiao especifica, nao o catch-all",
		str(mb.biome_at(Vector3.ZERO)) != str(mb.biome_at(Vector3(0.0, 0.0, half - 1.0))),
		"centro=%s, borda=%s" % [str(mb.biome_at(Vector3.ZERO)),
			str(mb.biome_at(Vector3(0.0, 0.0, half - 1.0)))])

	# Alcançável passou a ser a lista que importa: com a partição ligada, o
	# jogador pisa em qualquer um destes, e bioma sem taxa derruba a fórmula
	# para só-classe em silêncio — o furo que a auditoria de 2026-08 fechou
	# para UM bioma e que a partição reabre para todos.
	var reachable := mb.reachable_biomes()
	var no_rates: Array = []
	for code in reachable:
		if db.biome_mining_weights(str(code)).is_empty():
			no_rates.append(str(code))
	_check_true("todo bioma alcancavel tem taxas de mineracao", no_rates.is_empty(),
		"sem taxas: %s" % str(no_rates) if not no_rates.is_empty()
		else "%d alcancaveis" % reachable.size())

	# Alvo, não erro: o bioma existe e é bom, só não tem onde ficar ainda.
	var unreachable := mb.unreachable_biomes()
	var named: Array = []
	for code in unreachable:
		named.append("%s (%s)" % [str(code), str(db.biome(str(code)).get("name", "?"))])
	_warn("todo bioma do mapa e alcancavel", unreachable.is_empty(),
		"sem regiao: %s" % str(named) if not unreachable.is_empty()
		else "%d de %d" % [reachable.size(), reachable.size()])


## Progressão entre mapas: arena, Glifo e travessia (documento
## `glifos-e-portais`).
##
## Espelha os critérios do export, com a mesma divisão de portas. São erro:
## duelista sem bloco `duel` (a arena não teria contra quem encenar) e
## travessia exigindo Glifo que arena nenhuma concede — esta última é a que
## trava a campanha em silêncio, porque o guardião simplesmente nunca deixa
## passar e nada reporta.
##
## É alvo, não erro: Glifo concedido que travessia nenhuma exige. Enquanto a
## era seguinte não tiver mapa, é exatamente onde Daleth está.
func _test_progression_contract(db: BestiaryData) -> void:
	print("contrato de progressao:")

	var granted: Dictionary = {}
	for code in db.duelist_codes():
		var d := db.duelist(str(code))
		var duel: Variant = d.get("duel")
		_check_true("duelista %s traz o bloco duel" % str(code), duel is Dictionary,
			str(duel))
		if not (duel is Dictionary):
			continue
		var opponent := str((duel as Dictionary).get("opponentCode", ""))
		_check_true("oponente de %s existe no elenco" % str(code),
			not db.creature(opponent).is_empty(), opponent)
		_check_true("nivel do oponente de %s dentro do teto" % str(code),
			int((duel as Dictionary).get("opponentLevel", 0)) <= db.level_cap(),
			"%d / %d" % [int((duel as Dictionary).get("opponentLevel", 0)), db.level_cap()])
		var glyph: Variant = (duel as Dictionary).get("grantsGlyph")
		if glyph != null and str(glyph) != "":
			granted[str(glyph)] = str(code)
			_check_true("Glifo %s concedido por %s tem nome no catalogo"
				% [str(glyph), str(code)],
				db.glyph_name(str(glyph)) != str(glyph), db.glyph_name(str(glyph)))

	# Travessia exigente sem quem conceda o Glifo é beco sem saída.
	var required: Dictionary = {}
	for map_code in db.map_codes():
		for link in db.connections_from_map(str(map_code)):
			if not (link is Dictionary):
				continue
			var need: Variant = (link as Dictionary).get("requiredGlyph")
			if need == null or str(need) == "":
				continue
			required[str(need)] = "%s -> %s" % [str(map_code), str((link as Dictionary).get("to", "?"))]
			_check_true("travessia %s exige Glifo que alguma arena concede"
				% required[str(need)], granted.has(str(need)), str(need))

	var unused: Array = []
	for glyph_code in granted:
		if not required.has(glyph_code):
			unused.append("%s (%s)" % [str(glyph_code), str(granted[glyph_code])])
	_warn("todo Glifo concedido abre alguma travessia", unused.is_empty(),
		"sem travessia: %s" % str(unused) if not unused.is_empty() else "%d Glifo(s)" % granted.size())


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
	# A lista sai do bundle, não de códigos escritos aqui: uma lista fixa
	# sobrevive a um elemento ser removido do catálogo sem falhar — só para de
	# achar o par, e a checagem inteira some em silêncio dentro do `if` abaixo.
	var disadvantage_element := ""
	for candidate: String in db.element_codes():
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
