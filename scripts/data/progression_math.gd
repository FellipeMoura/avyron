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


# ---------------------------------------------------------------------------
# distribuição de XP de vitória entre participantes
#
# Documento `progressao`: a XP total de uma vitória é conservada — trocar
# mais criaturas nunca cria XP — e dividida entre quem participou de fato
# (`Battle.xp_participants`), não só quem terminou a luta em campo.
# ---------------------------------------------------------------------------

## Proporção do XP total que vira parcela base (dividida igualmente entre os
## participantes) — o resto vira parcela por contribuição. **Placeholder de
## tuning, não decisão final** (o documento de design discute 20%/80% só como
## ilustração). Mude aqui quando o valor fechar; nada mais neste arquivo
## depende do número em si.
const XP_BASE_SHARE_RATIO := 0.2

## Distribui `xp_total` entre os participantes de uma vitória, na mesma
## ordem de `contributions`. Devolve um `Array[int]` do mesmo tamanho, com
## soma **exatamente** igual a `xp_total` (arredondamento por maior resto —
## ver `_round_conserving_total` —, nunca `floor` solto por item, que vazaria
## XP).
##
## Cada parcela é `base_igual + pool_contribuição * (contribuição_i / soma)`.
## Com `contributions` somando zero (ninguém causou nem sofreu dano — só
## participou por outra via, ex.: capturas tentadas), cai na divisão igual
## para não dividir por zero. Um único participante leva tudo, sem rodeio de
## fórmula.
static func distribute_xp(xp_total: int, contributions: Array) -> Array:
	var n := contributions.size()
	if xp_total <= 0 or n <= 0:
		return []
	if n == 1:
		return [xp_total]

	var total_contribution := 0.0
	for c in contributions:
		total_contribution += float(c)

	var shares: Array[float] = []
	if total_contribution <= 0.0:
		var equal_share := float(xp_total) / float(n)
		for i in n:
			shares.append(equal_share)
	else:
		var base_pool := float(xp_total) * XP_BASE_SHARE_RATIO
		var contribution_pool := float(xp_total) - base_pool
		var base_each := base_pool / float(n)
		for i in n:
			shares.append(base_each + contribution_pool * (float(contributions[i]) / total_contribution))

	return _round_conserving_total(shares, xp_total)


## `floor` em cada parcela flutuante, depois distribui o resto inteiro
## (menor que `n` por definição) para quem perdeu mais no arredondamento —
## maior resto primeiro. É o que garante `sum(saida) == xp_total` sempre,
## mesmo com `n` grande e `xp_total` pequeno.
static func _round_conserving_total(shares: Array[float], xp_total: int) -> Array:
	var floors: Array[int] = []
	var remainders: Array[float] = []
	var floor_sum := 0
	for s in shares:
		var f := int(floor(s))
		floors.append(f)
		remainders.append(s - float(f))
		floor_sum += f

	var leftover := xp_total - floor_sum
	var order: Array = range(shares.size())
	order.sort_custom(func(a, b): return remainders[a] > remainders[b])
	for i in leftover:
		floors[order[i]] += 1

	return floors
