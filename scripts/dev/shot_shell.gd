extends SceneTree

## Captura de comparação: dois corpos lado a lado, na câmera do jogo
## (ortográfica, 30°/45°), com luz parecida com a do PZ-01, tocando o mesmo
## clipe. Serve para julgar uma casca nova contra o corpo que ela substitui
## sem abrir o editor.
##
## Precisa de janela (renderiza de verdade), então roda SEM `--headless`:
##
##     godot --path . --script res://scripts/dev/shot_shell.gd -- --a /models/dev/manequim-mestre.glb --b /models/CRT-005.glb --out C:/.../comparacao.png [--clip Idle] [--size 1.4]
##
## Grava a imagem depois de alguns quadros (o AnimationPlayer precisa
## avançar para o clipe sair da pose de bind) e sai.

var _a := "/models/CRT-005.glb"
var _b := "/models/CRT-005.glb"
var _out := "user://comparacao.png"
var _clip := "Idle"
var _size := 1.4
## Giro extra dos corpos em graus: 0 = de frente para a câmera, 180 = de
## costas (para ver cauda e espinhos dorsais), 90 = de lado.
var _face := 0.0
var _frames := 0
var _viewport: SubViewport


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--a": _a = args[i + 1]
			"--b": _b = args[i + 1]
			"--out": _out = args[i + 1]
			"--clip": _clip = args[i + 1]
			"--size": _size = float(args[i + 1])
			"--face": _face = float(args[i + 1])

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	root.add_child(_viewport)

	var world := Node3D.new()
	_viewport.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.16, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.7, 0.8)
	e.ambient_light_energy = 0.9
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	world.add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.3, 0.32)
	fm.roughness = 1.0
	plane.material = fm
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)

	_spawn(world, _a, Vector3(-1.1, 0, 0), "A")
	_spawn(world, _b, Vector3(1.1, 0, 0), "B")

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.2
	# Mesma inclinação da câmera do jogo: 30° de pitch, 45° de yaw.
	var yaw := deg_to_rad(45.0)
	var pitch := deg_to_rad(30.0)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	world.add_child(cam)
	# `look_at` exige o nó na árvore — por isso depois do `add_child`.
	cam.look_at_from_position(dir * 12.0 + Vector3(0, 0.8, 0), Vector3(0, 0.8, 0), Vector3.UP)
	cam.current = true


func _spawn(parent: Node3D, model_url: String, at: Vector3, label: String) -> void:
	var visual := CreatureActor.build_visual(_size, "ELE-002", "CRT-SHOT-" + label, model_url)
	var mesh: Node3D = visual["mesh"]
	mesh.position = at + Vector3(0, float(visual["height"]) * 0.5, 0)
	# Vira de frente pra câmera (que está no quadrante +X/+Z).
	mesh.rotation.y = deg_to_rad(45.0 + 180.0 + _face)
	parent.add_child(mesh)
	var anim: AnimationPlayer = visual.get("anim")
	if anim != null and anim.has_animation(_clip):
		anim.play(_clip)
		anim.seek(0.45, true)
	print("%s: %s -> %s clipes, altura %.2f" % [label, model_url, str(anim.get_animation_list().size()) if anim else "0", float(visual["height"])])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 20:
		return false
	var img := _viewport.get_texture().get_image()
	var err := img.save_png(_out)
	print("captura: %s (%s)" % [_out, "ok" if err == OK else error_string(err)])
	quit(0 if err == OK else 1)
	return true
