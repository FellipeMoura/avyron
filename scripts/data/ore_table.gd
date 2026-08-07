class_name OreTable
extends RefCounted

## Tabela de minérios por mapa. Hardcoded enquanto o bundle do bestiário não
## exporta itens; quando exportar, substituir por leitura de BestiaryData.
##
## Estrutura: cada entrada tem "code", "name" e "weight" (peso relativo).
## A soma dos pesos não precisa ser 100; `sample` normaliza na hora.

const MAPS: Dictionary = {
	"PZ-01": [
		{"code": "ORE-001", "name": "Calcário",  "weight": 35},
		{"code": "ORE-002", "name": "Sílex",     "weight": 25},
		{"code": "ORE-003", "name": "Carvão",    "weight": 20},
		{"code": "ORE-004", "name": "Cobre",     "weight": 12},
		{"code": "ORE-005", "name": "Ferro",     "weight":  8},
	]
}

## Nome de exibição de um minério pelo código.
static func ore_name(code: String) -> String:
	for entries in MAPS.values():
		for e in entries:
			if str(e["code"]) == code:
				return str(e["name"])
	return code


## Sorteia um minério do mapa por amostragem de peso acumulado.
## Devolve dicionário vazio se o mapa não tiver entradas.
static func sample(rng: RandomNumberGenerator, map_code: String) -> Dictionary:
	var pool: Array = MAPS.get(map_code, [])
	if pool.is_empty():
		return {}
	var total := 0
	for e in pool:
		total += int(e["weight"])
	var roll := rng.randi() % total
	var acc := 0
	for e in pool:
		acc += int(e["weight"])
		if roll < acc:
			return e
	return pool[-1]
