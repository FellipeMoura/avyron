class_name Combatant
extends RefCounted

## Uma criatura dentro de uma batalha. Guarda o estado volátil — HP, carga,
## buffs, usos restantes — enquanto os dados imutáveis da espécie continuam
## no bundle.
##
## Nada aqui persiste entre batalhas. O medidor de carga em particular
## **começa zerado toda vez**, por decisão de design: o Despertar Ancestral é
## um arco dentro de uma luta, não um orçamento administrado ao longo do dia.

var code: String
var display_name: String
var element: String
var creature_class: String
var level: int

var max_hp: int
var hp: int
var base_attack: int
var base_defense: int
var base_speed: int
var base_charge: int

## 0 a 100. Cheio libera o Despertar Ancestral.
var charge_meter: float = 0.0

var is_awakened := false
var awakened_rounds_left := 0
var awakening_multiplier := 1.5
var awakening_duration := 3
var awakening_name := ""
var has_awakening := false

## Multiplicadores acumulados por buff/debuff. 1.0 é neutro.
var attack_modifier := 1.0
var defense_modifier := 1.0

var catch_rate := 0
var awakened_capture_multiplier := 1.0

var _abilities: Array = []          # dicionários do bundle, em ordem de aprendizado
var _uses_left: Dictionary = {}     # código -> usos restantes


## Monta um combatente a partir do bundle. Devolve null se a criatura não
## existe ou está sem stats — o que o export já deveria ter impedido.
static func from_bestiary(db: BestiaryData, creature_code: String, at_level: int) -> Combatant:
	var data := db.creature(creature_code)
	if data.is_empty() or data.get("stats", null) == null:
		return null

	var c := Combatant.new()
	c.code = creature_code
	c.display_name = str(data.get("name", creature_code))
	c.element = str(data.get("element", ""))
	c.creature_class = str(data.get("class", ""))
	c.level = at_level

	var s := db.stats_at_level(creature_code, at_level)
	c.max_hp = s["hp"]
	c.hp = s["hp"]
	c.base_attack = s["attack"]
	c.base_defense = s["defense"]
	c.base_speed = s["speed"]
	c.base_charge = s["charge"]

	var raw_stats: Dictionary = data["stats"]
	c.awakening_multiplier = float(raw_stats["awakeningMultiplier"])
	c.awakening_duration = int(raw_stats["awakeningDurationTurns"])

	var awk: Variant = data.get("awakening", null)
	c.has_awakening = awk != null
	if c.has_awakening:
		c.awakening_name = str(awk["name"])

	var cap: Variant = data.get("capture", null)
	if cap != null:
		c.catch_rate = int(cap["catchRate"])
		c.awakened_capture_multiplier = float(cap["awakenedMultiplier"])

	c._abilities = db.known_abilities(creature_code, at_level)
	for a in c._abilities:
		c._uses_left[str(a["code"])] = int(a["uses"])

	return c


# ---------------------------------------------------------------------------
# stats efetivos
# ---------------------------------------------------------------------------

## Ataque depois de buffs e do Despertar. Piso de 1 para a fórmula de dano
## nunca dividir nem multiplicar por zero.
func effective_attack() -> int:
	var v := float(base_attack) * attack_modifier
	if is_awakened:
		v *= awakening_multiplier
	return maxi(1, int(v))


func effective_defense() -> int:
	var v := float(base_defense) * defense_modifier
	if is_awakened:
		v *= awakening_multiplier
	return maxi(1, int(v))


func effective_speed() -> int:
	return maxi(1, base_speed)


## Só este stat não é afetado pelo Despertar: a carga acelera o caminho até a
## transformação, não é acelerada por ela.
func effective_charge() -> int:
	return maxi(1, base_charge)


func is_fainted() -> bool:
	return hp <= 0


func hp_ratio() -> float:
	return float(hp) / float(max_hp) if max_hp > 0 else 0.0


# ---------------------------------------------------------------------------
# habilidades
# ---------------------------------------------------------------------------

## Golpes utilizáveis agora: conhecidos no nível, com usos restantes, e com a
## assinatura do Despertar aparecendo apenas durante a transformação.
func available_abilities() -> Array:
	var out: Array = []
	for a in _abilities:
		var ability_code := str(a["code"])
		if _uses_left.get(ability_code, 0) <= 0:
			continue
		if bool(a["awakeningOnly"]) and not is_awakened:
			continue
		out.append(a)
	return out


func ability_by_code(ability_code: String) -> Dictionary:
	for a in _abilities:
		if str(a["code"]) == ability_code:
			return a
	return {}


func uses_left(ability_code: String) -> int:
	return int(_uses_left.get(ability_code, 0))


func consume_use(ability_code: String) -> void:
	if _uses_left.has(ability_code):
		_uses_left[ability_code] = maxi(0, int(_uses_left[ability_code]) - 1)


# ---------------------------------------------------------------------------
# carga e Despertar
# ---------------------------------------------------------------------------

func add_charge(amount: float, charge_max: float) -> void:
	if is_awakened:
		return  # já transformada: o medidor não acumula durante o Despertar
	charge_meter = clampf(charge_meter + amount, 0.0, charge_max)


func can_awaken(charge_max: float) -> bool:
	return has_awakening and not is_awakened and charge_meter >= charge_max


## Ativa a transformação. Não consome o turno — por isso não vive dentro de
## uma ação de batalha.
func awaken() -> void:
	is_awakened = true
	awakened_rounds_left = awakening_duration
	charge_meter = 0.0


## Chamado no fim de cada rodada. Devolve true no momento em que reverte.
func tick_awakening() -> bool:
	if not is_awakened:
		return false
	awakened_rounds_left -= 1
	if awakened_rounds_left <= 0:
		revert()
		return true
	return false


func revert() -> void:
	is_awakened = false
	awakened_rounds_left = 0
