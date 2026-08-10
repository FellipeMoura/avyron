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

## Só preenchidos em `Kind.CAPTURE`. A chamadora resolve o relicário equipado
## antes de montar a ação — `Battle` não conhece `PlayerRelic`, só recebe os
## três primitivos que `RelicMath.capture_chance` precisa.
var relic_rate: float = 0.0
var relic_element: String = ""
var relic_class: String = ""


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


## Capturar consome o turno, como um golpe. Os três valores vêm do relicário
## equipado no momento em que o jogador aperta a tecla — sem eles (relicário
## nulo) a chamadora nem deve montar esta ação.
static func capture(rate: float, element: String, class_code: String) -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.CAPTURE
	a.relic_rate = rate
	a.relic_element = element
	a.relic_class = class_code
	return a


static func flee() -> BattleAction:
	var a := BattleAction.new()
	a.kind = Kind.FLEE
	return a
