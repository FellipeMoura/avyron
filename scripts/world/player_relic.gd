class_name PlayerRelic
extends RefCounted

## O relicário equipado pelo jogador: só o estado de progressão persiste
## (código do modelo, nível, XP acumulado) — o resto (slotCapacity, taxa de
## captura, buff) é resolvido no bundle a cada leitura, mesmo estilo de
## `PlayerRoster`/`Combatant`.
##
## Sem consumível: capturar não gasta nada do relicário, só alimenta a barra
## de XP. Subir de nível exige XP cheio **e** o material da classe do próprio
## relicário — a mesma exigência dupla que já existe pra subir de nível de
## criatura, só que aqui o "combate vencido" vira "captura bem-sucedida".
##
## Especificação: documento `relicario` no bestiário.

var relic_code: String = ""
var level := 1
var xp := 0


static func from_bestiary(db: BestiaryData, code: String) -> PlayerRelic:
	if db == null or db.relic(code).is_empty():
		return null
	var r := PlayerRelic.new()
	r.relic_code = code
	return r


func _data(db: BestiaryData) -> Dictionary:
	return db.relic(relic_code) if db != null else {}


func display_name(db: BestiaryData) -> String:
	var d := _data(db)
	return str(d.get("name", relic_code)) if not d.is_empty() else relic_code


func element_code(db: BestiaryData) -> String:
	return str(_data(db).get("element", ""))


func class_code(db: BestiaryData) -> String:
	return str(_data(db).get("class", ""))


func slot_capacity(db: BestiaryData) -> int:
	var d := _data(db)
	return int(d.get("slotCapacity", 1)) if not d.is_empty() else 1


func max_level(db: BestiaryData) -> int:
	var d := _data(db)
	return int(d.get("maxLevel", 1)) if not d.is_empty() else 1


func capture_rate(db: BestiaryData) -> float:
	return db.relic_capture_rate_at_level(relic_code, level) if db != null else 0.0


func combat_buff(db: BestiaryData) -> float:
	return db.relic_combat_buff_at_level(relic_code, level) if db != null else 0.0


func xp_to_next(db: BestiaryData) -> int:
	var rr := db.relic_rules() if db != null else {}
	if rr.is_empty():
		return 0
	return ProgressionMath.xp_to_next(float(rr["xpCurveBase"]), float(rr["xpCurveExponent"]), level)


func material_cost(db: BestiaryData) -> int:
	var rr := db.relic_rules() if db != null else {}
	if rr.is_empty():
		return 0
	return ProgressionMath.material_cost(int(rr["materialCostBase"]), int(rr["materialCostLevelStep"]), level)


## Item de material que este relicário consome pra subir de nível — o mesmo
## material da classe do relicário que já alimenta o level-up de criatura
## (`ITM-019/020/021`).
func material_item_code(db: BestiaryData) -> String:
	return db.class_material_item(class_code(db)) if db != null else ""


## Concede XP de uma captura bem-sucedida e sobe de nível se der — precisa de
## XP cheio **e** do material disponível na bolsa. Sem o material, o XP trava
## no teto (não deixa passar) até o jogador ter o item; sem isso a barra
## passaria do teto silenciosamente e "cheia" deixaria de significar algo.
##
## Devolve `{leveled_up: bool, new_level: int, waiting_material: bool}`.
func grant_capture_xp(db: BestiaryData, inventory: PlayerInventory) -> Dictionary:
	var result := {"leveled_up": false, "new_level": level, "waiting_material": false}
	if db == null or inventory == null:
		return result

	var rr := db.relic_rules()
	if rr.is_empty():
		return result

	xp += int(rr["xpPerCapture"])

	var cap := max_level(db)
	while level < cap and xp >= xp_to_next(db):
		var threshold := xp_to_next(db)
		var cost := material_cost(db)
		var material := material_item_code(db)
		if material == "" or not inventory.remove(material, cost):
			xp = threshold  # trava no teto — nao deixa a barra estourar esperando material
			result["waiting_material"] = true
			break
		xp -= threshold
		level += 1
		result["leveled_up"] = true
		result["new_level"] = level

	return result
