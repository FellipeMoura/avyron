class_name ProgressionMath
extends RefCounted

## Curva de nível compartilhada por dois sistemas que sobem de nível do mesmo
## jeito — XP acumulado até um limiar **e** material da própria classe
## gasto no ato: o Relicário (`PlayerRelic`, XP por captura) e as criaturas
## do time (`PlayerRoster`, XP por vitória). Extraído de `RelicMath` quando a
## segunda chamadora apareceu — mesma forma, zero relação com a fórmula de
## captura que ficou lá.
##
## Funções puras, sem estado. Especificação: documentos `progressao` e
## `relicario` no bestiário.


## XP necessário pra passar do nível dado ao seguinte.
##
##     xpToNext(nível) = floor(curveBase * nível ^ curveExponent)
static func xp_to_next(curve_base: float, curve_exponent: float, level: int) -> int:
	return int(floor(curve_base * pow(float(level), curve_exponent)))


## Unidades do material de classe exigidas pra subir do nível dado.
##
##     custo(nível) = base + floor(nível / levelStep)
static func material_cost(base: int, level_step: int, level: int) -> int:
	if level_step <= 0:
		return base
	return base + int(floor(float(level) / float(level_step)))
