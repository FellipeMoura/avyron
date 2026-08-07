class_name BestiaryData
extends Node

## Carrega e indexa data/bestiary.json — o bundle exportado do bestiário.
##
## Registrado como autoload `Bestiary`, mas também instanciável direto, o que
## permite testar sem subir a árvore de cena inteira.
##
## Tudo é endereçado por código (`CRT-001`, `HAB-014`, `ELE-002`). Nenhum id
## numérico atravessa a fronteira entre os dois repositórios, então o bundle
## sobrevive a uma reconstrução do banco.
##
## NUNCA edite data/bestiary.json à mão: ele é gerado, e a próxima exportação
## sobrescreve. Corrija no bestiário via API e re-exporte.

const BUNDLE_PATH := "res://data/bestiary.json"

## Versão do changelog de onde este bundle saiu. É o que torna um build
## rastreável até o estado exato do catálogo.
var data_version: String = ""
var source: String = ""
var rules: Dictionary = {}

var _creatures: Dictionary = {}   # code -> Dictionary
var _abilities: Dictionary = {}   # code -> Dictionary
var _elements: Dictionary = {}    # code -> Dictionary
var _classes: Dictionary = {}     # code -> Dictionary
var _maps: Dictionary = {}        # code -> Dictionary
var _biomes: Dictionary = {}      # code -> Dictionary
var _advantages: Array = []

var _loaded := false


func _ready() -> void:
	if _loaded:
		return
	var err := load_bundle()
	if err != "":
		push_error("Bestiary: " + err)
		return
	# Logar a versão no boot faz um relatório de bug dizer contra quais dados
	# o build rodou, sem precisar adivinhar.
	print("Bestiary: dataVersion %s (%d criaturas, %d habilidades) de %s"
		% [data_version, creature_count(), ability_count(), source])


## Devolve "" em sucesso, ou a mensagem do erro. Falhar aqui é fatal para o
## jogo — sem dados não há criatura, golpe nem batalha —, então a chamadora
## deve tratar o retorno em vez de seguir com o bundle vazio.
func load_bundle(path: String = BUNDLE_PATH) -> String:
	if not FileAccess.file_exists(path):
		return "bundle nao encontrado em %s — rode `pnpm game:export` no repo do bestiario" % path

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return "bundle vazio em %s" % path

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return "bundle em %s nao e um objeto JSON valido" % path

	var bundle: Dictionary = parsed

	data_version = str(bundle.get("dataVersion", ""))
	source = str(bundle.get("source", ""))
	rules = bundle.get("rules", {})
	_advantages = bundle.get("elementalAdvantages", [])

	_creatures = _index_by_code(bundle.get("creatures", []))
	_abilities = _index_by_code(bundle.get("abilities", []))
	_elements = _index_by_code(bundle.get("elements", []))
	_classes = _index_by_code(bundle.get("classes", []))
	_maps = _index_by_code(bundle.get("maps", []))
	_biomes = _index_by_code(bundle.get("biomes", []))

	if _creatures.is_empty():
		return "bundle sem criaturas — export incompleto"
	if rules.is_empty():
		return "bundle sem o bloco `rules` — export de uma versao antiga do script"

	_loaded = true
	return ""


func _index_by_code(rows: Array) -> Dictionary:
	var out := {}
	for row in rows:
		out[str(row["code"])] = row
	return out


# ---------------------------------------------------------------------------
# consultas
# ---------------------------------------------------------------------------

func creature(code: String) -> Dictionary:
	return _creatures.get(code, {})

func ability(code: String) -> Dictionary:
	return _abilities.get(code, {})

func element(code: String) -> Dictionary:
	return _elements.get(code, {})

func creature_class(code: String) -> Dictionary:
	return _classes.get(code, {})

func game_map(code: String) -> Dictionary:
	return _maps.get(code, {})

func biome(code: String) -> Dictionary:
	return _biomes.get(code, {})

func creature_codes() -> Array:
	return _creatures.keys()

func creature_count() -> int:
	return _creatures.size()

func ability_count() -> int:
	return _abilities.size()


## Criaturas de um mapa. Útil para montar a tabela de encontros do bioma.
func creatures_in_map(map_code: String) -> Array:
	var out := []
	for code in _creatures:
		if _creatures[code].get("map", null) == map_code:
			out.append(_creatures[code])
	return out


## Golpes que a criatura já conhece no nível dado, em ordem de apresentação.
##
## A assinatura do Despertar aparece aqui desde o nível 1 porque ela é travada
## pela transformação estar ativa, não pelo nível — filtrar por
## `awakeningOnly` é responsabilidade do sistema de batalha.
func known_abilities(creature_code: String, level: int) -> Array:
	var c := creature(creature_code)
	if c.is_empty():
		return []

	var out := []
	for entry in c.get("abilities", []):
		if int(entry["learnLevel"]) <= level:
			var a := ability(str(entry["code"]))
			if not a.is_empty():
				out.append(a)
	return out


# ---------------------------------------------------------------------------
# atalhos que combinam dados + fórmulas
# ---------------------------------------------------------------------------

## Os cinco stats efetivos da criatura no nível dado.
## Dicionário vazio se a criatura não existe ou está sem stats — o que o
## export já deveria ter impedido de acontecer.
func stats_at_level(creature_code: String, level: int) -> Dictionary:
	var c := creature(creature_code)
	if c.is_empty():
		return {}
	var s: Variant = c.get("stats", null)
	if s == null:
		return {}

	var growth := float(s["growthRate"])
	return {
		"hp": CombatMath.stat_at_level(int(s["hp"]), growth, level),
		"attack": CombatMath.stat_at_level(int(s["attack"]), growth, level),
		"defense": CombatMath.stat_at_level(int(s["defense"]), growth, level),
		"speed": CombatMath.stat_at_level(int(s["speed"]), growth, level),
		"charge": CombatMath.stat_at_level(int(s["charge"]), growth, level),
	}


## Código do elemento de uma habilidade, ou "" quando ela não tem afinidade.
##
## Existe porque `str(null)` em GDScript devolve a string "<null>", e não
## vazio. Golpes utilitários como Bote têm `element: null` no bundle, então
## `str(a.get("element", ""))` produzia "<null>" — que passava em qualquer
## teste de `!= ""` e ia parar na tela e na busca de multiplicador. O dano
## saía certo por acidente (o código inexistente não casa com nenhum par e
## cai no neutro), mas era coincidência, não lógica.
static func ability_element(ability: Dictionary) -> String:
	var value: Variant = ability.get("element", null)
	return "" if value == null else str(value)


func element_multiplier(attacker_element: String, defender_element: String) -> float:
	return CombatMath.element_multiplier(attacker_element, defender_element, _advantages, rules)


## Multiplicador de Ataque e Defesa durante o Despertar Ancestral.
## 1.5 para despertares de reforço, 1.7 para os de troca.
func awakening_multiplier(creature_code: String) -> float:
	var c := creature(creature_code)
	if c.is_empty() or c.get("stats", null) == null:
		return 1.0
	return float(c["stats"]["awakeningMultiplier"])
