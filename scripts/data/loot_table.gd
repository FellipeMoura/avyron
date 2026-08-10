class_name LootTable
extends RefCounted

## Sorteio de drops de uma criatura derrotada.
##
## Diferente de `MiningTable.distribution` (que sorteia exatamente **um**
## vencedor entre pesos normalizados), cada entrada de `drops` é um evento
## independente: uma criatura pode largar zero, um ou vários itens na mesma
## derrota, e a chance de um não afeta a chance do outro. Não há distribuição
## pra normalizar aqui.
##
## Especificação: bloco `drops` de cada criatura no bundle (`itemCode`,
## `chance`, `condition`). Tuning: `POST /drops` no bestiário.


## Rola cada drop independentemente e devolve os `itemCode` que caíram.
## Pode devolver vazio — falhar todos os rolls é o resultado mais comum
## quando as chances são baixas, não um bug.
static func roll(rng: RandomNumberGenerator, drops: Array) -> Array[String]:
	var won: Array[String] = []
	if rng == null:
		return won
	for drop in drops:
		var chance := float(drop.get("chance", 0.0))
		if chance <= 0.0:
			continue
		if rng.randf() < chance:
			won.append(str(drop.get("itemCode", "")))
	return won
