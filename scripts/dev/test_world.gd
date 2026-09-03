extends SceneTree

## Validação headless do input map, da matemática da câmera e da cena principal.
##
##     godot --headless --script res://scripts/dev/test_world.gd
##
## O teste que mais importa aqui é o de direção: com câmera isométrica, errar
## a rotação de 45° faz o W andar na diagonal — bug clássico, sutil de notar
## no olho e trivial de provar com aritmética.

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_input_map()
	_test_direction_math()
	_test_scroll_zoom()
	_test_water_line()
	_test_main_scene()


	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	_checks += 1
	if actual == expected:
		print("  ok   %s = %s" % [label, str(actual)])
	else:
		_failures += 1
		printerr("  FAIL %s = %s (esperado %s)" % [label, str(actual), str(expected)])


func _check_true(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s%s" % [label, (" — " + detail) if detail != "" else ""])
	else:
		_failures += 1
		printerr("  FAIL %s%s" % [label, (" — " + detail) if detail != "" else ""])


# ---------------------------------------------------------------------------

func _test_input_map() -> void:
	print("input map:")
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		_check_true("acao '%s' existe" % action, InputMap.has_action(action))

	# O ponto crítico: uma tecla sintética precisa casar com a ação. Se o
	# `device` gravado no project.godot não bater, isto falha aqui em vez de
	# falhar como "o personagem não anda" depois.
	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	w.pressed = true
	_check_true("W dispara move_up", InputMap.event_is_action(w, "move_up"))

	var d := InputEventKey.new()
	d.physical_keycode = KEY_D
	d.pressed = true
	_check_true("D dispara move_right", InputMap.event_is_action(d, "move_right"))

	# Gamepad: eixo esquerdo horizontal.
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	_check_true("stick direita dispara move_right", InputMap.event_is_action(stick, "move_right"))


func _test_direction_math() -> void:
	print("direcao (rotacao de 45 graus):")

	# Direção que a câmera olha, projetada no chão. É para onde "cima da tela"
	# aponta no mundo.
	var cam_basis := Basis.from_euler(Vector3(
		deg_to_rad(IsoCamera.PITCH_DEGREES),
		deg_to_rad(IsoCamera.YAW_DEGREES),
		0.0
	))
	var cam_forward := cam_basis * Vector3(0, 0, -1)
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()

	# W = move_up, que Input.get_vector devolve como y negativo.
	var w_dir := IsoCamera.screen_to_world_direction(Vector2(0, -1))
	_check_true("W anda para onde a camera olha",
		w_dir.distance_to(cam_forward) < 0.001,
		"W=%s camera=%s" % [str(w_dir.snappedf(0.001)), str(cam_forward.snappedf(0.001))])

	# D deve ser perpendicular a W, para a direita da tela.
	var d_dir := IsoCamera.screen_to_world_direction(Vector2(1, 0))
	_check_true("D e perpendicular a W", absf(d_dir.dot(w_dir)) < 0.001,
		"dot = %.4f" % d_dir.dot(w_dir))

	var right_of_screen := cam_forward.rotated(Vector3.UP, -PI / 2.0)
	_check_true("D vai para a direita da tela",
		d_dir.distance_to(right_of_screen) < 0.001,
		"D=%s" % str(d_dir.snappedf(0.001)))

	# W e S se cancelam; diagonais são normalizadas.
	var s_dir := IsoCamera.screen_to_world_direction(Vector2(0, 1))
	_check_true("S e o oposto de W", s_dir.distance_to(-w_dir) < 0.001)

	var diag := IsoCamera.screen_to_world_direction(Vector2(1, -1))
	_check_true("diagonal e normalizada", absf(diag.length() - 1.0) < 0.001,
		"len = %.4f" % diag.length())

	_check("input zerado nao move", IsoCamera.screen_to_world_direction(Vector2.ZERO), Vector3.ZERO)

	# O movimento nunca sai do plano do chão.
	_check_true("direcao fica no plano do chao", absf(w_dir.y) < 0.0001)


func _test_scroll_zoom() -> void:
	print("zoom por scroll:")
	var cam := IsoCamera.new()
	root.add_child(cam)
	# `_init()` roda antes da árvore estar viva (mesma pegadinha do
	# `_initialize()` documentada no CLAUDE.md) — `add_child` aqui não
	# dispara `_ready()` a tempo, então chama à mão.
	cam._ready()

	_check_true("comeca no base_size", absf(cam.size - cam.base_size) < 0.001,
		"%.3f" % cam.size)

	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	cam._unhandled_input(wheel_up)
	_check_true("roda pra cima aproxima (size menor)", cam.size < cam.base_size,
		"%.3f" % cam.size)

	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	for _i in 30:
		cam._unhandled_input(wheel_down)
	_check_true("roda pra baixo trava no teto do multiplicador",
		absf(cam._zoom_mult - IsoCamera.ZOOM_MULT_MAX) < 0.001, "%.3f" % cam._zoom_mult)
	_check_true("size acompanha o teto", absf(cam.size - cam._zoomed_base_size()) < 0.001)

	for _i in 30:
		cam._unhandled_input(wheel_up)
	_check_true("roda pra cima trava no piso do multiplicador",
		absf(cam._zoom_mult - IsoCamera.ZOOM_MULT_MIN) < 0.001, "%.3f" % cam._zoom_mult)

	# Composição com a batalha: o zoom escolhido pelo jogador sobrevive à
	# transição, e o scroll fica travado enquanto ela dura.
	cam._zoom_mult = 0.8
	cam.size = cam._zoomed_base_size()
	cam.enter_battle()
	_check_true("entrar em batalha trava o scroll", cam._in_battle)
	cam._unhandled_input(wheel_down)
	_check_true("scroll ignorado durante a batalha",
		absf(cam._zoom_mult - 0.8) < 0.001, "%.3f" % cam._zoom_mult)

	cam.exit_battle()
	_check_true("sair da batalha destrava o scroll", not cam._in_battle)
	cam._unhandled_input(wheel_down)
	_check_true("scroll funciona de novo depois",
		cam._zoom_mult > 0.8, "%.3f" % cam._zoom_mult)

	cam.free()


## Onde o domador nada, e onde ele anda.
##
## Desde 2026-09-01 o relevo é só dois níveis fixos
## (`MapTerrain.SEA_HEIGHT`/`LAND_HEIGHT`) — decisão do usuário, trocar
## leitura de profundidade contínua por gráfico controlado. Fora da terra
## firme declarada (`on_coast`/`on_island`/`on_glacial`) é SEMPRE
## `SEA_HEIGHT`, sem exceção de colina ou recife — não sobrou relevo contínuo
## pra ter exceção. Dentro dela é SEMPRE `LAND_HEIGHT`, plano, exceto nos
## `ACCESS_RAMPS` — os únicos lugares onde a transição vira rampa de verdade
## em vez de parede.
##
## A cota é a MESMA que fragmenta a névoa (`MapDressing.PZ01_WATER_LINE`), e
## essa igualdade é o contrato: nadar numa cota e trocar a murk noutra faria a
## imagem contradizer o corpo. Se um dia as duas se separarem, é aqui que dói.
func _test_water_line() -> void:
	print("linha d'agua:")
	var terrain := MapTerrain.create({})
	terrain.water_line = MapDressing.water_line("PZ-01")
	_check("a cota vem do bioma, e é a mesma da névoa",
		terrain.water_line, MapDressing.PZ01_WATER_LINE)

	# Mar aberto: sempre SEA_HEIGHT, sem exceção — não existe mais colina nem
	# recife pra furar a regra. Longe de qualquer ponto de acesso.
	var half := float(MapTerrain.SIZE) * 0.5
	for spot in [
		Vector3(half * 0.4, 0, 0),
		Vector3(half * 0.7, 0, half * 0.7),
		Vector3(half * 0.85, 0, half * 0.85),
	]:
		var at := Vector3(spot.x, terrain.height_at(spot), spot.z)
		_check_true("mar aberto e sempre SEA_HEIGHT em (%.0f, %.0f) (%.5f)" % [at.x, at.z, at.y],
			absf(at.y - MapTerrain.SEA_HEIGHT) < 0.001)
		_check_true("e submerso em (%.0f, %.0f)" % [at.x, at.z],
			terrain.submerged(at))

	# A costa é rampa andável na borda INTEIRA (pedido do usuário, 2026-09-01
	# — é o adro da vila, precisa de acesso amplo). Ilha e platô glacial
	# continuam parede fora dos próprios `ACCESS_RAMPS`: ao norte da ilha
	# (oposto do único ponto de acesso dela, em z=-9) não deveria haver rampa
	# nenhuma.
	var isle_wall_land := Vector3(0.0, 0, MapTerrain.ISLAND_TOP_RADIUS - 1.0)
	isle_wall_land.y = terrain.height_at(isle_wall_land)
	var isle_wall_sea := Vector3(0.0, 0, MapTerrain.ISLAND_BASE_RADIUS + 6.0)
	isle_wall_sea.y = terrain.height_at(isle_wall_sea)
	_check_true("ilha longe do ponto de acesso ainda e LAND_HEIGHT (%.2f)" % isle_wall_land.y,
		absf(isle_wall_land.y - MapTerrain.LAND_HEIGHT) < 0.001)
	_check_true("e o mar do outro lado e parede, sem rampa (%.2f)" % isle_wall_sea.y,
		absf(isle_wall_sea.y - MapTerrain.SEA_HEIGHT) < 0.001)

	# Os 3 pontos de acesso (2 platô glacial, 1 ilha — a costa é rampa na
	# borda inteira, não precisa de ponto próprio): cada um é terra seca no
	# próprio ponto, e o vão calibrado entre `ACCESS_RAMP_INNER` e `OUTER`
	# garante rampa andável (≤45°) — a mesma conta de sempre, 1,5·altura/vão,
	# contra a diferença entre os dois níveis.
	var ramp_span := MapTerrain.ACCESS_RAMP_OUTER - MapTerrain.ACCESS_RAMP_INNER
	var ramp_height := MapTerrain.LAND_HEIGHT - MapTerrain.SEA_HEIGHT
	var ramp_slope := rad_to_deg(atan(1.5 * ramp_height / ramp_span))
	_check_true("a rampa de acesso e andavel (%.1f graus)" % ramp_slope, ramp_slope < 45.0)
	for p in MapTerrain.ACCESS_RAMPS:
		var pos := Vector3(p.x, 0, p.y)
		pos.y = terrain.height_at(pos)
		_check_true("ponto de acesso (%.1f, %.1f) esta seco (chao %.2f)" % [p.x, p.y, pos.y],
			not terrain.submerged(pos))

	# A ilha do miolo: topo seco, LAND_HEIGHT plano. Segunda exceção à regra
	# "fora da terra firme é tudo mar", e a única no meio do mapa — o topo é
	# onde a arena vive e onde o domador abre o jogo, de pé.
	var isle := Vector3(0, 0, 0)
	isle.y = terrain.height_at(isle)
	_check_true("o topo da ilha e LAND_HEIGHT (%.2f)" % isle.y,
		absf(isle.y - MapTerrain.LAND_HEIGHT) < 0.001)
	_check_true("o topo da ilha esta seco", not terrain.submerged(isle))
	var isle_edge := Vector3(0, 0, MapTerrain.ISLAND_BASE_RADIUS + 2.0)
	_check_true("mar aberto fora do raio nao e ilha", not terrain.on_island(isle_edge))

	# E a arena tem de estar EM CIMA dela, no topo plano — não na encosta.
	var arena_dist := Vector2(WorldPopulator.ARENA_SPOT.x, WorldPopulator.ARENA_SPOT.z).length()
	_check_true("a arena fica no topo plano da ilha (%.1f m do centro)" % arena_dist,
		arena_dist <= MapTerrain.ISLAND_TOP_RADIUS)
	var arena_ground := terrain.height_at(WorldPopulator.ARENA_SPOT)
	_check_true("o chao da arena esta seco (%.2f)" % arena_ground,
		not terrain.submerged(Vector3(
			WorldPopulator.ARENA_SPOT.x, arena_ground, WorldPopulator.ARENA_SPOT.z)))

	# O platô glacial: núcleo seco, LAND_HEIGHT plano. Terceira exceção à
	# regra "fora da terra firme é tudo mar" — BIO-014 tem fauna e minério
	# próprios (ver `CLAUDE.md`, minério glacial exclusivo), então ler como
	# leito de mar contradizia o resto do design.
	var glacial_core := Vector3(-35.0, 0, 35.0)
	glacial_core.y = terrain.height_at(glacial_core)
	_check_true("o nucleo do plato glacial e LAND_HEIGHT (%.2f)" % glacial_core.y,
		absf(glacial_core.y - MapTerrain.LAND_HEIGHT) < 0.001)
	_check_true("o nucleo do plato glacial esta seco", not terrain.submerged(glacial_core))

	# Mapa sem bioma de água: ninguém nada. É o padrão das bancadas.
	var dry := MapTerrain.create({})
	_check_true("terreno sem cota injetada nao molha ninguem", not dry.submerged(Vector3.ZERO))
	_check("mapa desconhecido nao tem agua", MapDressing.water_line("PZ-99"), -INF)
	terrain.free()
	dry.free()


func _test_main_scene() -> void:

	print("cena principal:")
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_check("main_scene apontada", path, "res://scenes/main.tscn")
	_check_true("arquivo da cena existe", ResourceLoader.exists(path))

	var packed: PackedScene = load(path)
	_check_true("cena carrega", packed != null)
	if packed == null:
		return

	var root: Node = packed.instantiate()
	_check_true("tem Player", root.get_node_or_null("Player") != null)
	_check_true("tem IsoCamera", root.get_node_or_null("IsoCamera") != null)
	_check_true("tem Ground", root.get_node_or_null("Ground") != null)

	var cam := root.get_node_or_null("IsoCamera") as Camera3D
	if cam:
		_check("camera e ortografica", cam.projection, Camera3D.PROJECTION_ORTHOGONAL)
		_check("pitch travado", roundf(cam.rotation_degrees.x), -30.0)
		_check("yaw travado", roundf(cam.rotation_degrees.y), 45.0)

	var player := root.get_node_or_null("Player") as CharacterBody3D
	if player:
		_check_true("Player tem colisao", player.get_node_or_null("Collision") != null)
		_check_true("Player tem script", player.get_script() != null)

		# O `y` da cena não é decoração: a origem do mapa é o topo da ILHA, a
		# 2,6 m, e o corpo nasce ali antes de a gravidade encostá-lo. Nascer
		# abaixo do relevo é nascer DENTRO dele — a física resolve empurrando
		# para um lado qualquer, e o jogo abre com o domador saltando.
		var terrain := MapTerrain.create({})
		var shape := (player.get_node("Collision") as CollisionShape3D).shape as CapsuleShape3D
		var feet := player.position.y - shape.height * 0.5
		var ground := terrain.height_at(player.position)
		_check_true("Player nasce acima do relevo (pes %.2f, chao %.2f)" % [feet, ground],
			feet >= ground)
		terrain.free()

	root.free()
