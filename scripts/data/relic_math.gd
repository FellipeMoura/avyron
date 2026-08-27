class_name RelicMath
extends RefCounted

## Fórmulas do sistema de Relicário. Funções puras, mesmo contrato de
## `CombatMath`/`MiningTable`: nada aqui lê estado global ou RNG (o roll da
## captura continua em `Battle._do_capture`, esta classe só calcula a chance).
##
## Toda constante vem de `BestiaryData.relic_rules()` — nenhum número de
## balanceamento é escrito aqui. Especificação legível: documentos `captura`
## e `relicario` no bestiário.


## Valor da curva linear de taxa de captura do relicário no nível dado.
##
##     valor(nível) = base + perLevel * (nível - 1)
##
## `base` é o valor **no nível 1** por definição (`relic_stats.baseCaptureRate`),
## por isso o incremento multiplica `(nível - 1)` e não o nível cru — do
## contrário o nível 1 já contaria um incremento que não devia.
##
## Genérica de propósito, mas hoje com um consumidor só: a curva de buff de
## combate que dividia esta fórmula saiu do escopo do Relicário (documento
## `relicario`) e as colunas saíram do banco em 2026-08.
static func rate_at_level(base: float, per_level: float, level: int) -> float:
	return base + per_level * float(level - 1)


## Resistência da criatura à captura — a inversão de `catchRate` (1–255,
## maior é mais fácil) que a fórmula do Relicário usa como denominador.
## `catchRate` continua sendo a fonte única de dificuldade por criatura; isto
## só lê a escala ao contrário do que a fórmula antiga lia.
static func resistance(catch_rate: int) -> int:
	return 256 - catch_rate


## Chance de captura via Relicário, entre 0.0 e 1.0.
##
##     relicRate = (já resolvido pela chamadora, `relic_capture_rate_at_level`)
##     base%     = (relicRate / resistance(catchRate)) * 100
##     final%    = clamp(
##                   base%
##                   + sameElementBonusPct           (mesmo elemento)
##                   + sameClassBonusPct              (mesma classe)
##                   - elementDisadvantagePenaltyPct  (elemento em desvantagem)
##                 , captureFloorPct, captureCeilPct)
##
## Sem termo de HP e sem termo de Despertar — decisão explícita do redesenho,
## documentada em `captura`. Vantagem elemental não gera bônus, só o mesmo
## elemento gera; o resto é neutro.
static func capture_chance(
	db: BestiaryData,
	relic_rate: float,
	relic_element: String,
	relic_class: String,
	creature_catch_rate: int,
	creature_element: String,
	creature_class: String
) -> float:
	var r := db.relic_rules()
	if r.is_empty():
		return 0.0

	var res := resistance(creature_catch_rate)
	if res <= 0:
		return float(r["captureCeilPct"]) / 100.0

	var base_pct := (relic_rate / float(res)) * 100.0

	if relic_element != "" and relic_element == creature_element:
		base_pct += float(r["sameElementBonusPct"])
	if relic_class != "" and relic_class == creature_class:
		base_pct += float(r["sameClassBonusPct"])

	var mult := db.element_multiplier(relic_element, creature_element)
	if mult < 1.0:
		base_pct -= float(r["elementDisadvantagePenaltyPct"])

	var final_pct := clampf(base_pct, float(r["captureFloorPct"]), float(r["captureCeilPct"]))
	return final_pct / 100.0
