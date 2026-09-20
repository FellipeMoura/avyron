class_name PlayerRelic
extends RefCounted

## O relicário equipado pelo jogador: só o estado de progressão persiste
## (código do modelo, nível, XP acumulado) — o resto (slotCapacity, taxa de
## captura) é resolvido no bundle a cada leitura, mesmo estilo de
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
	return BestiaryData.relic_element_code(_data(db))


func class_code(db: BestiaryData) -> String:
	return BestiaryData.relic_class_code(_data(db))


func slot_capacity(db: BestiaryData) -> int:
	var d := _data(db)
	return int(d.get("slotCapacity", 1)) if not d.is_empty() else 1


func max_level(db: BestiaryData) -> int:
	var d := _data(db)
	return int(d.get("maxLevel", 1)) if not d.is_empty() else 1


func capture_rate(db: BestiaryData) -> float:
	return db.relic_capture_rate_at_level(relic_code, level) if db != null else 0.0



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


## A leitura de progressão pronta pra tela — mesma forma de
## `PlayerRoster.progress_at`, mais `can_level`:
##
##     {level, xp, xp_to_next, at_cap, xp_full, material, material_cost, can_level}
##
## `can_level` é o que separa o starter neutro dos modelos com classe: sem
## classe não há material que suba de nível, a barra enche e para de
## propósito (documento `relicario`). A tela precisa dizer ISSO — "sem
## classe, não sobe" — em vez de pedir um material que não existe, que era o
## que "XP cheio, falta ." fazia a cada captura.
func progress(db: BestiaryData) -> Dictionary:
	var out := {
		"level": level, "xp": xp, "xp_to_next": 0, "at_cap": false, "xp_full": false,
		"material": "", "material_cost": 0, "can_level": false,
	}
	if db == null or db.relic_rules().is_empty():
		return out
	out["material"] = material_item_code(db)
	out["can_level"] = str(out["material"]) != ""
	out["at_cap"] = level >= max_level(db)
	if out["at_cap"]:
		return out
	out["xp_to_next"] = xp_to_next(db)
	out["xp_full"] = xp >= int(out["xp_to_next"])
	out["material_cost"] = material_cost(db)
	return out


## Concede XP de uma captura bem-sucedida e sobe de nível se der — precisa de
## XP cheio **e** do material disponível na bolsa. Sem o material, o XP trava
## no teto (não deixa passar) até o jogador ter o item; sem isso a barra
## passaria do teto silenciosamente e "cheia" deixaria de significar algo.
##
## Devolve `{leveled_up, new_level, waiting_material, material, units_needed}`
## — `material`/`units_needed` só preenchidos quando travou esperando, mesmo
## contrato de `PlayerRoster.grant_xp_at`. No teto do modelo o XP não
## acumula, pela mesma razão de lá.
func grant_capture_xp(db: BestiaryData, inventory: PlayerInventory) -> Dictionary:
	var result := {
		"leveled_up": false, "new_level": level, "waiting_material": false,
		"material": "", "units_needed": 0,
	}
	if db == null or inventory == null:
		return result

	var rr := db.relic_rules()
	if rr.is_empty():
		return result

	var cap := max_level(db)
	if level >= cap:
		return result

	xp += int(rr["xpPerCapture"])

	while level < cap and xp >= xp_to_next(db):
		var threshold := xp_to_next(db)
		var cost := material_cost(db)
		var material := material_item_code(db)
		if material == "" or not inventory.remove(material, cost):
			xp = threshold  # trava no teto — nao deixa a barra estourar esperando material
			result["waiting_material"] = true
			result["material"] = material
			result["units_needed"] = cost
			break
		xp -= threshold
		level += 1
		result["leveled_up"] = true
		result["new_level"] = level

	if level >= cap:
		xp = 0

	return result
