class_name MapBiomes
extends RefCounted

## Em que bioma este ponto do mapa está.
##
## Substitui a declaração única que o mundo fazia (`WorldRoot.DEFAULT_BIOME`,
## um bioma para os 3.600 m² inteiros) pela partição que o catálogo já
## descrevia e ninguém lia: `map_biome_regions`, que chega no bundle como
## `maps[].biomeRegions`.
##
## ## Coordenadas normalizadas, e por que isso importa
##
## As regiões vêm em ±1 sobre o MEIO-LADO do mapa, não em metros. É o que faz
## a partição sobreviver a um redimensionamento do terreno: crescer o
## `MapTerrain.SIZE` reposiciona todas as fronteiras junto, na mesma proporção,
## sem reescrever uma linha de catálogo. Quem sabe quantos metros o mapa tem é
## o terreno, e é dele que o `half_side` vem — o bundle não sabe e não deve
## saber.
##
## O preço dessa escolha é que as notas do catálogo amarram números normalizados
## a constantes daqui (`-0.533` é o `COAST_RAMP_START` sobre 30 m). Se o mapa
## mudar de tamanho SEM que as fronteiras devam acompanhar — por exemplo,
## alargar só o mar aberto mantendo a costa nos mesmos 16 m —, aí sim a região
## precisa ser reautorada. Redimensionar é grátis; redesenhar não é.
##
## ## Primeira que contém, ganha
##
## A avaliação é na ordem de `sortOrder` do catálogo, e para na primeira região
## que contém o ponto. É o que deixa uma região pequena e específica (a ilha, o
## recife) se sobrepor a uma grande e genérica sem precisar de recorte
## geométrico: a específica só precisa vir antes. A última costuma ser um
## catch-all cobrindo o mapa inteiro, e é ele que garante cobertura total por
## construção.
##
## Ponto que não cai em região nenhuma devolve `""`, e o silêncio é
## deliberado: quem pergunta é a mineração, a cada tecla, e um `push_warning`
## por consulta viraria enxurrada. O buraco é denunciado **uma vez, na
## montagem**, por `coverage_report()` — que é o que `test_data` cobra.

## Formas que o catálogo pode usar. Forma desconhecida não é ignorada em
## silêncio: ela sairia como "região que nunca contém nada", e o bioma dela
## ficaria inalcançável exatamente como um bioma sem região — o modo de falha
## que este arquivo inteiro existe para tornar visível.
const SHAPES := ["band", "circle", "rect"]

var _regions: Array = []
var _half_side := 1.0
var _map_code := ""
## Biomas que o mapa lista, para a conferência de alcançabilidade.
var _map_biomes: Array = []


## Constrói a partição de um mapa. `half_side` é o meio-lado do terreno em
## metros (`MapTerrain.SIZE * 0.5`) — o divisor que traduz metro em ±1.
static func create(db: BestiaryData, map_code: String, half_side: float) -> MapBiomes:
	var mb := MapBiomes.new()
	mb._map_code = map_code
	mb._half_side = maxf(half_side, 0.001)
	if db == null:
		return mb
	mb._map_biomes = db.biomes_in_map(map_code)
	for r in db.biome_regions_in_map(map_code):
		if r is Dictionary and SHAPES.has(str(r.get("shape", ""))):
			mb._regions.append(r)
		else:
			push_warning(
				"MapBiomes: regiao %s do mapa %s tem shape desconhecido %s — ignorada" %
				[str(r.get("code", "?")), map_code, str(r.get("shape", "?"))])
	return mb


## O bioma deste ponto, ou `""` se nenhuma região o contém.
##
## O `y` é ignorado de propósito: a partição é do PLANO. Bioma por altura seria
## outra coisa (e o mapa já tem uma que funciona assim — a névoa), mas misturar
## as duas faria a mesma posição responder dois biomas conforme o jogador
## estivesse nadando ou pisando o fundo.
func biome_at(world_pos: Vector3) -> String:
	var nx := world_pos.x / _half_side
	var nz := world_pos.z / _half_side
	for r in _regions:
		if _contains(r, nx, nz):
			return str(r.get("biome", ""))
	return ""


## Esta região contém o ponto normalizado?
func _contains(region: Dictionary, nx: float, nz: float) -> bool:
	var p: Dictionary = region.get("params", {}) if region.get("params") is Dictionary else {}
	match str(region.get("shape", "")):
		"band":
			# `from`/`to` aceitam qualquer ordem. Uma banda invertida daria
			# região vazia — o mesmo sintoma mudo de um bioma sem região —, e
			# não há leitura em que a ordem dos dois signifique coisas
			# diferentes.
			var v := nz if str(p.get("axis", "z")) == "z" else nx
			var a := float(p.get("from", -1.0))
			var b := float(p.get("to", 1.0))
			return v >= minf(a, b) and v <= maxf(a, b)
		"circle":
			var d := Vector2(nx - float(p.get("cx", 0.0)), nz - float(p.get("cz", 0.0)))
			return d.length() <= float(p.get("r", 0.0))
		"rect":
			var x0 := float(p.get("x0", -1.0))
			var x1 := float(p.get("x1", 1.0))
			var z0 := float(p.get("z0", -1.0))
			var z1 := float(p.get("z1", 1.0))
			return (nx >= minf(x0, x1) and nx <= maxf(x0, x1)
				and nz >= minf(z0, z1) and nz <= maxf(z0, z1))
	return false


func has_partition() -> bool:
	return not _regions.is_empty()


func region_count() -> int:
	return _regions.size()


## Biomas efetivamente alcançáveis, na ordem em que as regiões os reivindicam.
func reachable_biomes() -> Array:
	var out: Array = []
	for r in _regions:
		var b := str(r.get("biome", ""))
		if b != "" and not out.has(b):
			out.append(b)
	return out


## Biomas que o mapa lista e nenhuma região reivindica — eles existem no
## catálogo e o jogador nunca pisa neles. O exportador avisa do lado de lá; a
## conferência existe aqui também porque bundle e jogo podem divergir de
## versão, e é o jogo que sofre.
func unreachable_biomes() -> Array:
	var claimed := reachable_biomes()
	var out: Array = []
	for b in _map_biomes:
		if not claimed.has(str(b)):
			out.append(str(b))
	return out


## Varre o mapa numa grade e conta os pontos que não caem em região nenhuma.
##
## Existe porque cobertura total é uma promessa que só o catch-all sustenta, e
## nada obriga o catálogo a ter um: apagar a região catch-all não quebra nada
## visível — a mineração só passa a cair no fallback declarado, com outra
## distribuição, meses depois. Uma varredura de alguns milhares de pontos custa
## nada e é a única forma de provar a promessa em vez de confiar nela.
##
## `step` em metros. Devolve `{total, uncovered, worst}` — `worst` é um dos
## pontos descobertos, para a mensagem poder dizer ONDE.
func coverage_report(step: float = 2.0) -> Dictionary:
	var total := 0
	var uncovered := 0
	var worst := Vector2.ZERO
	var s := maxf(step, 0.25)
	var v := -_half_side
	while v <= _half_side:
		var u := -_half_side
		while u <= _half_side:
			total += 1
			if biome_at(Vector3(u, 0.0, v)) == "":
				uncovered += 1
				worst = Vector2(u, v)
			u += s
		v += s
	return {"total": total, "uncovered": uncovered, "worst": worst}
