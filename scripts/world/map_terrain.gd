class_name MapTerrain
extends StaticBody3D

## O chão do mapa com relevo: malha, colisão e a consulta de altura que os
## sistemas de chão plano usam para continuar corretos.
##
## O desenho do relevo é deliberado: o CENTRO É PLANO (altura 0) até
## `FLAT_RADIUS`, e é lá que vive todo o gameplay que assume plano — pontos do
## `WorldPopulator`, origem do jogador, encenação de duelo. As colinas só
## crescem dali para fora, e a borda sobe num rim de contenção que fecha a
## leitura do mapa na câmera ortográfica. Relevo é apresentação com colisão,
## não labirinto: nada aqui deve criar rota bloqueada.
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
	return h


## A faixa da costa, rampa incluída. `margin` estende a checagem mar adentro —
## o spawner usa para o keep-out cobrir também a deriva de patrulha.
func on_coast(world_pos: Vector3, margin: float = 0.0) -> bool:
	return world_pos.z <= COAST_RAMP_START + margin


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
