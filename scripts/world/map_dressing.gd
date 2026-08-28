class_name MapDressing
extends RefCounted

## Veste o mapa: ambiente (névoa, luz, chão) e props de cenário por mapa.
##
## Mesmo padrão de `WorldPopulator` — `RefCounted` com funções `static`,
## chamado uma vez por `WorldRoot._ready()`, sem estado depois de vestir.
## Tudo aqui é apresentação pura: nenhum prop emite sinal, dá drop ou entra
## em fórmula. As constantes de cor/névoa são "constantes de apresentação"
## na exceção da regra 1 do CLAUDE.md, não tuning de gameplay.
##
## Layout é posição de cena, não de bestiário — mesmo raciocínio de
## `MERCHANT_SPOT`: o catálogo diz que o PZ-01 é o Mundo dos Mares; ONDE cada
## recife fica é decisão do mundo. Os landmarks são fixos à mão; a vegetação
## miúda é espalhada com semente fixa (mesmo motivo do `spawn_seed` do
## `CreatureSpawner`: mapa que muda a cada play atrapalha comparar execuções).

const AQUA_KIT := "res://models/biomes/aquatic/"

## Ambiência subaquática validada visualmente (ver README, "Assets 3D"):
## densidade acima de ~0.02 afoga as cores dos corais.
const PZ01_WATER_BG := Color("#0E3D4A")
const PZ01_AMBIENT := Color("#4E8896")
const PZ01_FOG := Color("#1A5D6C")
const PZ01_SUN := Color("#CFEFE8")

## A iluminação é FRAGMENTADA por altura, não por região: a névoa fria é
## densa ABAIXO da linha d'água (névoa de altura do Environment) e rala acima
## dela — o leito fica imerso na murk e a costa emerge para um ar mais limpo,
## sem precisar de segundo Environment. A linha fica logo abaixo do topo do
## platô (`MapTerrain.COAST_HEIGHT` = 1,6) para a rampa atravessar a
## superfície no meio da subida.
const PZ01_WATER_LINE := 1.25
## A base vale para o mapa inteiro (inclusive a costa — um resto de maresia);
## a densidade subaquática precisa ser alta porque, na câmera ortográfica
## inclinada, o raio de visão atravessa POUCO da camada baixa: a acumulação
## vem quase toda destes ~2,5 m de caminho dentro da murk.
const PZ01_FOG_BASE_DENSITY := 0.006
const PZ01_FOG_UNDERWATER_DENSITY := 1.0

## O tom quente do trecho seco vem de luzes de preenchimento locais sobre a
## vila da costa — luz posicional é naturalmente fragmentada, então o sol e o
## ambiente globais continuam frios para o mar. Sem sombra: são banho de cor,
## não fonte de leitura.
const PZ01_COAST_LIGHT := Color("#FFD9A6")
const PZ01_COAST_LIGHT_ENERGY := 1.1
const PZ01_COAST_LIGHT_RANGE := 13.0
const PZ01_COAST_LIGHT_SPOTS: Array = [Vector3(2.0, 5.5, -46.0), Vector3(10.0, 5.5, -46.5)]
## A ilha da arena recebe o mesmo banho quente pela mesma regra: chão que
## emerge sai da murk também na luz. Uma omni só, centrada — o platô inteiro
## cabe no alcance.
const PZ01_ISLAND_LIGHT_SPOT := Vector3(0.0, 6.0, 0.0)
const PZ01_ISLAND_LIGHT_RANGE := 12.0

## Paleta do solo, consumida pelo shader do `MapTerrain` (base/variação por
## ruído/inclinações). Leito de areia com encostas em rocha esverdeada.
const PZ01_GROUND := {
	"color_base": Color("#8A8264"),
	"color_alt": Color("#7A7A5E"),
	"color_slope": Color("#5C6B5E"),
	"color_coast": Color("#B3A47C"),
}

## Landmarks fixos: [arquivo, posição, yaw, escala, raio de colisão].
## Raio 0 = atravessável (o arco é passagem por baixo de propósito). Os
## modelos do Meshy chegam normalizados em ~1×1×1 — a escala aqui é o porte.
## Posições evitam os pontos fixos do `WorldPopulator` e a origem do jogador.
##
## O MIOLO ficou vazio de coral quando a ilha subiu ali: seis peças que
## estavam entre 4 e 8 m do centro foram para o anel de 11–15 m, onde
## continuam sendo recife submerso. Coral apoiado na encosta seca da ilha
## seria a mesma contradição que a costa já não comete.
##
## No resize de 2026-08-28 as posições do MAR dobraram junto com o mapa e as
## DUAS da ilha não — a ilha não escalou, e uma pedra de silhueta que saísse
## de cima dela deixaria de ser silhueta de coisa nenhuma. O anel de recife
## foi de 11–15 m para 22–30 m, que é o raio que a região RGN-002 do catálogo
## descreve em coordenada normalizada (`r 0.5`) — e é por isso que aquela
## linha do catálogo não precisou ser reautorada.
const PZ01_LANDMARKS: Array = [
	["Coralstone_Arch", Vector3(6, 0, -30), 0.4, 9.0, 0.0],
	["Coralstone_Arch", Vector3(-36, 0, 28), 2.0, 7.0, 0.0],
	["Turquoise_Reef_Stone", Vector3(-26, 0, -18), 1.2, 5.0, 2.2],
	["Turquoise_Reef_Stone", Vector3(32, 0, 24), 0.3, 4.0, 1.8],
	["Jade_Reef_Garden", Vector3(28, 0, -8), 2.6, 4.0, 1.8],
	["Jade_Reef_Garden", Vector3(-40, 0, -4), 5.0, 3.2, 1.5],
	["Terraced_Stone_Mounds", Vector3(-12, 0, 24), 5.2, 3.8, 1.6],
	["Terraced_Stone_Mounds", Vector3(24, 0, -28), 1.0, 3.0, 1.3],
	["Aqua_Bloom_Grove", Vector3(22, 0, 10), 4.0, 3.5, 1.5],
	["Pastel_Tidepool_Treas", Vector3(-24, 0, 12), 3.1, 3.0, 1.3],
	["Aqua_Coral_Garden", Vector3(6, 0, 24), 0.9, 3.2, 0.0],
	["Aqua_Sponge_Cluster", Vector3(18, 0, 20), 1.7, 2.6, 0.0],
	["Seafoam_Pipe_Coral", Vector3(20, 0, -16), 0.0, 2.8, 0.0],
	["Reef_Cluster", Vector3(-22, 0, -8), 0.6, 2.4, 0.0],
	# Na ilha: duas pedras miúdas no topo, uma de cada lado da arena. São
	# silhueta — sem elas o platô lê como bolha de terreno em vez de rochedo,
	# e é a silhueta que a câmera ortográfica dá ao jogador de longe. Porte
	# pequeno de propósito: peça grande aqui esconderia o duelista.
	# As duas são o MESMO modelo em porte e giro diferentes, e isso é escolha:
	# `Terraced_Stone_Mounds` é a única peça do kit que lê como rocha em vez de
	# coral. Um coral de pé em terra seca contradiz a ilha inteira — foi o que
	# a primeira captura mostrou, com um recife turquesa ao lado do duelista.
	["Terraced_Stone_Mounds", Vector3(3.4, 0, 1.6), 0.8, 2.2, 1.0],
	["Terraced_Stone_Mounds", Vector3(-3.4, 0, -1.2), 2.3, 2.6, 0.9],
]

## Vegetação miúda espalhada por semente: [arquivo, escala mín, escala máx].
## Nada aqui tem colisão — pisar numa alga é pisar numa alga.
const PZ01_SCATTER_POOL: Array = [
	["Emerald_Seaweed_Grove", 2.5, 4.5],
	["Seafoam_Pipe_Coral", 1.5, 2.5],
	["Aqua_Coral_Garden", 1.8, 3.0],
	["Reef_Cluster", 1.2, 2.2],
	["Aqua_Sponge_Cluster", 1.5, 2.5],
	["Aqua_Bloom_Grove", 1.5, 2.5],
]
## Contagem e raios cresceram na proporção da ÁREA do anel de espalhamento
## no resize de 2026-08-28 (28 props num anel de 4–27 m; 116 num de 8–55 m),
## para a densidade visual do mapa não cair junto com o crescimento. É a
## medida que decide se um mapa maior lê como "maior" ou como "vazio".
const PZ01_SCATTER_COUNT := 116
const PZ01_SCATTER_SEED := 20260824
const SCATTER_RADIUS_MIN := 8.0
const SCATTER_RADIUS_MAX := 55.0

## Nenhum prop nasce a menos disto dos pontos de interação/origem — cenário
## não pode esconder um serviço nem entulhar o spawn do jogador.
const CLEAR_RADIUS := 3.5


## Paleta do solo deste mapa, para o `MapTerrain` — vazia = shader nos
## defaults. Vive aqui (e não no terreno) porque cor de bioma é vestimenta.
static func ground_palette(map_code: String) -> Dictionary:
	return PZ01_GROUND if map_code == "PZ-01" else {}


## Cota da superfície da água deste mapa; `-INF` = mapa seco.
##
## Mesmo raciocínio da paleta: onde fica a superfície é decisão de bioma, e o
## terreno só a consome. A cota é a MESMA que fragmenta a névoa, e tem de
## continuar sendo: se o jogador nadasse numa cota e a murk trocasse noutra, a
## imagem contradiria o corpo na rampa da costa.
static func water_line(map_code: String) -> float:
	return PZ01_WATER_LINE if map_code == "PZ-01" else -INF


static func apply(root: Node3D, map_code: String, terrain: MapTerrain = null) -> void:
	if map_code != "PZ-01":
		return

	_apply_pz01_ambience(root)

	var holder := Node3D.new()
	holder.name = "Dressing"
	root.add_child(holder)

	var occupied: Array[Vector3] = _clear_spots()
	for l in PZ01_LANDMARKS:
		_place(holder, terrain, l[0], l[1], l[2], l[3], l[4])
		occupied.append(l[1])

	var rng := RandomNumberGenerator.new()
	rng.seed = PZ01_SCATTER_SEED
	var placed := 0
	var attempts := 0
	while placed < PZ01_SCATTER_COUNT and attempts < PZ01_SCATTER_COUNT * 12:
		attempts += 1
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(SCATTER_RADIUS_MIN, SCATTER_RADIUS_MAX)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		# A costa fica sem bioma natural — é o adro dos NPCs e portais. A ilha
		# também: o que cresce nela são as duas pedras fixas acima, postas à
		# mão. Margem de 1,5 m para nenhuma alga nascer encostada na saia.
		if terrain and (terrain.on_coast(pos) or terrain.on_island(pos, 1.5)):
			continue
		if _too_close(pos, occupied):
			continue
		var pick: Array = PZ01_SCATTER_POOL[rng.randi() % PZ01_SCATTER_POOL.size()]
		_place(holder, terrain, pick[0], pos, rng.randf() * TAU, rng.randf_range(pick[1], pick[2]), 0.0)
		occupied.append(pos)
		placed += 1


## Pontos que o cenário deve deixar livres: origem do jogador e os pontos
## fixos do `WorldPopulator`.
static func _clear_spots() -> Array[Vector3]:
	return [
		Vector3.ZERO,
		WorldPopulator.MERCHANT_SPOT,
		WorldPopulator.RELIC_STATION_SPOT,
		WorldPopulator.ARENA_SPOT,
		WorldPopulator.PORTAL_SPOT,
	]


static func _too_close(pos: Vector3, occupied: Array[Vector3]) -> bool:
	for o in occupied:
		if pos.distance_to(o) < CLEAR_RADIUS:
			return true
	return false


static func _apply_pz01_ambience(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = PZ01_WATER_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = PZ01_AMBIENT
	env.ambient_light_energy = 1.35
	env.fog_enabled = true
	env.fog_light_color = PZ01_FOG
	# Névoa de altura: densa abaixo da linha d'água, quase nada acima. O sinal
	# POSITIVO de `fog_height_density` é o que faz a névoa engrossar para
	# BAIXO da cota — invertido, a costa afogaria e o mar clarearia.
	env.fog_density = PZ01_FOG_BASE_DENSITY
	env.fog_height = PZ01_WATER_LINE
	env.fog_height_density = PZ01_FOG_UNDERWATER_DENSITY
	var we := WorldEnvironment.new()
	we.name = "Ambience"
	we.environment = env
	root.add_child(we)

	# A luz já existe em `main.tscn`; aqui só recebe o banho de cor do bioma.
	# Se a cena mudar o nome do nó, o mapa fica com a luz neutra — degradação
	# silenciosa aceitável para apresentação. O CHÃO não é mais pintado aqui:
	# o `MapTerrain` é dono do material do solo, com a paleta que
	# `ground_palette` fornece.
	var key := root.get_node_or_null("KeyLight") as DirectionalLight3D
	if key:
		key.light_color = PZ01_SUN
		key.light_energy = 1.35
		key.shadow_enabled = true

	# O banho quente do trecho seco. Omnis largas sobre a vila da costa: quem
	# sobe a rampa entra no alcance delas e "sai da água" também na luz.
	for i in PZ01_COAST_LIGHT_SPOTS.size():
		_add_fill_light(root, "CoastFill%d" % i, PZ01_COAST_LIGHT_SPOTS[i],
			PZ01_COAST_LIGHT_RANGE)
	_add_fill_light(root, "IslandFill", PZ01_ISLAND_LIGHT_SPOT, PZ01_ISLAND_LIGHT_RANGE)


## Uma omni de preenchimento sobre chão emerso. Sem sombra de propósito: é
## banho de cor, não fonte de leitura — quem desenha volume aqui é o sol.
static func _add_fill_light(root: Node3D, node_name: String, pos: Vector3, light_range: float) -> void:
	var fill := OmniLight3D.new()
	fill.name = node_name
	fill.position = pos
	fill.light_color = PZ01_COAST_LIGHT
	fill.light_energy = PZ01_COAST_LIGHT_ENERGY
	fill.omni_range = light_range
	fill.shadow_enabled = false
	root.add_child(fill)


static func _place(
	parent: Node3D,
	terrain: MapTerrain,
	file: String,
	pos: Vector3,
	yaw: float,
	prop_scale: float,
	col_radius: float
) -> void:
	var packed := load(AQUA_KIT + file + ".glb") as PackedScene
	if packed == null:
		push_warning("MapDressing: prop ausente %s — rode pnpm game:export no bestiario" % file)
		return
	# Apoiado no relevo, meio palmo afundado — prop de borda de colina com a
	# base 100% exposta mostraria o corte reto da malha do Meshy.
	if terrain:
		pos.y = terrain.height_at(pos) - 0.05 * prop_scale
	var node := packed.instantiate() as Node3D
	node.position = pos
	node.rotation.y = yaw
	node.scale = Vector3.ONE * prop_scale
	parent.add_child(node)

	# Colisão só nos landmarks maciços, como cilindro simples — o jogador e
	# as criaturas (CharacterBody3D) deslizam ao redor em vez de atravessar
	# uma rocha do próprio tamanho.
	if col_radius > 0.0:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = col_radius
		cyl.height = maxf(2.0, prop_scale)
		shape.shape = cyl
		shape.position.y = cyl.height * 0.5
		body.add_child(shape)
		parent.add_child(body)
