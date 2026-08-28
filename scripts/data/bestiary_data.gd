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
var _glyphs: Dictionary = {}      # code -> Dictionary
var _advantages: Array = []

## Bloco `mining` do bundle, desmontado em três índices.
##
## As taxas chegam numa lista plana onde cada linha tem OU `classCode` OU
## `biomeCode` — nunca os dois. Indexar por lado separado é o que permite a
## fórmula multiplicar um pelo outro sem varrer a lista a cada mineração.
var _minerals: Dictionary = {}      # code -> Dictionary
var _class_mining: Dictionary = {}  # classCode -> {itemCode: float}
var _biome_mining: Dictionary = {}  # biomeCode -> {itemCode: float}

## Catálogo completo de itens, com preço e efeito executável. `_minerals` é a
## fatia minerável disto — o sorteio da picareta vem de lá, preço e efeito
## vêm daqui.
var _items: Dictionary = {}         # code -> Dictionary
var _merchants: Dictionary = {}     # code -> Dictionary
var _duelists: Dictionary = {}      # code -> Dictionary

## Modelos de Relicário — código -> Dictionary já achatado com `relic_stats`
## pelo exportador (elemento, classe, slotCapacity, curva de captura).
var _relics: Dictionary = {}        # code -> Dictionary
var _equipment: Dictionary = {}     # code -> Dictionary (modelo + numeros + receita)

## Constantes da economia: nome da moeda, bolsa inicial, margem do comerciante.
var economy: Dictionary = {}

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
	_glyphs = _index_by_code(bundle.get("glyphs", []))
	_index_mining(bundle.get("mining", null))
	_items = _index_by_code(bundle.get("items", []))
	_merchants = _index_by_code(bundle.get("merchants", []))
	_duelists = _index_by_code(bundle.get("duelists", []))
	_relics = _index_by_code(bundle.get("relics", []))
	_equipment = _index_by_code(bundle.get("equipment", []))
	economy = bundle.get("economy", {})

	if _creatures.is_empty():
		return "bundle sem criaturas — export incompleto"
	if rules.is_empty():
		return "bundle sem o bloco `rules` — export de uma versao antiga do script"
	# Ausência de mineração não é fatal: combate e exploração seguem de pé, e
	# quem falha alto por isso é `test_data.gd`, que é o guarda do contrato.
	# Em runtime o aviso basta para o dev saber que exportou de um bestiário
	# anterior ao módulo de mineração.
	if _minerals.is_empty():
		push_warning("Bestiary: bundle sem o bloco `mining` — mineracao desligada. Re-exporte.")
	# Mesmo raciocínio: bundle anterior ao módulo de Relicário não deve travar
	# o jogo, só desligar captura/storage até re-exportar.
	if _relics.is_empty():
		push_warning("Bestiary: bundle sem o bloco `relics` — Relicário desligado. Re-exporte.")
	# Idem para o resto do set: sem o bloco, a bancada abre vazia e o jogador
	# joga sem Amplificador/Encantador — que é exatamente o estado do jogo
	# antes deste módulo, não uma falha nova.
	if _equipment.is_empty():
		push_warning("Bestiary: bundle sem o bloco `equipment` — bancada vazia. Re-exporte.")

	_loaded = true
	return ""


func _index_by_code(rows: Array) -> Dictionary:
	var out := {}
	for row in rows:
		out[str(row["code"])] = row
	return out


func _index_mining(mining: Variant) -> void:
	_minerals = {}
	_class_mining = {}
	_biome_mining = {}
	if typeof(mining) != TYPE_DICTIONARY:
		return

	var block: Dictionary = mining
	_minerals = _index_by_code(block.get("items", []))

	for row in block.get("rates", []):
		var item_code := str(row.get("itemCode", ""))
		if item_code == "":
			continue
		var weight := float(row.get("weight", 0.0))
		# `classCode` e `biomeCode` chegam como null no lado que não se aplica —
		# e `str(null)` em GDScript vira "<null>", que casaria com nada e ainda
		# criaria um balde fantasma. Testar contra null antes de converter.
		var class_code: Variant = row.get("classCode", null)
		var biome_code: Variant = row.get("biomeCode", null)
		if class_code != null:
			_mining_bucket(_class_mining, str(class_code))[item_code] = weight
		elif biome_code != null:
			_mining_bucket(_biome_mining, str(biome_code))[item_code] = weight


static func _mining_bucket(store: Dictionary, key: String) -> Dictionary:
	if not store.has(key):
		store[key] = {}
	return store[key]


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


## Códigos de bioma de um mapa, na ordem em que o catálogo os lista.
##
## Esta é a lista DECLARADA do mapa — quais biomas ele tem. Onde cada um fica
## é outra consulta (`biome_regions_in_map`), e as duas discordarem é
## justamente o defeito que o exportador avisa: bioma listado que região
## nenhuma reivindica existe no catálogo e é inalcançável em jogo.
##
## Continua servindo de conferência para o bioma de fallback do mundo: sem
## ela, um bioma de outro mapa passaria batido, porque `MiningTable` trata
## bioma desconhecido como lado ausente e cai na classe sozinha, sem erro.
func biomes_in_map(map_code: String) -> Array:
	var m: Dictionary = _maps.get(map_code, {})
	var list: Variant = m.get("biomes", [])
	return list if list is Array else []


## Regiões de bioma de um mapa: `[{code, biome, shape, params}]`, na ordem de
## avaliação do catálogo (a primeira que contém o ponto ganha).
##
## As coordenadas em `params` são **normalizadas em ±1** sobre o meio-lado do
## mapa, não metros — quem traduz é `MapBiomes`, que é quem conhece o terreno.
## Este índice só entrega o que o bundle trouxe, sem interpretar forma nenhuma:
## `shape` novo no catálogo não muda uma linha aqui.
##
## Lista vazia é estado normal, e significa mapa sem partição autorada — o
## mundo cai no bioma declarado, como fazia antes de a partição existir.
func biome_regions_in_map(map_code: String) -> Array:
	var m: Dictionary = _maps.get(map_code, {})
	var list: Variant = m.get("biomeRegions", [])
	return list if list is Array else []


## Travessias que saem deste mapa: `[{to, requiredGlyph}]`, em ordem do
## catálogo. `requiredGlyph` nulo é passagem livre.
##
## Só a saída de uma ERA exige Glifo — travessia entre submapas da mesma era
## é livre por decisão de design (documento `glifos-e-portais`). Por isso o
## mundo pergunta antes de instanciar guardião: mapa sem travessia exigente
## não tem portal bloqueado para colocar.
func connections_from_map(map_code: String) -> Array:
	var m: Dictionary = _maps.get(map_code, {})
	var list: Variant = m.get("connections", [])
	return list if list is Array else []


## Nome de exibição de um Glifo (`"GLF-001"` → `"Daleth"`).
##
## O save guarda o CÓDIGO e a tela mostra o nome: é o que deixa a letra ser
## renomeada — o documento avisa que os nomes desta primeira leva são
## provisórios — sem invalidar o progresso de ninguém. Código desconhecido
## devolve ele mesmo, para a mensagem nunca sair vazia.
func glyph_name(code: String) -> String:
	var g: Dictionary = _glyphs.get(code, {})
	return str(g.get("name", code))

func creature_codes() -> Array:
	return _creatures.keys()

func map_codes() -> Array:
	return _maps.keys()

func element_codes() -> Array:
	return _elements.keys()

func class_codes() -> Array:
	return _classes.keys()


# ---------------------------------------------------------------------------
# mineração
#
# Só acesso a dado aqui. A fórmula que combina classe e bioma vive em
# `MiningTable`, pelo mesmo motivo que as contas de combate vivem em
# `CombatMath`: esta classe indexa o bundle, não decide regra.
# ---------------------------------------------------------------------------

func mineral(code: String) -> Dictionary:
	return _minerals.get(code, {})


## Nome de exibição de um mineral. Delega ao catálogo completo, que é
## superconjunto de `mining.items` — e cai no próprio código quando
## desconhecido: um inventário com "ITM-042" é feio mas legível; um vazio
## esconde o bug.
func mineral_name(code: String) -> String:
	return item_name(code)


func mineral_codes() -> Array:
	return _minerals.keys()


func has_mining() -> bool:
	return not _minerals.is_empty()


## Pesos de minério da classe, `{itemCode: peso}`. Vazio para classe que o
## bestiário ainda não cadastrou.
func class_mining_weights(class_code: String) -> Dictionary:
	return _class_mining.get(class_code, {})


func biome_mining_weights(biome_code: String) -> Dictionary:
	return _biome_mining.get(biome_code, {})


## `workFunction` da classe: `{speedModifier, role}`.
## É o perfil de trabalho da criatura domesticada — o que ela acelera e em que
## papel. Vazio se a classe não existe ou não tem perfil.
##
## `preferredOres` saiu do bundle em 2026-08: as chaves eram semânticas
## (`fossilAmber`), não códigos `ITM-*`, e traduzi-las exigiria um mapa
## hardcoded aqui — que é o oposto de tudo o que a migração para dado fez. Os
## pesos de `mining.rates` já respondem a mesma pergunta, em números.
func class_work_function(class_code: String) -> Dictionary:
	var c := creature_class(class_code)
	var wf: Variant = c.get("workFunction", null)
	return wf if typeof(wf) == TYPE_DICTIONARY else {}


## Qual dos cinco stats a classe especializa: `hp`, `attack`, `defense`,
## `speed` ou `charge`. Vazio se a classe não existe.
##
## O bundle nunca traz vazio numa classe válida — o export aborta em classe
## sem `primaryStat` justamente porque o bônus cairia sobre nada e a criatura
## sairia com o número de outra, sem sintoma. O fallback existe para o caso de
## um bundle antigo no disco, que é o único jeito de isso chegar aqui.
func class_primary_stat(class_code: String) -> String:
	var value: Variant = creature_class(class_code).get("primaryStat", null)
	return "" if value == null else str(value)


## Quanto a classe soma ao seu `primaryStat`, em pontos percentuais: `20` é
## +20%. Zero quando a classe não existe ou o bundle não traz o campo.
##
## O número vem do catálogo e não daqui — regra 1 deste repo. `1.20` não
## aparece em GDScript nenhum: mudar o bônus das cinco classes é um PATCH em
## `creature_classes`, não um commit.
func class_primary_stat_bonus_pct(class_code: String) -> float:
	var value: Variant = creature_class(class_code).get("primaryStatBonusPct", null)
	if value == null:
		return 0.0
	var pct := float(value)
	# Negativo viraria um debuff que ninguém pediu; o CHECK do banco já
	# recusa, e isto cobre bundle velho no disco.
	return pct if pct > 0.0 else 0.0


# ---------------------------------------------------------------------------
# itens e economia
#
# `items` é o catálogo inteiro, com preço e efeito. `mining.items` é a fatia
# minerável dele: o sorteio da picareta vem de lá, preço e efeito daqui.
# ---------------------------------------------------------------------------

func item(code: String) -> Dictionary:
	return _items.get(code, {})


## Nome de exibição. Procura no catálogo, depois no bloco de mineração (para
## sobreviver a um bundle antigo, anterior ao `items`), e por fim devolve o
## próprio código.
func item_name(code: String) -> String:
	if _items.has(code):
		return str(_items[code].get("name", code))
	if _minerals.has(code):
		return str(_minerals[code].get("name", code))
	return code


## Preço de compra. Zero para item que o bestiário ainda não precificou — o
## comerciante trata isso como "não está à venda".
func item_value(code: String) -> int:
	return int(item(code).get("value", 0))


func item_category(code: String) -> String:
	return str(item(code).get("category", ""))


func item_effect_code(code: String) -> String:
	return str(item(code).get("effectCode", "none"))


func item_effect_value(code: String) -> float:
	return float(item(code).get("effectValue", 0.0))


func items_in_category(category: String) -> Array:
	var out: Array = []
	for code in _items:
		if str(_items[code].get("category", "")) == category:
			out.append(_items[code])
	out.sort_custom(func(a, b): return str(a["code"]) < str(b["code"]))
	return out


## O material de `category = "material"` que pertence a uma classe — o item
## que sobe de nível gasta, seja uma criatura dessa classe (`progressao`) ou
## um relicário dessa classe (`relicario`). Só 3 hoje (`ITM-019/020/021`),
## scan linear está bem. Vazio se a classe não existe ou não tem material
## cadastrado.
func class_material_item(class_code: String) -> String:
	if class_code == "":
		return ""
	for item in items_in_category("material"):
		if str(item.get("classCode", "")) == class_code:
			return str(item["code"])
	return ""


func item_codes() -> Array:
	return _items.keys()


# --- economia ---

func currency_name(quantity: int = 1) -> String:
	var key := "currencyName" if absi(quantity) == 1 else "currencyNamePlural"
	return str(economy.get(key, "moeda" if absi(quantity) == 1 else "moedas"))


func starting_currency() -> int:
	return int(economy.get("startingCurrency", 0))


## Fração do valor que o comerciante paga ao comprar do jogador. O piso de
## segurança existe porque um bundle antigo, sem o bloco `economy`, daria
## `sellRatio` zero — e aí vender qualquer coisa renderia nada, em silêncio.
func sell_ratio() -> float:
	var ratio := float(economy.get("sellRatio", 0.0))
	return ratio if ratio > 0.0 else 0.4


## Quanto o comerciante paga por uma unidade. Piso de 1 para item que tem
## valor: arredondar para zero transformaria mineral barato em lixo que nunca
## sai do inventário.
func sell_price(code: String) -> int:
	var value := item_value(code)
	if value <= 0:
		return 0
	return maxi(1, int(floor(float(value) * sell_ratio())))


# --- comerciantes ---

func merchant(code: String) -> Dictionary:
	return _merchants.get(code, {})


func merchant_codes() -> Array:
	return _merchants.keys()


## Comerciantes de um mapa, para o mundo saber quem instanciar.
func merchants_in_map(map_code: String) -> Array:
	var out: Array = []
	for code in _merchants:
		if str(_merchants[code].get("map", "")) == map_code:
			out.append(_merchants[code])
	return out


# --- duelistas (arena) ---

func duelist(code: String) -> Dictionary:
	return _duelists.get(code, {})


func duelist_codes() -> Array:
	return _duelists.keys()


## Duelistas de um mapa, para o mundo saber quem instanciar como arena.
##
## Mesmo padrão de `merchants_in_map`, e desde 2026-08 cada duelista traz o
## bloco `duel` — contra quem, em que nível e qual Glifo a vitória concede.
## Isso eram três constantes no `WorldPopulator`, e o nível entre elas era
## número de balanceamento em código, contra a regra 1. `duel.grantsGlyph`
## nulo é normal: só a arena do último mapa de uma era concede Glifo.
func duelists_in_map(map_code: String) -> Array:
	var out: Array = []
	for code in _duelists:
		if str(_duelists[code].get("map", "")) == map_code:
			out.append(_duelists[code])
	return out


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


## `catchRate` bruto da criatura (1–255, maior é mais fácil), lido do bloco
## `capture` do bundle. Fonte única de dificuldade por criatura — o Relicário
## deriva `resistance` dele (`RelicMath.resistance`), não guarda o próprio.
func catch_rate(creature_code: String) -> int:
	var c := creature(creature_code)
	var cap: Variant = c.get("capture", null)
	return int(cap["catchRate"]) if cap != null else 0


## O que a criatura larga ao ser derrotada: `[{itemCode, chance, condition}]`.
## Vazio para criatura sem drop cadastrado — estado normal, não erro.
func creature_drops(creature_code: String) -> Array:
	return creature(creature_code).get("drops", [])


## `{xp: {curveBase, curveExponent, yieldDivisor}, levelUpCost: {base, levelStep}}`
## — as constantes de progressão de nível de criatura. Mesmo bloco `rules`
## que a formula de dano já lê, só a fatia `progression`. Ver `ProgressionMath`
## e documento `progressao`.
func progression_rules() -> Dictionary:
	var p: Variant = rules.get("progression", null)
	return p if typeof(p) == TYPE_DICTIONARY else {}


## Teto de nível do jogo (`combat_rules.levelMax`). Cria monta subindo até
## aqui e para — sem isso, XP sobrando numa criatura já no topo tentaria
## gastar material pra um nível que não existe.
func level_cap() -> int:
	var levels: Variant = rules.get("levels", null)
	if typeof(levels) != TYPE_DICTIONARY:
		return 999
	return int(levels.get("max", 999))


# ---------------------------------------------------------------------------
# Relicário
#
# Mesma divisão de sempre: esta classe indexa o bundle, `RelicMath` decide a
# fórmula. `_relics` já chega achatado (modelo + `relic_stats` num só dict),
# então não há uma segunda tabela pra cruzar aqui dentro.
# ---------------------------------------------------------------------------

func relic(code: String) -> Dictionary:
	return _relics.get(code, {})


func relic_codes() -> Array:
	return _relics.keys()


func has_relics() -> bool:
	return not _relics.is_empty()


## Constantes globais do sistema (floors/bônus de captura, curva de XP e
## custo de material do nível do relicário). `{}` se o bundle é anterior ao
## módulo — `has_relics()` já avisou no load.
func relic_rules() -> Dictionary:
	var r: Variant = rules.get("relic", null)
	return r if typeof(r) == TYPE_DICTIONARY else {}


## Taxa de captura do relicário no nível dado — sobe linear a partir de
## `baseCaptureRate` (o valor no nível 1).
func relic_capture_rate_at_level(relic_code: String, level: int) -> float:
	var r := relic(relic_code)
	if r.is_empty():
		return 0.0
	return RelicMath.rate_at_level(float(r["baseCaptureRate"]), float(r["captureRatePerLevel"]), level)



# ---------------------------------------------------------------------------
# Set do jogador — Amplificador e Encantador
#
# O Relicário fica de fora deste bloco de propósito: ele tem tabela, curva e
# progressão próprias (`_relics` acima). O que estas funções indexam é o
# resto do set — as peças passivas, fabricadas de minério, cujo modelo já
# chega achatado com números e receita num dicionário só.
#
# Aqui não há fórmula nenhuma, nem uma classe `EquipmentMath` ao lado: o
# efeito é `modificador *= 1 ± valor/100`, que é aritmética que `Battle` já
# faz para as habilidades de suporte. Uma classe de fórmula para reembrulhar
# uma linha seria a duplicação que o repo evita, não a separação que ele pede.
# ---------------------------------------------------------------------------

## Os dois slots do set fora do Relicário. Strings porque é o que o bundle
## traz em `equipment[].slot`; um slot novo entra no catálogo e nesta lista.
const SLOT_AMPLIFIER := "amplifier"
const SLOT_ENCHANTER := "enchanter"


func equipment(code: String) -> Dictionary:
	return _equipment.get(code, {})


func equipment_codes() -> Array:
	return _equipment.keys()


func has_equipment() -> bool:
	return not _equipment.is_empty()


## Modelos de um slot, do tier mais barato para o mais caro. A ordem é a da
## bancada e a da janela do set — e é por tier, não por código, para que um
## modelo intercalado depois (um T2 alternativo) caia no lugar certo sem
## depender de alguém ter escolhido bem o número do `EQP-`.
func equipment_in_slot(slot: String) -> Array:
	var out: Array = []
	for code: String in _equipment:
		if str(_equipment[code].get("slot", "")) == slot:
			out.append(_equipment[code])
	out.sort_custom(func(a, b): return int(a.get("tier", 0)) < int(b.get("tier", 0)))
	return out


func equipment_slot(code: String) -> String:
	return str(equipment(code).get("slot", ""))


func equipment_name(code: String) -> String:
	var e := equipment(code)
	return str(e.get("name", code)) if not e.is_empty() else code


func equipment_tier(code: String) -> int:
	return int(equipment(code).get("tier", 0))


## O par que o combate lê. Separados em duas funções pelo mesmo motivo de
## `item_effect_code`/`item_effect_value`: quem chama tem de pegar os dois,
## e ler o valor sem o código ao lado é o erro que a separação torna visível.
func equipment_effect_code(code: String) -> String:
	return str(equipment(code).get("effectCode", ""))


func equipment_effect_value(code: String) -> float:
	return float(equipment(code).get("effectValue", 0.0))


## A receita, como `[{itemCode, quantity}]`. Vazia para um código que não
## existe — a bancada trata isso como "não fabricável" em vez de fabricar de
## graça, que é o que uma receita vazia significaria se lida ao pé da letra.
func equipment_recipe(code: String) -> Array:
	var r: Variant = equipment(code).get("recipe", [])
	return r if typeof(r) == TYPE_ARRAY else []

# ---------------------------------------------------------------------------
# atalhos que combinam dados + fórmulas
# ---------------------------------------------------------------------------

## Os cinco stats efetivos da criatura no nível dado, já com o bônus da
## classe aplicado.
## Dicionário vazio se a criatura não existe ou está sem stats — o que o
## export já deveria ter impedido de acontecer.
##
## **Este é o funil único dos stats.** Combate (`Combatant.from_bestiary`),
## time, ficha e painel da ativa passam todos por aqui, e é por isso que o
## bônus da classe entra neste ponto e não em `Combatant`: aplicado lá, a luta
## veria o número especializado e a ficha mostraria outro, e a divergência
## leria como bug de interface.
##
## A classe soma ao SEU stat e a mais nenhum — Arambi engrossa `defense`,
## Torumã engrossa `hp`. Não existe multiplicador que dependa da classe do
## oponente: o bônus é o mesmo contra qualquer adversário, o que é a diferença
## entre especialização e a matriz CLS×CLS que o projeto não tem.
func stats_at_level(creature_code: String, level: int) -> Dictionary:
	var c := creature(creature_code)
	if c.is_empty():
		return {}
	var s: Variant = c.get("stats", null)
	if s == null:
		return {}

	var growth := float(s["growthRate"])
	var out := {
		"hp": CombatMath.stat_at_level(int(s["hp"]), growth, level),
		"attack": CombatMath.stat_at_level(int(s["attack"]), growth, level),
		"defense": CombatMath.stat_at_level(int(s["defense"]), growth, level),
		"speed": CombatMath.stat_at_level(int(s["speed"]), growth, level),
		"charge": CombatMath.stat_at_level(int(s["charge"]), growth, level),
	}

	var class_code := str(c.get("class", ""))
	var stat := class_primary_stat(class_code)
	# `out.has(stat)` não é paranoia: um bundle antigo no disco pode trazer um
	# `primaryStat` que não é um dos cinco, e escrever a chave nova em vez de
	# multiplicar a existente daria uma criatura com seis stats e o bônus
	# perdido — exatamente o tipo de furo silencioso que o export aborta para
	# nunca chegar aqui.
	if stat != "" and out.has(stat):
		out[stat] = CombatMath.stat_with_class_bonus(
			int(out[stat]), class_primary_stat_bonus_pct(class_code))

	return out


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


## Mesmo problema, para o `element`/`class` de um modelo de Relicário: desde
## que o starter neutro existe (documento `relicario`), um relic pode chegar
## do bundle com `element: null` e/ou `class: null` — sem isso, `str(null)`
## viraria a string "<null>", que casaria com nada e faria o starter parecer
## "tem afinidade com um código inexistente" em vez de "sem afinidade".
static func relic_element_code(relic: Dictionary) -> String:
	var value: Variant = relic.get("element", null)
	return "" if value == null else str(value)


static func relic_class_code(relic: Dictionary) -> String:
	var value: Variant = relic.get("class", null)
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
