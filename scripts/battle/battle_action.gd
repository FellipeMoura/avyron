class_name BattleAction
extends RefCounted

## A escolha de um lado para a rodada. Um objeto de valor — sem lógica.
##
## Ativar o Despertar Ancestral **não** aparece aqui de propósito: ativar não
## consome o turno, então é uma chamada à parte em `Battle`, não uma ação
## que compete com atacar.

enum Kind {
	ABILITY,
	SWITCH,
	CAPTURE,
	FLEE,
}

## Trocar de criatura sempre acontece antes de qualquer golpe, por mais
## rápido que seja o oponente. Acima da faixa de prioridade das habilidades,
## que vai de -3 a 3.
const SWITCH_PRIORITY := 6

var kind: Kind
var ability_code: String = ""
var switch_to_index: int = -1
var item_bonus: float = 1.0


static func use_ability(code: String) -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.ABILITY
	a.ability_code = code
	return a


static func switch_to(party_index: int) -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.SWITCH
	a.switch_to_index = party_index
	return a


## Capturar consome o turno, como um golpe. `bonus` é o multiplicador do item
## usado — 1.0 para o básico.
static func capture(bonus: float = 1.0) -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.CAPTURE
	a.item_bonus = bonus
	return a


static func flee() -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.FLEE
	return a
