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

	root.free()
