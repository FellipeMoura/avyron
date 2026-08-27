class_name MapTerrain
extends StaticBody3D

## O chão do mapa com relevo: malha, colisão e a consulta de altura que os
## sistemas de chão plano usam para continuar corretos.
##
## O desenho do relevo é deliberado: a PLANÍCIE CENTRAL é plana (altura 0) até
## `FLAT_RADIUS`, e é lá que vive todo o gameplay que assume plano — pontos do
## `WorldPopulator`, encenação de duelo. As colinas só crescem dali para fora,
## e a borda sobe num rim de contenção que fecha a leitura do mapa na câmera
## ortográfica. Relevo é apresentação com colisão, não labirinto: nada aqui
## deve criar rota bloqueada.
##
## Duas exceções ao plano, as duas de propósito e as duas com rampa andável: a
## COSTA na borda -Z e a ILHA no miolo, que carrega a arena. Quem assume chão
## plano perto da origem (spawn, encenação) tem de perguntar a altura, não
## presumir zero — a origem do mapa hoje é o topo da ilha, a 2,6 m.
##
## Corpos com física (jogador, criaturas selvagens — `CharacterBody3D` com
## gravidade) seguem o relevo pela colisão, sem consulta. Quem NÃO tem física
## (companheira, props do `MapDressing`, spawner sorteando posição) pergunta a
## altura via `height_at` — a resposta é interpolada da MESMA grade que gera
## malha e colisão, então visual, física e consulta nunca discordam.
##
## Substitui o `Ground` chapado de `main.tscn` em runtime (`WorldRoot`), com o
## mesmo nome de nó — `test_world` confere a existência de "Ground" e o clique
## de mundo continua batendo num StaticBody.

## Lado do mapa em metros (grade de 1 m — célula igual à do HeightMapShape3D,
## que fixa o espaçamento em 1 unidade).
const SIZE := 60
## Raio (em métrica de quadrado, max(|x|,|z|)) da zona plana central.
const FLAT_RADIUS := 16.0
## Altura máxima das colinas na zona externa.
const HILL_HEIGHT := 2.5
## Altura extra do rim de borda, somada por cima das colinas.
const RIM_HEIGHT := 3.5
## Semente do relevo — fixa pelo mesmo motivo do `spawn_seed` do spawner.
const TERRAIN_SEED := 20260824

## A costa: um platô raso ao longo da borda -Z — solo firme para NPCs e
## portais, sem bioma natural e sem spawn de criatura (spawner e MapDressing
## consultam `on_coast`). O leito sobe em rampa entre COAST_RAMP_START e
## COAST_TOP e assenta plano em COAST_HEIGHT; as colinas são suprimidas na
## faixa (o platô é limpo de propósito) e o rim de borda continua subindo
## atrás dela, como paredão de fundo.
const COAST_RAMP_START := -16.0
const COAST_TOP := -21.0
const COAST_HEIGHT := 1.6

## A ilha: o único chão seco fora da costa — um platô pequeno no MEIO do mapa,
## que emerge da planície central e carrega a arena (`WorldPopulator`). É
## também onde o domador abre o jogo, de pé, antes de descer para o mar.
##
## O topo é plano até `ISLAND_TOP_RADIUS` e desce em rampa até morrer em
## `ISLAND_BASE_RADIUS`. A largura dessa rampa não é estética: a inclinação
## máxima de um `smoothstep` é `1,5 · altura / vão`, e com 2,6 m em 5 m de vão
## dá 38°, abaixo dos 45° que o `CharacterBody3D` do Godot aceita como piso.
## Encurtar o vão (ou levantar a ilha) sem refazer essa conta transforma a
## ilha em parede — e uma parede aqui tranca a arena, que é justamente o que
## o cabeçalho proíbe.
##
## `ISLAND_CENTER` é (x, z) no plano — o `y` do Vector2 é o Z do mundo.
const ISLAND_CENTER := Vector2(0.0, 0.0)
const ISLAND_TOP_RADIUS := 4.0
const ISLAND_BASE_RADIUS := 9.0
const ISLAND_HEIGHT := 2.6

## Margem entre a borda do terreno e o limite em que um corpo ainda pode ser
## posto. Além dos ±30 m da malha não há chão nenhum — nem visual, nem colisão,
## nem resposta de `height_at` que signifique alguma coisa —, e um corpo posto
## lá simplesmente cai. Dois metros cobrem o maior raio de cápsula do elenco
## (1,2 m) com folga.
const BOUNDS_MARGIN := 2.0

## Cota da superfície da água, injetada por quem veste o mapa
## (`MapDressing.water_line`). `-INF` = mapa seco, e aí nada está submerso —
## o padrão das bancadas de teste, que montam terreno sem bioma.
var water_line := -INF

var _heights: PackedFloat32Array
var _dim: int


static func create(palette: Dictionary) -> MapTerrain:
	var t := MapTerrain.new()
	t._build(palette)
	return t


## Altura do terreno no ponto (bilinear sobre a grade). Fora do mapa devolve a
## altura da borda mais próxima — quem perguntar de fora não cai no vazio.
func height_at(world_pos: Vector3) -> float:
	var half := float(SIZE) * 0.5
	var gx := clampf(world_pos.x + half, 0.0, float(SIZE) - 0.001)
	var gz := clampf(world_pos.z + half, 0.0, float(SIZE) - 0.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - float(x0)
	var fz := gz - float(z0)
	var h00 := _heights[z0 * _dim + x0]
	var h10 := _heights[z0 * _dim + x0 + 1]
	var h01 := _heights[(z0 + 1) * _dim + x0]
	var h11 := _heights[(z0 + 1) * _dim + x0 + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func _build(palette: Dictionary) -> void:
	_dim = SIZE + 1
	_heights = PackedFloat32Array()
	_heights.resize(_dim * _dim)

	var noise := FastNoiseLite.new()
	noise.seed = TERRAIN_SEED
	noise.frequency = 0.055

	var half := float(SIZE) * 0.5
	for z in _dim:
		for x in _dim:
			var wx := float(x) - half
			var wz := float(z) - half
			_heights[z * _dim + x] = _height_formula(wx, wz, noise)

	_add_mesh(palette)
	_add_collision()


## A fórmula do relevo. `r` em métrica de quadrado porque o mapa é quadrado:
## a distância ao centro tem de crescer igual em direção a lado e a canto,
## senão o rim afunda nos cantos.
func _height_formula(x: float, z: float, noise: FastNoiseLite) -> float:
	var r := maxf(absf(x), absf(z))
	var coast := smoothstep(-COAST_RAMP_START, -COAST_TOP, -z)
	var amp := smoothstep(FLAT_RADIUS, float(SIZE) * 0.5 - 2.0, r)
	var hills := (noise.get_noise_2d(x, z) * 0.5 + 0.5) * HILL_HEIGHT * amp
	var h := hills * (1.0 - coast) + COAST_HEIGHT * coast
	h += smoothstep(float(SIZE) * 0.5 - 5.0, float(SIZE) * 0.5, r) * RIM_HEIGHT
	# A ilha soma em vez de misturar porque nasce dentro da planície (h = 0
	# ali) e não alcança nem a costa nem o rim — não há segundo relevo para
	# negociar no caminho.
	h += _island_profile(x, z) * ISLAND_HEIGHT
	return h


## Quanto da ilha existe neste ponto: 1 no topo plano, 0 fora da base.
func _island_profile(x: float, z: float) -> float:
	var d := Vector2(x - ISLAND_CENTER.x, z - ISLAND_CENTER.y).length()
	return 1.0 - smoothstep(ISLAND_TOP_RADIUS, ISLAND_BASE_RADIUS, d)


## A faixa da costa, rampa incluída. `margin` estende a checagem mar adentro —
## o spawner usa para o keep-out cobrir também a deriva de patrulha.
func on_coast(world_pos: Vector3, margin: float = 0.0) -> bool:
	return world_pos.z <= COAST_RAMP_START + margin


## A ilha, saia submersa incluída — o par de `on_coast`, e usado pelos mesmos
## sistemas: o spawner mantém criatura fora dela, o `MapDressing` não espalha
## coral em terra seca, e `submerged` a deixa negociar com a cota.
##
## O raio é o da BASE, não o da linha d'água: o trecho entre a base e a praia
## está debaixo d'água e continua respondendo pela altura, exatamente como o
## pé da rampa da costa. `margin` estende o keep-out mar adentro.
func on_island(world_pos: Vector3, margin: float = 0.0) -> bool:
	var d := Vector2(world_pos.x - ISLAND_CENTER.x, world_pos.z - ISLAND_CENTER.y).length()
	return d <= ISLAND_BASE_RADIUS + margin


## Este ponto está debaixo d'água?
##
## **Fora da costa e da ilha a resposta é sempre sim**, independentemente da
## altura: o PZ-01 é o leito de um mar, e um recife que sobe 2,5 m continua
## sendo recife, não ilhota. Só esses dois lugares negociam com a cota — são
## os dois em que a rampa atravessa a superfície no meio da subida,
## exatamente como a névoa já conta.
##
## Testar só a altura seria a outra leitura possível, e foi descartada: 315 das
## células do anel externo passam da cota por causa das colinas, e o jogador
## emergiria de pé no meio do recife em cada uma delas. Ilhota de verdade é
## geografia declarada (`on_island`), não altura que calhou de passar da cota —
## foi essa distinção que fez a ilha precisar de um predicado próprio em vez
## de afrouxar a regra para todo mundo.
func submerged(world_pos: Vector3) -> bool:
	if is_inf(water_line):
		return false
	if not on_coast(world_pos) and not on_island(world_pos):
		return true
	return world_pos.y < water_line



## Traz um ponto para dentro do terreno, no plano. Quem move corpo por conta
## própria — hoje só a `BattleStaging`, que empurra os três combatentes com a
## física pausada — passa por aqui antes de escrever a posição.
##
## Existe porque o posto do domador é derivado para FORA do par (atrás da
## própria criatura, no sentido oposto ao adversário): um duelo engatado perto
## da borda de spawn projetava esse posto além da malha, e o jogador ia junto.
## O Y passa intocado — quem chama decide a altura, e a regra de apoio é de
## cada corpo.
func clamp_to_bounds(world_pos: Vector3) -> Vector3:
	var limit := float(SIZE) * 0.5 - BOUNDS_MARGIN
	return Vector3(
		clampf(world_pos.x, -limit, limit),
		world_pos.y,
		clampf(world_pos.z, -limit, limit),
	)


func _add_mesh(palette: Dictionary) -> void:
	var half := float(SIZE) * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(_dim * _dim)
	normals.resize(_dim * _dim)

	for z in _dim:
		for x in _dim:
			var i := z * _dim + x
			vertices[i] = Vector3(float(x) - half, _heights[i], float(z) - half)
			# Normal por diferenças centrais na própria grade — suave e
			# consistente com a colisão, sem depender de generate_normals
			# (que em malha não indexada sairia facetado).
			var hl := _grid_height(x - 1, z)
			var hr := _grid_height(x + 1, z)
			var hd := _grid_height(x, z - 1)
			var hu := _grid_height(x, z + 1)
			normals[i] = Vector3(hl - hr, 2.0, hd - hu).normalized()

	for z in SIZE:
		for x in SIZE:
			var i := z * _dim + x
			# Ordem HORÁRIA vista de cima: é a frente no Godot (ao contrário
			# do padrão OpenGL). Na ordem inversa o chão inteiro é culled e o
			# mapa aparece flutuando sobre o fundo.
			indices.append_array([i, i + 1, i + _dim, i + 1, i + _dim + 1, i + _dim])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = FastNoiseLite.new()
	noise_tex.seamless = true
	noise_tex.width = 256
	noise_tex.height = 256

	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain_ground.gdshader")
	material.set_shader_parameter("noise_tex", noise_tex)
	# A geografia da ilha vai para o shader daqui, e não como default do
	# `.gdshader`, porque ela é do terreno: a faixa seca pintada tem de ser a
	# MESMA que a malha levantou. (As bandas da costa ainda vivem como default
	# lá — quando alguém mexer nelas, o lugar certo é este.)
	material.set_shader_parameter("island_center", ISLAND_CENTER)
	material.set_shader_parameter("island_top_radius", ISLAND_TOP_RADIUS)
	material.set_shader_parameter("island_base_radius", ISLAND_BASE_RADIUS)
	for key in palette:
		material.set_shader_parameter(key, palette[key])
	mesh.surface_set_material(0, material)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	add_child(mi)


func _grid_height(x: int, z: int) -> float:
	return _heights[clampi(z, 0, _dim - 1) * _dim + clampi(x, 0, _dim - 1)]


func _add_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = _dim
	shape.map_depth = _dim
	shape.map_data = _heights
	var col := CollisionShape3D.new()
	col.name = "Collision"
	col.shape = shape
	add_child(col)
