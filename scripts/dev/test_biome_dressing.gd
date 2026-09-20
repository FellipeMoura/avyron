extends SceneTree

## Vestimenta viva do PZ-01: ambiência por bioma, balanço de corrente e
## scatter em manchas de espécie, e a costa em camadas com props (Fase A do
## enriquecimento de bioma do PZ-01, 2026-09-17).
##
##     godot --headless --script res://scripts/dev/test_biome_dressing.gd
##
## Três blocos, cada um provando uma coisa que a imagem mostraria errada sem
## nenhum outro teste reclamar:
##
##   1. **Bancada do `BiomeAmbience`** — sem mundo, `_process` à mão: a
##      interpolação chega no alvo, não salta na abertura nem na interrupção.
##   2. **O mundo de verdade** — o `WorldRoot` avisa a ambiência a cada
##      travessia (sonda nos cinco biomas), o balanço caiu só nas peças da
##      lista e compartilhando material, e o scatter continua respeitando
##      os pontos de serviço.
##   3. **Manchas medidas** — homogeneidade de espécie de cada passe contra o
##      sorteio livre, e cobertura de tela contra o layout anterior. É a única
##      forma de "ficou agrupado sem esvaziar" que não depende de olhar a tela.

const SETTLE_FRAMES := 5
## Mesma razão do `test_playable`: a troca de bioma é detectada no `_process`
## do `WorldRoot`, então ler no quadro do teleporte leria o bioma anterior.
const PROBE_FRAMES := 3
## Folga de ponto flutuante nas comparações de luz/névoa.
const EPS := 0.0005
## Raio (m) de uma "tela" para a medida de cobertura: metade da largura que a
## câmera de jogo mostra (~24 m em `IsoCamera.base_size` 13,72), arredondada
## para baixo — o miolo do quadro, onde o jogador está olhando.
const VIEW_RADIUS := 8.0
## Telas amostradas por domínio. Semente fixa em `empty_fraction`.
const SCREEN_SAMPLES := 400
## Fração máxima de telas com no máximo UMA peça. Medido em 2026-09-17: 5,3% no
## mar raso e 0% no recife (o layout anterior, por sonda num recorte parecido,
## ~6% e 0%). A folga é pequena de propósito: a primeira versão do agrupamento,
## por posição, deixava ~34% das telas do mar raso assim — e foi a tela, não um
## teste, que a denunciou.
const MAX_EMPTY_SHALLOW := 0.12
const MAX_EMPTY_REEF := 0.03
## Quantas vezes a homogeneidade de espécie (vizinho mais próximo da mesma
## peça) tem de superar a do sorteio livre, `1 / tamanho do pool`. Medido em
## 2026-09-17: 3,7× nos dois passes; o sorteio livre anterior media ~0,9× e
## ~1,2× (por sonda).
const MIN_HOMOGENEITY_FACTOR := 2.5

var _scene: Node
var _player: CharacterBody3D
var _frames := 0
var _phase := 0
var _probe := 0
var _probe_frames := 0
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	_player = _scene.get_node("Player")


func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == 0:
		if _frames < SETTLE_FRAMES:
			return false
		print("== bancada do BiomeAmbience")
		_bench_ambience()
		print("== ambiencia no mundo")
		_check_world_ambience()
		print("== balanco de corrente")
		_check_sway()
		print("== scatter em manchas de especie")
		_check_scatter()
		print("== costa em duas camadas + props")
		_check_coast_layers()
		print("== plato glacial em duas camadas")
		_check_glacial_layers()
		print("== praca da vila")
		_check_village()
		print("== travessia pelos cinco biomas")
		_phase = 1
		return false
	if _phase == 1:
		return _step_biome_probes()
	return true


# ---------------------------------------------------------------------------
# 1. Bancada
# ---------------------------------------------------------------------------

func _bench_ambience() -> void:
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var amb := BiomeAmbience.new()
	amb._env = env
	amb._sun = sun
	# Fora da árvore: o motor não chama `_process` sozinho, então cada passo
	# conta uma vez só.

	for code in BiomeAmbience.PROFILES:
		var unknown: Array = []
		for key in BiomeAmbience.PROFILES[code]:
			if not BiomeAmbience.BASE.has(key):
				unknown.append(key)
		# Chave digitada errado num perfil seria interpolada e nunca escrita
		# em lugar nenhum — o bioma leria igual à base sem erro nenhum.
		_check_true("perfil %s so declara chaves que a base conhece" % code, unknown.is_empty(),
			"desconhecidas: %s" % str(unknown))

	_check_true("bioma sem perfil recebe a base",
		amb._profile("BIO-999") == BiomeAmbience.BASE)
	_check_true("BIO-001 e a base (e o bioma-base do PZ-01)",
		amb._profile("BIO-001") == BiomeAmbience.BASE)

	var deep: Dictionary = amb._profile("BIO-004")
	var glacial: Dictionary = amb._profile("BIO-014")
	var reef: Dictionary = amb._profile("BIO-003")

	amb.set_biome("BIO-004", true)
	_check_near("abertura instantanea ja escreve o perfil (sol)", sun.light_energy, deep["sun_energy"])
	_check_near("abertura instantanea ja escreve o perfil (nevoa)", env.fog_density, deep["fog_density"])

	amb.set_biome("BIO-014")
	_check_near("travessia nao salta no quadro da troca", sun.light_energy, deep["sun_energy"])
	amb._process(BiomeAmbience.TRANSITION_SEC * 0.5)
	var mid_expected := lerpf(deep["sun_energy"], glacial["sun_energy"], 0.5)
	_check_near("meio da travessia e o meio do caminho (smoothstep em 0,5)", sun.light_energy, mid_expected)
	amb._process(BiomeAmbience.TRANSITION_SEC * 0.5)
	_check_near("fim da travessia chega no alvo (sol)", sun.light_energy, glacial["sun_energy"])
	_check_true("fim da travessia chega no alvo (cor da nevoa)",
		env.fog_light_color.is_equal_approx(glacial["fog"]),
		"%s vs %s" % [env.fog_light_color, glacial["fog"]])

	# Interrupção: sai do glacial para o abismo, e no meio muda para o recife.
	amb.set_biome("BIO-004")
	amb._process(BiomeAmbience.TRANSITION_SEC * 0.5)
	var interrupted := sun.light_energy
	amb.set_biome("BIO-003")
	_check_near("interrupcao parte de onde a imagem esta, nao do perfil anterior",
		sun.light_energy, interrupted)
	amb._process(BiomeAmbience.TRANSITION_SEC)
	_check_near("interrupcao ainda chega no alvo novo", sun.light_energy, reef["sun_energy"])

	amb.set_biome("BIO-003")
	_check_true("mesmo bioma de novo nao reabre a interpolacao", amb._t >= 1.0, "t = %.2f" % amb._t)

	var bare := BiomeAmbience.new()
	bare.set_biome("BIO-004")
	bare._process(BiomeAmbience.TRANSITION_SEC)
	_check_true("sem Environment nem sol o no degrada sem erro", true)

	bare.free()
	amb.free()
	sun.free()


# ---------------------------------------------------------------------------
# 2. Mundo
# ---------------------------------------------------------------------------

func _check_world_ambience() -> void:
	var amb := _scene.get_node_or_null("BiomeAmbience") as BiomeAmbience
	_check_true("o MapDressing monta o BiomeAmbience", amb != null)
	_check_true("o WorldRoot guarda a referencia", _scene.get("_ambience") == amb)
	if amb == null:
		return
	var biome := str(_scene.call("current_biome"))
	var env := (_scene.get_node("Ambience") as WorldEnvironment).environment
	var profile: Dictionary = amb._profile(biome)
	_check_true("a abertura nao interpola (%s)" % biome, amb._t >= 1.0, "t = %.2f" % amb._t)
	_check_near("a abertura ja esta no perfil do bioma em que o jogador nasce",
		env.fog_density, profile["fog_density"])


func _check_sway() -> void:
	var props := _props()
	var swaying := 0
	var wrong: Array = []
	var materials := {}
	var names_swaying := {}
	for p in props:
		var name := _prop_name(p)
		var should: bool = MapDressing.SWAY.has(name)
		for mi in _meshes(p):
			for i in mi.mesh.get_surface_count():
				var over := mi.get_surface_override_material(i) as ShaderMaterial
				var has := over != null and over.shader == MapDressing.SWAY_SHADER
				if has != should:
					wrong.append(name)
				if has:
					swaying += 1
					materials[over.get_instance_id()] = true
					names_swaying[name] = true
					if not is_equal_approx(float(over.get_shader_parameter("sway_amount")), MapDressing.SWAY[name]):
						wrong.append("%s (amount)" % name)
					if float(over.get_shader_parameter("sway_top_y")) <= float(over.get_shader_parameter("sway_pivot_y")):
						wrong.append("%s (ponta abaixo do pivo)" % name)
	_check_true("ha pecas balancando no mapa", swaying > 0, "%d superficies" % swaying)
	_check_true("balanca exatamente quem esta em SWAY, e mais ninguem", wrong.is_empty(),
		"divergentes: %s" % str(wrong.slice(0, 6)))
	_check_true("um material por peca, nao por instancia",
		materials.size() == names_swaying.size(),
		"%d materiais para %d pecas" % [materials.size(), names_swaying.size()])

	# Os dois materiais de verdade, não a constante contra ela mesma: o que
	# importa é que a superfície e o leito RECEBERAM a mesma direção.
	var water := _water_material()
	var water_dir: Variant = water.get_shader_parameter("water_flow_dir") if water else null
	var sway_dirs := {}
	for p in props:
		for mi in _meshes(p):
			for i in mi.mesh.get_surface_count():
				var over := mi.get_surface_override_material(i) as ShaderMaterial
				if over and over.shader == MapDressing.SWAY_SHADER:
					sway_dirs[over.get_shader_parameter("sway_dir")] = true
	_check_true("o material da agua recebe a corrente explicita", water_dir is Vector2, str(water_dir))
	_check_true("todo balanco usa a mesma corrente da superficie",
		sway_dirs.size() == 1 and sway_dirs.has(water_dir),
		"agua %s, balanco %s" % [water_dir, sway_dirs.keys()])


func _check_scatter() -> void:
	var terrain := _scene.get("_terrain") as MapTerrain
	var biomes := _scene.get("_map_biomes") as MapBiomes
	var layout := MapDressing.scatter_layout(terrain, biomes)
	var general: Array = layout["general"]
	var reef: Array = layout["reef"]

	# O aglomerado abandona quando só erra; se abandonasse demais, o passe
	# esgotaria as tentativas e a densidade cairia calada — a promessa do
	# `_scatter` é redistribuir, não emagrecer.
	_check_true("o passe geral preenche o orcamento", general.size() == MapDressing.PZ01_SCATTER_COUNT,
		"%d de %d" % [general.size(), MapDressing.PZ01_SCATTER_COUNT])
	_check_true("o passe do recife preenche o orcamento", reef.size() == MapDressing.PZ01_REEF_SCATTER_COUNT,
		"%d de %d" % [reef.size(), MapDressing.PZ01_REEF_SCATTER_COUNT])

	# O que a árvore tem é o que o layout diz — senão as medidas abaixo seriam
	# de um mapa que o jogo não planta. Soma TODOS os passes, para um passe
	# novo não passar despercebido por este teste.
	var props := _props()
	var planted := MapDressing.active_landmarks(biomes).size()
	for pass_name in MapDressing.SCATTER_PASSES:
		planted += (layout[pass_name] as Array).size()
	_check_true("o mundo planta exatamente o layout calculado", props.size() == planted,
		"%d nos, layout %d" % [props.size(), planted])

	var too_close: Array = []
	for p in props:
		for spot in MapDressing._clear_spots():
			var d := Vector2(p.position.x - spot.x, p.position.z - spot.z).length()
			if d < MapDressing.CLEAR_RADIUS:
				too_close.append("%s a %.1f m" % [_prop_name(p), d])
	_check_true("nenhum prop a menos de CLEAR_RADIUS de ponto de servico", too_close.is_empty(),
		str(too_close.slice(0, 4)))

	# O miolo da praça da vila fica sem cenário sorteado (ver
	# `MapDressing.PZ01_PLAZA_KEEPOUT`) — é o chão das pessoas e do spawn.
	var in_plaza: Array = []
	for p in props:
		if MapDressing.plaza_profile(terrain, p.position) > MapDressing.PZ01_PLAZA_KEEPOUT:
			in_plaza.append(_prop_name(p))
	_check_true("nenhum prop sorteado no miolo da praca da vila", in_plaza.is_empty(), str(in_plaza.slice(0, 4)))

	var off_dry := func(p: Vector3) -> bool:
		return not (terrain.on_coast(p) or terrain.on_island(p, 1.5))
	var shallow_domain := domain_cells(func(p: Vector3) -> bool:
		var d := Vector2(p.x, p.z).length()
		return d >= MapDressing.SCATTER_RADIUS_MIN and d <= MapDressing.SCATTER_RADIUS_MAX \
			and off_dry.call(p) and biomes.biome_at(p) == "BIO-001")
	var reef_domain := domain_cells(func(p: Vector3) -> bool:
		return Vector2(p.x, p.z).length() <= MapDressing.SCATTER_RADIUS_MAX \
			and off_dry.call(p) and biomes.biome_at(p) == "BIO-003")

	_check_homogeneous("passe geral", general, MapDressing.PZ01_SCATTER_POOL.size())
	_check_homogeneous("passe do recife", reef, MapDressing.PZ01_REEF_SCATTER_POOL.size())

	# Cobertura mede o que o jogador VÊ: todas as peças do mapa juntas, não um
	# passe isolado — o recife também recebe peças do passe geral.
	var everything: Array = _xz(general) + _xz(reef)
	for l in MapDressing.active_landmarks(biomes):
		everything.append(Vector2(l[1].x, l[1].z))
	var empty_shallow := empty_fraction(everything, shallow_domain)
	var empty_reef := empty_fraction(everything, reef_domain)
	_check_true("mar raso: telas com no maximo uma peca <= %.0f%%" % (MAX_EMPTY_SHALLOW * 100.0),
		empty_shallow <= MAX_EMPTY_SHALLOW, "%.1f%%" % (empty_shallow * 100.0))
	_check_true("recife: telas com no maximo uma peca <= %.0f%%" % (MAX_EMPTY_REEF * 100.0),
		empty_reef <= MAX_EMPTY_REEF, "%.1f%%" % (empty_reef * 100.0))


## Cobra que vizinhos tendem a ser da mesma espécie — a leitura "campo de
## alga" em vez de "salpicado".
func _check_homogeneous(label: String, entries: Array, pool_size: int) -> void:
	var h := homogeneity(entries)
	var free := 1.0 / float(pool_size)
	_check_true("%s agrupa especie (>= %.1fx o sorteio livre)" % [label, MIN_HOMOGENEITY_FACTOR],
		h >= free * MIN_HOMOGENEITY_FACTOR,
		"vizinho da mesma especie em %.0f%% (livre: %.1f%%, %.1fx)" % [h * 100.0, free * 100.0, h / free])


## O mesmo que `_check_coast_layers` mede na costa, no platô GLACIAL: a
## máscara que troca rocha exposta (borda) por neve (miolo).
##
## O platô glacial é o espelho da costa desde 2026-09-18 — mesma forma, lado
## +Z —, então a varredura vem da outra borda do mapa. Ele não tem props nem
## ponto de serviço; o que há para conferir é a máscara.
func _check_glacial_layers() -> void:
	var terrain := _scene.get("_terrain") as MapTerrain
	var half := float(MapTerrain.SIZE) * 0.5
	var x := float(roundi(MapTerrain.GLACIAL_CENTER_X))

	# Vindo da borda +Z para o mar: primeira célula que deixa de ser platô.
	var ramp_top_z := -INF
	for zi in range(int(half), int(-half), -1):
		if terrain._glacial_profile(x, float(zi)) < 1.0:
			ramp_top_z = float(zi)
			break
	_check_true("a linha de centro do glacial chega na rampa", ramp_top_z > -half, "z = %.0f" % ramp_top_z)
	if ramp_top_z == -INF:
		return

	# Um metro rampa abaixo, não na célula exata da borda: as células da grade
	# ficam em meio-metro do mundo (`i - meio-lado`, com meio-lado fracionário),
	# então amostrar no inteiro encontrado arredonda meio metro PARA DENTRO do
	# platô deste lado do mapa — e mede 1 m de distância em vez de 0. Do lado
	# da costa o mesmo arredondamento cai para fora, que é por que a sonda de
	# lá acerta em cheio.
	_check_near("na rampa do glacial a distancia e zero (rocha exposta)",
		terrain.glacial_inland_at(Vector3(x, 0.0, ramp_top_z - 1.0)), 0.0)
	_check_near("no mar aberto a distancia glacial e zero",
		terrain.glacial_inland_at(Vector3(half * 0.2, 0.0, -half * 0.3)), 0.0)

	# Mesma régua da costa, e o mesmo teto pelo mesmo motivo geométrico.
	var flat_half_width := MapTerrain.GLACIAL_RECT_HALF_W - MapTerrain.GLACIAL_RAMP_WIDTH \
		- MapTerrain.COAST_EDGE_NOISE_AMPLITUDE - MapTerrain.COAST_EDGE_NOISE_FINE_AMPLITUDE
	var k_max := mini(20, maxi(1, int(flat_half_width)))
	var wrong: Array = []
	var previous := -1.0
	for k in range(1, k_max + 1):
		var d := terrain.glacial_inland_at(Vector3(x, 0.0, ramp_top_z + float(k)))
		if d > float(k) * 1.1 + 0.5 or d < float(k) * 0.6 - 0.5 or d < previous - 0.01:
			wrong.append("%d m -> %.1f" % [k, d])
		previous = d
	_check_true("plato glacial adentro a distancia cresce com os metros", wrong.is_empty(),
		str(wrong.slice(0, 5)))

	var at_edge := terrain.glacial_inland_at(Vector3(x, 0.0, half - 1.0))
	_check_true("a borda do mapa nao conta como beira do glacial",
		at_edge > MapTerrain.GLACIAL_RAMP_WIDTH * 2.0, "%.1f m" % at_edge)


## A máscara "distância para dentro da costa" que o shader usa para trocar lama
## úmida por terra seca. Anda pela linha de centro do lobo, da borda do mapa
## para o mar, e confere a medida contra a distância real até a borda da rampa.
func _check_coast_layers() -> void:
	var terrain := _scene.get("_terrain") as MapTerrain
	var half := float(MapTerrain.SIZE) * 0.5
	var x := float(roundi(MapTerrain.COAST_CENTER_X))

	# Borda de cima da rampa na linha de centro: primeira célula, vinda da
	# borda do mapa, em que a forma da costa deixa de ser platô cheio.
	var ramp_top_z := INF
	for zi in range(int(-half), int(half)):
		if terrain._coast_profile(x, float(zi)) < 1.0:
			ramp_top_z = float(zi)
			break
	_check_true("a linha de centro da costa chega na rampa", ramp_top_z < half, "z = %.0f" % ramp_top_z)
	if ramp_top_z == INF:
		return

	_check_near("na rampa a distancia e zero (lama umida)",
		terrain.coast_inland_at(Vector3(x, 0.0, ramp_top_z)), 0.0)
	_check_near("no mar aberto a distancia e zero",
		terrain.coast_inland_at(Vector3(half * 0.2, 0.0, -half * 0.3)), 0.0)

	# Para dentro: nunca mais que a distância em linha reta até a rampa (a
	# borda mais próxima pode estar de lado, com o warp) e nunca muito menos.
	# O chamfer superestima até ~8%.
	#
	# O teto da varredura é a própria largura livre de lateral do platô
	# (`COAST_RECT_HALF_W - COAST_RAMP_WIDTH`), não um número fixo: passado
	# esse ponto a célula mais próxima fora do platô deixa de ser a rampa
	# (na linha de centro) e passa a ser a BORDA LATERAL, que é mais perto —
	# a distância para de crescer com `k` por geometria, não por bug. Corte de
	# 90% do BIO-002 (2026-09-17) encolheu essa largura livre de ~66 m para
	# ~16 m; testar até 20 m fixo (válido enquanto a costa era larga) passou a
	# cair nessa zona e falhar por design, não por regressão. A margem descontada
	# é a amplitude COMBINADA do warp da costa (`COAST_EDGE_NOISE_AMPLITUDE` +
	# `COAST_EDGE_NOISE_FINE_AMPLITUDE`, não `EDGE_NOISE_AMPLITUDE` — esse é o
	# padrão da ILHA, bem menor; a costa ganhou irregularidade própria e maior
	# em 2026-09-18) porque o warp pode empurrar a lateral alguns metros pra
	# dentro em qualquer amostra.
	var flat_half_width := MapTerrain.COAST_RECT_HALF_W - MapTerrain.COAST_RAMP_WIDTH \
		- MapTerrain.COAST_EDGE_NOISE_AMPLITUDE - MapTerrain.COAST_EDGE_NOISE_FINE_AMPLITUDE
	var k_max := mini(20, maxi(1, int(flat_half_width)))
	var wrong: Array = []
	var previous := -1.0
	for k in range(1, k_max + 1):
		var d := terrain.coast_inland_at(Vector3(x, 0.0, ramp_top_z - float(k)))
		if d > float(k) * 1.1 + 0.5 or d < float(k) * 0.6 - 0.5 or d < previous - 0.01:
			wrong.append("%d m -> %.1f" % [k, d])
		previous = d
	_check_true("platô adentro a distancia cresce com os metros ate a rampa", wrong.is_empty(),
		str(wrong.slice(0, 5)))

	# A borda do MAPA atrás da vila não é beira d'água: sem isso a lama úmida
	# faria uma segunda faixa colada no paredão.
	var at_edge := terrain.coast_inland_at(Vector3(x, 0.0, -half + 1.0))
	_check_true("a borda do mapa nao conta como beira d'agua", at_edge > MapTerrain.COAST_RAMP_WIDTH * 2.0,
		"%.1f m" % at_edge)

	var material := (terrain.get_node("Mesh") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	var missing: Array = []
	for p in ["mud_tex", "mud_height_tex", "mud_dry_tex", "mud_dry_height_tex", "coast_inland_tex",
			"snow_tex", "snow_height_tex", "snow_rock_tex", "snow_rock_height_tex", "glacial_inland_tex",
			"paved_tex", "paved_height_tex", "village_mask_tex"]:
		if material.get_shader_parameter(p) == null:
			missing.append(p)
	_check_true("o material do chao recebe as camadas e as mascaras", missing.is_empty(), str(missing))
	_check_near("o shader recebe a escala das lajes do MapDressing",
		float(material.get_shader_parameter("paved_tex_scale")), MapDressing.PZ01_PAVED_TEX_SCALE)
	var tint: Variant = material.get_shader_parameter("paved_tint")
	_check_true("o shader recebe o tom das lajes do MapDressing",
		tint is Color and (tint as Color).is_equal_approx(MapDressing.PZ01_PAVED_TINT), str(tint))

	# A cor e as pedras têm de concordar sobre onde fica a linha da água: uma
	# faixa pintada num lugar e o matacão plantado noutro é o mesmo tipo de
	# descompasso que o `glacial_mask_tex` existiu para desfazer.
	_check_near("o shader recebe a largura da faixa umida do MapDressing",
		float(material.get_shader_parameter("coast_wet_width")), MapDressing.PZ01_COAST_WET_WIDTH)
	_check_true("a faixa de matacao cruza a linha da agua",
		MapDressing.PZ01_COAST_ROCK_BAND.x < MapDressing.PZ01_COAST_WET_WIDTH
		and MapDressing.PZ01_COAST_ROCK_BAND.y > MapDressing.PZ01_COAST_WET_WIDTH,
		"faixa %s, linha %.1f" % [MapDressing.PZ01_COAST_ROCK_BAND, MapDressing.PZ01_COAST_WET_WIDTH])

	var layout := MapDressing.scatter_layout(terrain, _scene.get("_map_biomes") as MapBiomes)
	var rocks: Array = layout["coast_rock"]
	var pebbles: Array = layout["coast_pebble"]
	_check_true("os matacoes preenchem o orcamento", rocks.size() == MapDressing.PZ01_COAST_ROCK_COUNT,
		"%d de %d" % [rocks.size(), MapDressing.PZ01_COAST_ROCK_COUNT])
	_check_true("os seixos preenchem o orcamento", pebbles.size() == MapDressing.PZ01_COAST_PEBBLE_COUNT,
		"%d de %d" % [pebbles.size(), MapDressing.PZ01_COAST_PEBBLE_COUNT])

	var off_band: Array = []
	for e in rocks:
		var inland: float = terrain.coast_inland_at(e[1])
		if inland < MapDressing.PZ01_COAST_ROCK_BAND.x or inland > MapDressing.PZ01_COAST_ROCK_BAND.y:
			off_band.append("%.1f m" % inland)
	_check_true("todo matacao nasce na faixa da linha da agua", off_band.is_empty(),
		str(off_band.slice(0, 5)))

	var wet_pebbles: Array = []
	for e in pebbles:
		if terrain.coast_inland_at(e[1]) < MapDressing.PZ01_COAST_PEBBLE_MIN_INLAND:
			wet_pebbles.append("%.1f m" % terrain.coast_inland_at(e[1]))
	_check_true("nenhum seixo na rampa molhada", wet_pebbles.is_empty(), str(wet_pebbles.slice(0, 5)))

	# Agrupamento: aqui ele É o objetivo (afloramento, não pedra solta), então
	# a régua é direta — a maioria dos matacões tem companhia ao alcance de um
	# aglomerado.
	var with_company := 0
	var reach: float = MapDressing.PZ01_COAST_ROCK_CLUSTER.y + MapDressing.PZ01_COAST_ROCK_MIN_SEP
	for i in rocks.size():
		for j in rocks.size():
			if i != j and (rocks[i][1] as Vector3).distance_to(rocks[j][1]) <= reach:
				with_company += 1
				break
	_check_true("a maioria dos matacoes esta em aglomerado",
		float(with_company) / float(maxi(rocks.size(), 1)) >= 0.6,
		"%d de %d com vizinho a %.1f m" % [with_company, rocks.size(), reach])


## A praça da vila (2026-09-20): a máscara cobre os serviços e o spawn, as
## lajes soltas ficam na orla dela, em chão plano, longe do spawn e das
## pessoas, e a árvore planta exatamente o layout calculado.
func _check_village() -> void:
	var terrain := _scene.get("_terrain") as MapTerrain
	var half := float(MapTerrain.SIZE) * 0.5
	var uncovered: Array = []
	for spot in [WorldPopulator.MERCHANT_SPOT, WorldPopulator.RELIC_STATION_SPOT,
			WorldPopulator.CRAFTING_BENCH_SPOT, WorldPopulator.PLAYER_START_SPOT]:
		var v := MapDressing.plaza_profile(terrain, spot)
		if v < 0.9:
			uncovered.append("%s -> %.2f" % [spot, v])
	_check_true("a praca cobre os tres servicos e o spawn", uncovered.is_empty(), str(uncovered))
	_check_near("a praca nao existe em mar aberto",
		MapDressing.plaza_profile(terrain, Vector3(half * 0.2, 0.0, -half * 0.3)), 0.0)

	var layout := MapDressing.village_layout()
	var village := _scene.get_node_or_null("Dressing/Village")
	_check_true("o mundo planta exatamente o layout da vila",
		village != null and village.get_child_count() == layout.size(),
		"%d nos, layout %d" % [village.get_child_count() if village else -1, layout.size()])

	var npcs: Array = []
	for child in _scene.get_children():
		var npc := child.get_node_or_null("Npc") if child is InteractableActor else null
		if npc:
			npcs.append((npc as Node3D).global_position)
	_check_true("as tres pessoas da vila existem", npcs.size() == 3, "%d" % npcs.size())

	var problems: Array = []
	var on_fringe := 0
	for e in layout:
		var pos: Vector3 = e["pos"]
		var name: String = String(e["file"]).get_file().get_basename()
		if absf(terrain.height_at(pos) - MapTerrain.LAND_HEIGHT) > 0.01:
			problems.append("%s fora do plano (h=%.2f)" % [name, terrain.height_at(pos)])
		var d_spawn := Vector2(pos.x - WorldPopulator.PLAYER_START_SPOT.x, pos.z - WorldPopulator.PLAYER_START_SPOT.z).length()
		if d_spawn < MapDressing.CLEAR_RADIUS:
			problems.append("%s a %.1f m do spawn" % [name, d_spawn])
		for n in npcs:
			var d_npc := Vector2(pos.x - n.x, pos.z - n.z).length()
			if d_npc < 1.0:
				problems.append("%s a %.1f m de uma pessoa" % [name, d_npc])
		var v := MapDressing.plaza_profile(terrain, pos)
		if v > 0.1 and v < 0.9:
			on_fringe += 1
	_check_true("toda peca da vila em chao plano, longe do spawn e das pessoas", problems.is_empty(),
		str(problems.slice(0, 5)))
	_check_true("a maioria das lajes cruza a orla da praca",
		layout.is_empty() or float(on_fringe) / float(layout.size()) >= 0.6,
		"%d de %d" % [on_fringe, layout.size()])


func _step_biome_probes() -> bool:
	var amb := _scene.get_node_or_null("BiomeAmbience") as BiomeAmbience
	var probes: Array = load("res://scripts/dev/test_playable.gd").biome_probes()
	var probe: Array = probes[_probe]
	if _probe_frames == 0:
		_player.global_position = probe[0]
		_player.velocity = Vector3.ZERO
	_probe_frames += 1
	if _probe_frames <= PROBE_FRAMES:
		return false

	var expected := str(probe[1])
	if amb:
		_check_true("em %s a ambiencia foi avisada de %s" % [probe[2], expected],
			amb._biome_code == expected, "tem %s" % amb._biome_code)
		_check_true("em %s o alvo e o perfil de %s" % [probe[2], expected],
			amb._to == amb._profile(expected))

	_probe += 1
	_probe_frames = 0
	if _probe >= probes.size():
		_summary()
		return true
	return false


# ---------------------------------------------------------------------------
# Medição
# ---------------------------------------------------------------------------

## Células de 1 m² do mapa que passam em `filter` — o domínio de um passe, com
## os mesmos filtros que o `scatter_layout` aplica. A contagem É a área.
static func domain_cells(filter: Callable) -> Array:
	var half := int(MapTerrain.SIZE / 2)
	var out: Array = []
	for x in range(-half, half + 1):
		for z in range(-half, half + 1):
			if filter.call(Vector3(x, 0.0, z)):
				out.append(Vector2(x, z))
	return out


## Fração das peças cujo vizinho mais próximo, no mesmo passe, é da mesma
## espécie. Entradas no formato de `MapDressing.scatter_layout`.
static func homogeneity(entries: Array) -> float:
	if entries.size() < 2:
		return 0.0
	var same := 0
	for i in entries.size():
		var best := INF
		var nearest := -1
		for j in entries.size():
			if i == j:
				continue
			var d: float = (entries[i][1] as Vector3).distance_squared_to(entries[j][1])
			if d < best:
				best = d
				nearest = j
		if entries[nearest][0][0] == entries[i][0][0]:
			same += 1
	return float(same) / entries.size()


## Fração de "telas" (círculo de `VIEW_RADIUS` centrado numa célula sorteada do
## domínio) com no máximo uma peça.
static func empty_fraction(points: Array, cells: Array) -> float:
	if cells.is_empty():
		return 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260917
	var empty := 0
	for i in SCREEN_SAMPLES:
		var center: Vector2 = cells[rng.randi() % cells.size()]
		var n := 0
		for p in points:
			if (p as Vector2).distance_to(center) < VIEW_RADIUS:
				n += 1
				if n > 1:
					break
		if n <= 1:
			empty += 1
	return float(empty) / SCREEN_SAMPLES


static func _xz(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append(Vector2(e[1].x, e[1].z))
	return out


func _props() -> Array:
	var holder := _scene.get_node_or_null("Dressing")
	var out: Array = []
	if holder == null:
		return out
	for c in holder.get_children():
		if c is Node3D and (c as Node3D).scene_file_path != "":
			out.append(c)
	return out


func _water_material() -> ShaderMaterial:
	var terrain := _scene.get("_terrain") as MapTerrain
	if terrain == null:
		return null
	var water := terrain.get_node_or_null("Water") as MeshInstance3D
	if water == null or water.mesh == null:
		return null
	return water.mesh.material as ShaderMaterial


static func _prop_name(node: Node) -> String:
	return node.scene_file_path.get_file().get_basename()


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out


# ---------------------------------------------------------------------------

func _check_near(label: String, got: float, expected: float) -> void:
	_check_true(label, absf(got - expected) <= EPS, "%.4f vs %.4f" % [got, expected])


func _check_true(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s%s" % [label, (" — " + detail) if detail != "" else ""])
	else:
		_failures += 1
		printerr("  FAIL %s%s" % [label, (" — " + detail) if detail != "" else ""])


func _summary() -> void:
	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)
