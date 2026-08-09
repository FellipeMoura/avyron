class_name MiningTable
extends RefCounted

## A fórmula de mineração. Substitui a antiga `OreTable`, que carregava cinco
## minérios inventados em constante — nada disso é decidido aqui agora.
##
##     chance(mineral) = normalizar(peso_classe × peso_bioma)
##
## Os dois pesos vêm do bundle (`mining.rates`). O **bioma** diz o que o chão
## tem; a **classe da criatura ativa** diz o que ela sabe achar. Multiplicar é
## o que faz trocar a criatura ativa mudar de verdade o que sai da picareta —
## um Draconis prospecta prata e cristal onde um Loricati tira âmbar.
##
## Ninguém guarda a distribuição em cache. São doze minerais: recalcular custa
## menos que uma linha de log, e o preço de cachear seria invalidar em toda
## troca de ativa, de bioma ou de mapa — três chances de servir uma tabela
## velha em troca de nada.
##
## Especificação: `mineracao` no bestiário. Tuning: `POST /mining-rates`.

## Tradução dos papéis de trabalho do `workFunction`. Enum em inglês no banco,
## português na tela — a mesma regra que `labels.ts` aplica do lado do web.
const ROLE_LABELS := {
	"excavator": "escavadora",
	"burrower": "tuneladora",
	"prospector": "prospectora",
}


## Distribuição normalizada do par (classe, bioma), ordenada da maior chance
## para a menor. Cada entrada é `{code, name, chance}`, com `chance` somando 1.
##
## Devolve vazio quando não há dado dos dois lados — o chamador trata isso como
## "não dá para minerar aqui" em vez de sortear de uma tabela imaginária.
static func distribution(db: BestiaryData, class_code: String, biome_code: String) -> Array:
	if db == null:
		return []

	var class_weights := db.class_mining_weights(class_code)
	var biome_weights := db.biome_mining_weights(biome_code)
	if class_weights.is_empty() and biome_weights.is_empty():
		return []

	# União dos dois lados: um mineral que só um deles lista ainda é candidato.
	var codes := {}
	for code in class_weights:
		codes[code] = true
	for code in biome_weights:
		codes[code] = true

	var raw := {}
	var total := 0.0
	for code: String in codes:
		# Lado **ausente por inteiro** é neutro (×1), lado presente mas sem o
		# mineral é zero. A diferença importa: sem criatura ativa o bioma
		# decide sozinho, mas uma classe que não lista prata não acha prata.
		var cw := _weight_of(class_weights, code)
		var bw := _weight_of(biome_weights, code)
		var w := cw * bw
		if w <= 0.0:
			continue
		raw[code] = w
		total += w

	if total <= 0.0:
		return []

	var out: Array = []
	for code: String in raw:
		out.append({
			"code": code,
			"name": db.mineral_name(code),
			"chance": float(raw[code]) / total,
		})
	out.sort_custom(func(a, b): return float(a["chance"]) > float(b["chance"]))
	return out


static func _weight_of(weights: Dictionary, code: String) -> float:
	if weights.is_empty():
		return 1.0
	return float(weights.get(code, 0.0))


## Sorteia um mineral da distribuição do par (classe, bioma).
## Devolve `{code, name, chance}`, ou vazio se não houver o que minerar.
static func sample(rng: RandomNumberGenerator, db: BestiaryData, class_code: String, biome_code: String) -> Dictionary:
	var dist := distribution(db, class_code, biome_code)
	if dist.is_empty():
		return {}

	var roll := rng.randf()
	var acc := 0.0
	for entry in dist:
		acc += float(entry["chance"])
		if roll < acc:
			return entry
	# Resíduo de ponto flutuante: a soma pode fechar em 0.9999999 e deixar um
	# roll altíssimo escapar do laço. Cair na última entrada é o certo.
	return dist[-1]


## Quanto a classe acelera a mineração. 1.0 é neutro; Theria escava a 1.1,
## Draconis a 0.9. Vira divisor do cooldown no `WorldRoot`.
static func speed_modifier(db: BestiaryData, class_code: String) -> float:
	if db == null:
		return 1.0
	var value: Variant = db.class_work_function(class_code).get("speedModifier", null)
	if value == null:
		return 1.0
	var modifier := float(value)
	# Um zero ou negativo vindo do banco dividiria o cooldown por zero. Melhor
	# minerar em ritmo neutro do que travar o jogo por um PATCH errado.
	return modifier if modifier > 0.0 else 1.0


## Papel de trabalho da classe já traduzido, ou "" quando não há perfil.
static func role_label(db: BestiaryData, class_code: String) -> String:
	if db == null:
		return ""
	var role := str(db.class_work_function(class_code).get("role", ""))
	if role == "":
		return ""
	return str(ROLE_LABELS.get(role, role))


## Os `count` minerais mais prováveis para o par (classe, bioma), só os nomes.
##
## `workFunction.preferredOres` existe no bundle, mas com chaves semânticas
## (`fossilAmber`, `elementalCrystal`) que não são códigos `ITM-*`. Traduzir
## essas chaves exigiria um mapa hardcoded — exatamente o que a migração para
## dado veio matar. Os pesos já dizem a mesma coisa, e dizem em números.
static func preferred_names(db: BestiaryData, class_code: String, biome_code: String, count: int = 3) -> Array[String]:
	var out: Array[String] = []
	for entry in distribution(db, class_code, biome_code):
		if out.size() >= count:
			break
		out.append(str(entry["name"]))
	return out
