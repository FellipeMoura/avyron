extends SceneTree

## Gerador one-shot do input map e da cena principal.
##
##     godot --headless --script res://scripts/dev/setup_project.gd
##
## Existe porque `.tscn` e a seção `[input]` de `project.godot` são formatos
## serializados que erram fácil quando escritos à mão. Gerando pelo próprio
## engine, o arquivo sai válido por construção.
##
## Idempotente: rodar de novo reescreve o mesmo resultado. Depois que o
## projeto crescer, a edição normal é pelo editor — este script é andaime
## de bootstrap.

func _init() -> void:
	_setup_input_map()
	_build_main_scene()
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/main.tscn")
	# O `*` marca o script como singleton instanciado. `Bestiary` (o autoload)
	# e `BestiaryData` (o class_name) precisam ser nomes diferentes — o Godot
	# recusa a colisão.
	ProjectSettings.set_setting("autoload/Bestiary", "*res://scripts/data/bestiary_data.gd")

	var err := ProjectSettings.save()
	if err != OK:
		printerr("falha ao salvar project.godot: ", err)
		quit(1)
		return

	print("project.godot e scenes/main.tscn gerados.")
	quit(0)


# ---------------------------------------------------------------------------
# input
# ---------------------------------------------------------------------------

## Teclado + gamepad desde o dia zero, com rebind completo previsto.
## Setas acompanham WASD porque custam nada e cobrem quem espera por elas.
func _setup_input_map() -> void:
	_action("move_left",  [KEY_A, KEY_LEFT],  JOY_AXIS_LEFT_X, -1.0)
	_action("move_right", [KEY_D, KEY_RIGHT], JOY_AXIS_LEFT_X,  1.0)
	_action("move_up",    [KEY_W, KEY_UP],    JOY_AXIS_LEFT_Y, -1.0)
	_action("move_down",  [KEY_S, KEY_DOWN],  JOY_AXIS_LEFT_Y,  1.0)
	# Correr: shift no teclado, gatilho direito no gamepad.
	_action("run", [KEY_SHIFT], JOY_AXIS_TRIGGER_RIGHT, 1.0)


func _action(name: String, keycodes: Array, axis: int, axis_value: float) -> void:
	var events: Array = []

	for kc in keycodes:
		var key := InputEventKey.new()
		# Físico, não por keycode: em teclado AZERTY o W fica onde o Z está,
		# e o jogador espera a tecla na mesma posição, não com a mesma letra.
		key.physical_keycode = kc
		events.append(key)

	var joy := InputEventJoypadMotion.new()
	joy.axis = axis
	joy.axis_value = axis_value
	events.append(joy)

	ProjectSettings.set_setting("input/" + name, {
		"deadzone": 0.2,
		"events": events,
	})


# ---------------------------------------------------------------------------
# cena
# ---------------------------------------------------------------------------

## Cena mínima que prova a câmera travada e a locomoção: chão, um corpo
## controlável, a câmera isométrica e a key light fixa.
##
## Tudo aqui é placeholder de forma — cápsula em vez de modelo, plano em vez
## de terreno. O que está sendo validado é o enquadramento e o movimento.
func _build_main_scene() -> void:
	var root := Node3D.new()
	root.name = "Main"

	# --- chão ---------------------------------------------------------------
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	root.add_child(ground)
	ground.owner = root

	var ground_mesh := MeshInstance3D.new()
	ground_mesh.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground_mesh.mesh = plane
	ground.add_child(ground_mesh)
	ground_mesh.owner = root

	var ground_col := CollisionShape3D.new()
	ground_col.name = "Collision"
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	ground_col.shape = box
	ground_col.position = Vector3(0, -0.1, 0)
	ground.add_child(ground_col)
	ground_col.owner = root

	# --- jogador ------------------------------------------------------------
	# Cápsula de 1.8 m: a convenção de escala é 1 metro real = 1 unidade
	# Godot, então a altura precisa ser plausível desde o placeholder.
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://scripts/world/player_controller.gd"))
	player.position = Vector3(0, 1.0, 0)
	root.add_child(player)
	player.owner = root

	var player_mesh := MeshInstance3D.new()
	player_mesh.name = "Mesh"
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	player_mesh.mesh = capsule
	player.add_child(player_mesh)
	player_mesh.owner = root

	# Nariz para dar leitura de direção — sem isso não dá para ver o corpo
	# girar para encarar o movimento.
	var nose := MeshInstance3D.new()
	nose.name = "Facing"
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.15, 0.15, 0.4)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 0.4, 0.4)
	player.add_child(nose)
	nose.owner = root

	var player_col := CollisionShape3D.new()
	player_col.name = "Collision"
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.height = 1.8
	capsule_shape.radius = 0.35
	player_col.shape = capsule_shape
	player.add_child(player_col)
	player_col.owner = root

	# --- câmera -------------------------------------------------------------
	# Projeção e ângulo são gravados na cena, não só aplicados em _ready().
	# Sem isso o editor mostra uma perspectiva qualquer e o enquadramento só
	# aparece ao rodar o jogo — o que torna impossível compor uma cena.
	# O script continua reaplicando em _ready() para o valor não derivar.
	var cam := Camera3D.new()
	cam.name = "IsoCamera"
	cam.set_script(load("res://scripts/world/iso_camera.gd"))
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 12.0
	cam.near = 0.05
	cam.far = 200.0
	cam.rotation_degrees = Vector3(IsoCamera.PITCH_DEGREES, IsoCamera.YAW_DEGREES, 0.0)

	var cam_basis := Basis.from_euler(Vector3(
		deg_to_rad(IsoCamera.PITCH_DEGREES), deg_to_rad(IsoCamera.YAW_DEGREES), 0.0
	))
	cam.position = player.position - cam_basis * Vector3(0, 0, -IsoCamera.RIG_DISTANCE)

	cam.set("target_path", NodePath("../Player"))
	root.add_child(cam)
	cam.owner = root

	# --- luz ----------------------------------------------------------------
	# Uma key light direcional fixa, conforme a direção de arte. Sombra
	# dinâmica fica desligada: criaturas usam blob decal sob o corpo.
	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = Vector3(-50, -45, 0)
	light.light_energy = 1.0
	light.shadow_enabled = false
	root.add_child(light)
	light.owner = root

	# --- salvar -------------------------------------------------------------
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		printerr("falha ao empacotar a cena: ", pack_err)
		root.free()
		return

	var save_err := ResourceSaver.save(packed, "res://scenes/main.tscn")
	if save_err != OK:
		printerr("falha ao salvar a cena: ", save_err)

	root.free()
