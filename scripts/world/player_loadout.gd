class_name PlayerLoadout
extends RefCounted

## O que o domador tem vestido fora do Relicário: um Amplificador e um
## Encantador, cada um no seu slot.
##
## Duas coisas moram aqui, e a distinção é o coração do sistema:
##
## - **posse** (`_owned`) — os modelos que o jogador fabricou. Cresce só na
##   bancada, gastando minério.
## - **equipado** (`_equipped`) — qual modelo de cada slot está em uso.
##
## O Relicário não tem essa separação, e por isso o posto dele deixa trocar
## para qualquer modelo do catálogo sem checar nada (ver ROADMAP). Aqui a
## posse existe desde o primeiro dia porque a fabricação **é** o sistema de
## aquisição: um modelo que ninguém fabricou não pode ser vestido, e isso é
## verificado num lugar só, `equip()`.
##
## Estado de jogador, não de catálogo — igual ao time e à bolsa. O que o
## bundle descreve é o que um modelo *faz*; o que este objeto guarda é o que
## este jogador *tem*. Nada aqui persiste em disco ainda: `PlayerProgress`
## continua sendo o único que grava, e quando o save crescer é lá que estas
## duas listas entram.
##
## Especificação: documento `equipamentos` no bestiário.

## Emitido quando a posse ou o que está vestido muda — a janela do set (`E`) e
## a bancada escutam. Um sinal só, pelo mesmo motivo de `PlayerInventory`:
## fabricar já equipa, então os dois lados mudam na mesma ação e dois sinais
## deixariam a HUD meio atualizada no meio do quadro.
signal changed

## Códigos `EQP-*` que o jogador fabricou. Set, não lista: fabricar o mesmo
## modelo duas vezes não faz sentido — ele é permanente e não se consome —, e
## a bancada recusa antes de gastar minério.
var _owned: Dictionary = {}      # code -> true

## slot -> código equipado. Slot ausente = nada vestido naquele slot, que é o
## estado inicial de todo jogador e não um erro a esconder.
var _equipped: Dictionary = {}   # String -> String


# ---------------------------------------------------------------------------
# posse
# ---------------------------------------------------------------------------

func owns(code: String) -> bool:
	return _owned.has(code)


func owned_codes() -> Array:
	var out := _owned.keys()
	out.sort()
	return out


## Registra a fabricação de um modelo. Devolve `false` se já era do jogador —
## quem chama (a bancada) usa isso para não cobrar duas vezes pela mesma peça.
##
## Equipar na hora é deliberado: o jogador que acabou de gastar trinta cobres
## não deve precisar de um segundo gesto para usar o que fez, e o modelo novo
## é sempre melhor que o do mesmo slot que ele já tinha (os tiers só sobem).
func acquire(code: String, slot: String) -> bool:
	if code == "" or _owned.has(code):
		return false
	_owned[code] = true
	if slot != "":
		_equipped[slot] = code
	changed.emit()
	return true


# ---------------------------------------------------------------------------
# equipado
# ---------------------------------------------------------------------------

func equipped_in(slot: String) -> String:
	return str(_equipped.get(slot, ""))


func has_anything() -> bool:
	return not _equipped.is_empty()


## Veste um modelo que o jogador possui. Recusa o que não é dele — é a
## checagem de posse que o posto do Relicário não tem, e ela mora aqui e não
## na tela porque uma segunda tela cairia no mesmo furo.
func equip(code: String, slot: String) -> bool:
	if slot == "" or not _owned.has(code):
		return false
	if str(_equipped.get(slot, "")) == code:
		return false
	_equipped[slot] = code
	changed.emit()
	return true


## Tira o que está no slot. Existe para o jogador poder lutar sem a peça —
## desligar um debuff permanente é uma jogada legítima contra um adversário
## que se aproveite dele, e sem isto a única forma de não usar o Encantador
## seria nunca o ter fabricado.
func unequip(slot: String) -> bool:
	if not _equipped.has(slot):
		return false
	_equipped.erase(slot)
	changed.emit()
	return true


# ---------------------------------------------------------------------------
# o que o combate pergunta
# ---------------------------------------------------------------------------

## Os modificadores que este loadout aplica, resolvidos contra o bundle:
## `[{effect_code, value, slot, equipment_code}]`, um por slot vestido.
##
## Devolve dado cru em vez de aplicar nada. Quem aplica é `Battle`, que é
## quem tem os combatentes e o clamp — se esta classe mexesse em `Combatant`
## direto, o teto acumulado de modificador passaria a ter dois donos.
func modifiers(db: BestiaryData) -> Array:
	var out: Array = []
	if db == null:
		return out
	for slot: String in _equipped:
		var code := str(_equipped[slot])
		var effect := db.equipment_effect_code(code)
		var value := db.equipment_effect_value(code)
		# Modelo com efeito vazio é bundle velho ou catálogo quebrado. Pular em
		# silêncio é certo aqui: `BestiaryData` já avisou uma vez no load, e
		# avisar por combatente viraria enxurrada a cada batalha.
		if effect == "" or value <= 0.0:
			continue
		out.append({
			"effect_code": effect,
			"value": value,
			"slot": slot,
			"equipment_code": code,
		})
	return out
