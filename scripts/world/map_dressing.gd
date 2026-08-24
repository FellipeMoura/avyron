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
const PZ01_FOG_DENSITY := 0.011
const PZ01_SUN := Color("#CFEFE8")

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
const PZ01_LANDMARKS: Array = [
	["Coralstone_Arch", Vector3(2, 0, -11), 0.4, 9.0, 0.0],
	["Coralstone_Arch", Vector3(-18, 0, 14), 2.0, 7.0, 0.0],
	["Turquoise_Reef_Stone", Vector3(-13, 0, -9), 1.2, 5.0, 2.2],
	["Turquoise_Reef_Stone", Vector3(16, 0, 12), 0.3, 4.0, 1.8],
	["Jade_Reef_Garden", Vector3(14, 0, -4), 2.6, 4.0, 1.8],
	["Jade_Reef_Garden", Vector3(-20, 0, -2), 5.0, 3.2, 1.5],
	["Terraced_Stone_Mounds", Vector3(-1, 0, -5), 5.2, 3.8, 1.6],
	["Terraced_Stone_Mounds", Vector3(12, 0, -14), 1.0, 3.0, 1.3],
	["Aqua_Bloom_Grove", Vector3(7, 0, 5), 4.0, 3.5, 1.5],
	["Pastel_Tidepool_Treas", Vector3(-12, 0, 6), 3.1, 3.0, 1.3],
	["Aqua_Coral_Garden", Vector3(-4, 0, 4), 0.9, 3.2, 0.0],
	["Aqua_Sponge_Cluster", Vector3(-2, 0, 7), 1.7, 2.6, 0.0],
	["Seafoam_Pipe_Coral", Vector3(4, 0, 1.5), 0.0, 2.8, 0.0],
	["Reef_Cluster", Vector3(-4, 0, -3), 0.6, 2.4, 0.0],
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
const PZ01_SCATTER_COUNT := 28
const PZ01_SCATTER_SEED := 20260824
const SCATTER_RADIUS_MIN := 4.0
const SCATTER_RADIUS_MAX := 27.0

## Nenhum prop nasce a menos disto dos pontos de interação/origem — cenário
## não pode esconder um serviço nem entulhar o spawn do jogador.
const CLEAR_RADIUS := 3.5


## Paleta do solo deste mapa, para o `MapTerrain` — vazia = shader nos
## defaults. Vive aqui (e não no terreno) porque cor de bioma é vestimenta.
static func ground_palette(map_code: String) -> Dictionary:
	return PZ01_GROUND if map_code == "PZ-01" else {}


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
		# A costa fica sem bioma natural — é o adro dos NPCs e portais.
		if terrain and terrain.on_coast(pos):
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
	env.fog_density = PZ01_FOG_DENSITY
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
