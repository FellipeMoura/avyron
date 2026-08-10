class_name ItemEffects
extends RefCounted

## O que um item faz ao ser usado. Funções puras, no par de `CombatMath` e
## `MiningTable`: o bestiário diz *quanto* (`effectCode` + `effectValue`), esta
## classe diz só a forma da aritmética.
##
## Nenhum número mora aqui. Item novo que reuse um efeito existente não toca
## neste arquivo — entra pelo bestiário e chega no próximo `game:export`.
##
## Especificação legível: a coluna `item_stats` no briefing do bestiário.


## Os valores do enum `item_effect` do bestiário. Estão como constante para
## um erro de digitação virar erro de parser em vez de um item que
## silenciosamente não faz nada.
const NONE := "none"
const CAPTURE_BONUS := "capture_bonus"
const HEAL_FLAT := "heal_flat"
const HEAL_PERCENT := "heal_percent"


static func is_heal(effect_code: String) -> bool:
	return effect_code == HEAL_FLAT or effect_code == HEAL_PERCENT


## Quanto de HP o item recupera numa criatura com este teto.
##
## `heal_percent` traz **pontos percentuais** (30, 70, 100), não fração — é o
## que está gravado em `item_stats.effectValue`. `capture_bonus`, no mesmo
## campo, é multiplicador cru (1.5, 2.5, 4.0). Os dois convivem porque quem
## interpreta o número é sempre o código do efeito, nunca o campo sozinho; ler
## `effectValue` sem olhar o `effectCode` ao lado é o erro que esta nota existe
## para evitar.
##
## Piso de 1 para qualquer cura positiva: 30% de um teto de 3 HP dá zero por
## arredondamento, e um consumível gasto sem efeito é pior que um recusado.
static func heal_amount(effect_code: String, effect_value: float, max_hp: int) -> int:
	if max_hp <= 0 or effect_value <= 0.0:
		return 0
	match effect_code:
		HEAL_FLAT:
			return maxi(1, int(effect_value))
		HEAL_PERCENT:
			return maxi(1, int(floor(float(max_hp) * effect_value / 100.0)))
		_:
			return 0


## Rótulo curto do efeito, para a lista de itens: `+30%` ou `+40`.
##
## É apresentação, mas mora aqui de propósito: quem sabe que um código traz
## percentual e o outro traz pontos é esta classe, e duplicar esse "%" numa
## tela seria a segunda fonte que discorda da primeira quando um efeito novo
## aparecer.
static func heal_label(effect_code: String, effect_value: float) -> String:
	match effect_code:
		HEAL_FLAT:
			return "+%d" % int(effect_value)
		HEAL_PERCENT:
			return "+%d%%" % int(effect_value)
		_:
			return ""
