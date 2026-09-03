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

## Chave única pra colisão de prop de bioma (2026-09-01, temporário). Desligada
## enquanto a densidade/porte do preenchimento ainda está sendo ajustado a
## olho. Os valores de `col_radius` continuam nos dados (`PZ01_LANDMARKS`);
## ligar de volta é só virar isto pra `true`, sem reautorar nada.
const PZ01_PROPS_COLLIDABLE := false

## Placeholder aliases de apoio: o mapa deve poder trocar por GLBs finais sem
## recriar o layout. Cada nome explícito e canônico fica aqui e é resolvido para
## um asset de teste (coral/rocha/aquático) até que o modelo definitivo chegue.
##
## `PZ01_PLACEHOLDER_REEF_HERO_01` existiu até 2026-09-01 e apontava pra
## `scenes/props/pz01_reef_hero_01.tscn` — um `.tscn` de recurso embutido que
## nunca chegou a carregar nesta versão do Godot (`Color(r,g,b)` de 3
## argumentos em `sub_resource`, que o parser 4.7.1 rejeita) e cujo fallback
## em `_place` também falhava (o caminho reconstruído saía malformado). Esse
## landmark nunca existiu de verdade em jogo — sempre foi `push_warning` e
## nada instanciado. Removido junto com o arquivo — item mecânico do plano de
## refinamento do PZ-01, Fase 2.
const PZ01_PLACEHOLDER_ROCK_HERO_01 := "PZ01_PLACEHOLDER_ROCK_HERO_01"
const PZ01_PLACEHOLDER_GLAZE_01 := "PZ01_PLACEHOLDER_GLAZE_01"

## Ambiência subaquática validada visualmente (ver README, "Assets 3D"):
## densidade acima de ~0.02 afoga as cores dos corais.
const PZ01_WATER_BG := Color("#062C3B")
## Neutro desde 2026-09-02 — era `#48B7B1` (teal), e por ser GLOBAL (mesma
## intensidade em terra firme e sob a água) tingia até a cor dos props/chão
## seco, que deveriam ler na cor própria deles. O frio da água agora vem só
## da névoa de altura logo abaixo (`PZ01_FOG`), que já era fragmentada por
## cota — luminância igual à do teal antigo, só sem matiz, pra não mudar o
## nível de exposição geral junto.
const PZ01_AMBIENT := Color("#959595")
const PZ01_FOG := Color("#163E61")
const PZ01_SUN := Color("#E9FFF8")

## A iluminação é FRAGMENTADA por altura, não por região: a névoa fria é
## densa ABAIXO da linha d'água (névoa de altura do Environment) e rala acima
## dela — o leito fica imerso na murk e a costa emerge para um ar mais limpo,
## sem precisar de segundo Environment. A linha fica logo abaixo do topo do
## platô (`MapTerrain.LAND_HEIGHT` = 1,6) para os pontos de acesso atravessarem a
## superfície no meio da subida.
const PZ01_WATER_LINE := 1.25
## A base vale para o mapa inteiro (inclusive a costa — um resto de maresia);
## a densidade subaquática precisa ser alta porque, na câmera ortográfica
## inclinada, o raio de visão atravessa POUCO da camada baixa: a acumulação
## vem quase toda destes ~2,5 m de caminho dentro da murk.
const PZ01_FOG_BASE_DENSITY := 0.006
const PZ01_FOG_UNDERWATER_DENSITY := 1.0

## O tom quente do trecho seco vem de luzes de preenchimento locais sobre a
## vila da costa — luz posicional é naturalmente fragmentada, então dá pra
## aquecer só ali sem mexer no sol/ambiente globais (neutros desde
## 2026-09-02, ver `PZ01_AMBIENT`). Sem sombra: são banho de cor, não fonte
## de leitura.
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
## ruído/inclinações).
##
## Era turquesa (`#67D0C0`/`#4DB4A4`) desde a Fase 1, lida da concept art de
## visão geral do mapa inteiro — mar raso turquesa, massa rochosa escura. Essa
## paleta nunca fechou com o kit de rocha real de BIO-002: postar prop marrom
## sobre chão turquesa lia como duas cenas coladas, e foi exatamente o que
## apareceu na captura de 2026-09-01 (chão claro, quase amarelo-esverdeado —
## a mistura de turquesa com a faixa seca antiga — contra rocha marrom-escura
## dos props). Trocada por uma rampa só, derivada da cor MÉDIA medida direto
## das texturas do kit (`Rocky_Plateau`/`Rocky_Outcrop`/`Cracked_*`, sonda
## direta: `#79674c`) — chão e rocha na mesma família de cor, de propósito.
## Isso também bate com um ponto já registrado em `BIOME_PROPS.md`: mar raso
## tem de ler mais simples que o recife, não igual — o mesmo kit visual dos
## dois biomas era parte do problema.
const PZ01_GROUND := {
	"color_base": Color("#8A7860"),
	"color_alt": Color("#6E5F49"),
	"color_slope": Color("#5A4E3C"),
	"color_coast": Color("#9C8868"),
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
	# Placeholders explícitos para a próxima iteração de GLBs do conceito.
	# Todos eles são resolvidos para um asset de teste equivalente sem mexer na
	# montagem do layout do mapa. O terceiro placeholder (hero do recife,
	# escala 8.0) saiu em 2026-09-01 junto com `pz01_reef_hero_01.tscn` — a
	# peça nunca renderizou nem uma vez (arquivo quebrado desde que foi
	# criado), então remover a linha não muda nada do que já estava em jogo.
	[PZ01_PLACEHOLDER_ROCK_HERO_01, Vector3(14, 0, -26), 2.4, 6.0, 1.4],
	[PZ01_PLACEHOLDER_GLAZE_01, Vector3(-26, 0, 22), 4.1, 5.0, 1.2],
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
	["Pastel_Tidepool_Treas", 1.4, 2.6],
	["Terraced_Stone_Mounds", 1.3, 2.5],
]

## Contagem e raios cresceram na proporção da ÁREA do anel de espalhamento
## no resize de 2026-08-28 (28 props num anel de 4–27 m; 116 num de 8–55 m),
## para a densidade visual do mapa não cair junto com o crescimento. É a
## medida que decide se um mapa maior lê como "maior" ou como "vazio".
const PZ01_SCATTER_COUNT := 116
const PZ01_SCATTER_SEED := 20260824
const SCATTER_RADIUS_MIN := 8.0
const SCATTER_RADIUS_MAX := 55.0

## Preenchimento denso do recife (BIO-003), pedido do usuário em 2026-09-02:
## o kit aquático inteiro é temático de mar raso/recife (nenhuma peça é
## glacial ou de mar profundo), e o recife deve ler MUITO mais cheio que o
## resto do mar raso — metade da escala normal, pra caber em quantidade sem
## virar amontoado de peças grandes se sobrepondo. Mesmos nomes do pool
## geral, só os pares min/max de escala divididos por 2.
const PZ01_REEF_SCATTER_POOL: Array = [
	["Emerald_Seaweed_Grove", 1.25, 2.25],
	["Seafoam_Pipe_Coral", 0.75, 1.25],
	["Aqua_Coral_Garden", 0.9, 1.5],
	["Reef_Cluster", 0.6, 1.1],
	["Aqua_Sponge_Cluster", 0.75, 1.25],
	["Aqua_Bloom_Grove", 0.75, 1.25],
	["Pastel_Tidepool_Treas", 0.7, 1.3],
	["Terraced_Stone_Mounds", 0.65, 1.25],
]
const PZ01_REEF_SCATTER_COUNT := 140
const PZ01_REEF_SCATTER_SEED := 20260902
## Bem mais apertado que `CLEAR_RADIUS` (3,5 m) de propósito — é o que faz o
## recife ler denso em vez de espalhado; peça pela metade do porte cabe em
## separação menor sem colar.
const PZ01_REEF_MIN_SEP := 1.4

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


static func apply(root: Node3D, map_code: String, terrain: MapTerrain = null, map_biomes: MapBiomes = null) -> void:
	if map_code != "PZ-01":
		return

	_apply_pz01_ambience(root)

	var holder := Node3D.new()
	holder.name = "Dressing"
	root.add_child(holder)

	var clear_spots := _clear_spots()
	var occupied: Array[Vector3] = clear_spots.duplicate()
	for l in PZ01_LANDMARKS:
		# O kit aquático inteiro é temático de mar raso/recife — nenhuma peça
		# dele é glacial ou de mar profundo (pedido do usuário, 2026-09-02).
		# A costa (BIO-002) já não tem landmark nenhum desde a Fase 2; aqui é
		# só filtrar as duas geografias que ainda tinham peça por acidente de
		# posição, não por intenção.
		if map_biomes and _is_excluded_biome(map_biomes.biome_at(l[1])):
			continue
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
		if map_biomes and _is_excluded_biome(map_biomes.biome_at(pos)):
			continue
		if _too_close(pos, occupied):
			continue
		var pick: Array = PZ01_SCATTER_POOL[rng.randi() % PZ01_SCATTER_POOL.size()]
		_place(holder, terrain, pick[0], pos, rng.randf() * TAU, rng.randf_range(pick[1], pick[2]), 0.0)
		occupied.append(pos)
		placed += 1

	# Preenchimento denso do recife (BIO-003) por cima do scatter geral acima
	# — amostra por REJEIÇÃO sobre a própria partição de bioma (`biome_at`),
	# não um círculo recalculado aqui: a forma/posição do recife é dado do
	# catálogo, e duplicar isso em geometria própria é a mesma classe de erro
	# que `REEF_CENTER` já cometeu uma vez (ver `map_terrain.gd`). Raio de
	# amostragem parte de 0 (não de `SCATTER_RADIUS_MIN`) porque o recife
	# encosta perto da origem; `on_island`/`on_coast` acima de qualquer forma
	# protegem os dois trechos que não são recife mesmo perto do centro.
	var reef_rng := RandomNumberGenerator.new()
	reef_rng.seed = PZ01_REEF_SCATTER_SEED
	var reef_placed := 0
	var reef_attempts := 0
	while reef_placed < PZ01_REEF_SCATTER_COUNT and reef_attempts < PZ01_REEF_SCATTER_COUNT * 25:
		reef_attempts += 1
		var angle := reef_rng.randf() * TAU
		var dist := reef_rng.randf_range(0.0, SCATTER_RADIUS_MAX)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if terrain and (terrain.on_coast(pos) or terrain.on_island(pos, 1.5)):
			continue
		if map_biomes == null or map_biomes.biome_at(pos) != "BIO-003":
			continue
		if _too_close(pos, occupied, PZ01_REEF_MIN_SEP):
			continue
		var pick: Array = PZ01_REEF_SCATTER_POOL[reef_rng.randi() % PZ01_REEF_SCATTER_POOL.size()]
		_place(holder, terrain, pick[0], pos, reef_rng.randf() * TAU, reef_rng.randf_range(pick[1], pick[2]), 0.0)
		occupied.append(pos)
		reef_placed += 1


## Pontos que o cenário deve deixar livres: origem do jogador e os pontos
## fixos do `WorldPopulator`.
static func _clear_spots() -> Array[Vector3]:
	return [
		Vector3.ZERO,
		WorldPopulator.PLAYER_START_SPOT,
		WorldPopulator.MERCHANT_SPOT,
		WorldPopulator.CRAFTING_BENCH_SPOT,
		WorldPopulator.RELIC_STATION_SPOT,
		WorldPopulator.ARENA_SPOT,
		WorldPopulator.PORTAL_SPOT,
	]


static func _too_close(pos: Vector3, occupied: Array[Vector3], radius: float = CLEAR_RADIUS) -> bool:
	for o in occupied:
		if pos.distance_to(o) < radius:
			return true
	return false


## O kit aquático (`AQUA_KIT`) é temático de mar raso/recife — pedido do
## usuário, 2026-09-02: nenhuma peça dele pertence ao platô glacial
## (BIO-014, tem textura de gelo própria desde então) nem ao Mar Profundo
## (BIO-004). `DEFAULT_BIOME` nunca aparece aqui por ser fallback de dado
## faltando, não bioma real (ver `CLAUDE.md`) — só os dois códigos abaixo.
static func _is_excluded_biome(biome_code: String) -> bool:
	return biome_code == "BIO-014" or biome_code == "BIO-004"


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
	# AO real (SSAO), não luz achatada — era uma das lacunas visuais
	# originais do bioma (bio-002-costa-primordial.md, 3.5): sem AO, fenda
	# entre rochas e base de prop leem plano na câmera ortográfica, porque não
	# há sombra projetada de uma fonte única sustentando o volume sozinha.
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_power = 1.5
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
## Sem especular pelo mesmo motivo (2026-09-02): mantém só a contribuição
## difusa do banho de cor. NÃO era a causa da bolha branca reportada no mesmo
## dia — essa hipótese (hotspot na água espelhada) foi descartada depois de
## testada; a causa real era `_flatten_specular` (ver comentário lá). Fica
## desligado mesmo assim, por ser consistente com "banho de cor, não fonte
## de leitura" e não ter custo.
static func _add_fill_light(root: Node3D, node_name: String, pos: Vector3, light_range: float) -> void:
	var fill := OmniLight3D.new()
	fill.name = node_name
	fill.position = pos
	fill.light_color = PZ01_COAST_LIGHT
	fill.light_energy = PZ01_COAST_LIGHT_ENERGY
	fill.omni_range = light_range
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	root.add_child(fill)


static func _resolve_asset(file: String) -> String:
	var alias := {
		PZ01_PLACEHOLDER_ROCK_HERO_01: "Aqua_Coral_Garden",
		PZ01_PLACEHOLDER_GLAZE_01: "Aqua_Sponge_Cluster",
	}
	var resolved: String = alias.get(file, file)
	if resolved.begins_with("res://") or resolved.contains("/") or resolved.ends_with(".glb") or resolved.ends_with(".tscn") or resolved.ends_with(".scn"):
		return resolved
	return resolved


## O kit aquático veio do Meshy com `_metallic_roughness.jpg`/`_normal.jpg`
## próprios (anterior à regra de cel-shading do `BIOME_PROPS.md`, "sem normal
## map, sem specular, sem roughness" — só o kit mais novo nasceu já seguindo
## ela). Sem isto, o `KeyLight` (única luz do mapa com sombra, energia 1.35)
## acende reflexo especular real nessas peças — visível como pontos de brilho
## alheios ao resto do cel-shading, achado em 2026-09-02 depois de a costa
## esvaziar (kit de BIO-002 removido) deixar essas peças mais expostas.
## Muta o material importado (compartilhado por todas as instâncias do mesmo
## `.glb`, via cache de recurso do Godot) em vez de duplicar por instância —
## é exatamente o efeito desejado (o kit inteiro achatado) e evita criar um
## `Material` novo por prop colocado.
##
## Sonda direta (`probe_aqua_materials.gd`, descartada depois) achou o motivo
## da primeira versão não ter resolvido: `roughness = 1.0` não fazia nada,
## porque 1,0 já É o fator default do glTF quando existe textura de
## roughness — o valor final no shader é `fator × textura`, e a textura (com
## pontos baixos = brilhante) passava direto. Faltava também zerar
## `metallic_specular` (o brilho dielétrico, 0,5 por padrão, não depende de
## `metallic`) — ele sozinho já bastava pra acender hotspot em superfície
## curva sob o sol, com `metallic` em zero ou não. Versão final limpa as
## DUAS texturas (`roughness_texture`/`metallic_texture`, senão o fator não
## tem efeito nenhum) e zera `metallic_specular` junto.
static func _flatten_specular(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is BaseMaterial3D:
					var flat := mat as BaseMaterial3D
					flat.metallic = 0.0
					flat.metallic_texture = null
					flat.metallic_specular = 0.0
					flat.roughness = 1.0
					flat.roughness_texture = null
					flat.normal_enabled = false
	for child in node.get_children():
		_flatten_specular(child)


static func _place(
	parent: Node3D,
	terrain: MapTerrain,
	file: String,
	pos: Vector3,
	yaw: float,
	prop_scale: float,
	col_radius: float
) -> void:
	var resolved := _resolve_asset(file)
	var packed: PackedScene = null
	var scene_path := resolved
	if not scene_path.begins_with("res://"):
		if scene_path.contains("/"):
			scene_path = "res://" + scene_path
		else:
			scene_path = AQUA_KIT + scene_path + ".glb"
	packed = load(scene_path) as PackedScene
	if packed == null:
		push_warning("MapDressing: prop ausente %s (resolved %s) — rode pnpm game:export no bestiario" % [file, scene_path])
		return
	# Apoiado no relevo, meio palmo afundado — prop de borda de colina com a
	# base 100% exposta mostraria o corte reto da malha do Meshy.
	if terrain:
		pos.y = terrain.height_at(pos) - 0.05 * prop_scale
	var node := packed.instantiate() as Node3D
	_flatten_specular(node)
	node.position = pos
	node.rotation.y = yaw
	node.scale = Vector3.ONE * prop_scale
	parent.add_child(node)

	# Colisão só nos landmarks maciços, como cilindro simples — o jogador e
	# as criaturas (CharacterBody3D) deslizam ao redor em vez de atravessar
	# uma rocha do próprio tamanho. Desligada por enquanto (`PZ01_PROPS_COLLIDABLE`).
	if col_radius > 0.0 and PZ01_PROPS_COLLIDABLE:
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
