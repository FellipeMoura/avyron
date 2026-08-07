extends SceneTree

## Prova que a cena principal roda de verdade: instancia, injeta input e
## verifica que o corpo se moveu e a câmera acompanhou.
##
##     godot --headless --script res://scripts/dev/test_playable.gd
##
## As outras suítes testam lógica isolada. Esta roda a árvore de cena com
## física ativa — é o teste que responde "dá para jogar?" em vez de
## "as contas fecham?".

const SETTLE_FRAMES := 5
const RUN_FRAMES := 90

var _scene: Node
var _player: CharacterBody3D
var _camera: Camera3D
var _frames := 0
var _start_pos: Vector3
var _start_cam: Vector3
## Medido em quadros de FÍSICA, não de renderização: `_process` roda solto em
## headless enquanto o movimento acontece a 60 Hz fixos. Usar o contador
## errado fazia a velocidade medida parecer um terço da real.
var _start_physics_frame := 0
var _elapsed_physics := 0
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	_player = _scene.get_node("Player")
	_camera = _scene.get_node("IsoCamera")


func _process(_delta: float) -> bool:
	_frames += 1

	# Deixa o corpo assentar no chão antes de medir — no primeiro quadro ele
	# ainda está caindo, e a gravidade poluiria a medição do deslocamento.
	if _frames == SETTLE_FRAMES:
		_start_pos = _player.global_position
		_start_cam = _camera.global_position
		_start_physics_frame = Engine.get_physics_frames()
		Input.action_press("move_up")
		return false

	if _frames < SETTLE_FRAMES:
		return false

	_elapsed_physics = Engine.get_physics_frames() - _start_physics_frame
	if _elapsed_physics < RUN_FRAMES:
		return false

	Input.action_release("move_up")
	_report()
	return true


func _report() -> void:
	var moved := _player.global_position - _start_pos
	moved.y = 0.0

	print("cena jogavel:")
	_check_true("o jogador se moveu", moved.length() > 1.0,
		"%.2f m em %d quadros de fisica" % [moved.length(), _elapsed_physics])

	# W deve andar para onde a câmera olha, não na diagonal do mundo.
	var expected := IsoCamera.screen_to_world_direction(Vector2(0, -1))
	_check_true("andou na direcao de tela correta",
		moved.normalized().dot(expected) > 0.99,
		"direcao %s, esperada %s" % [str(moved.normalized().snappedf(0.01)), str(expected.snappedf(0.01))])

	_check_true("nao afundou no chao", absf(_player.global_position.y - _start_pos.y) < 0.1,
		"y = %.2f" % _player.global_position.y)

	# Velocidade de caminhada: 4 m/s. A aceleração de 0.15 s puxa a média um
	# pouco para baixo, então a faixa aceita começa em 3 m/s.
	var seconds := float(_elapsed_physics) / Engine.physics_ticks_per_second
	var speed := moved.length() / seconds
	_check_true("velocidade proxima de andar (4 m/s)", speed > 3.0 and speed < 4.5,
		"%.2f m/s" % speed)

	var cam_moved := _camera.global_position - _start_cam
	_check_true("a camera acompanhou", cam_moved.length() > 0.5,
		"%.2f m" % cam_moved.length())
	_check_true("a camera nao girou",
		absf(_camera.rotation_degrees.x - IsoCamera.PITCH_DEGREES) < 0.01
		and absf(_camera.rotation_degrees.y - IsoCamera.YAW_DEGREES) < 0.01,
		"pitch %.1f, yaw %.1f" % [_camera.rotation_degrees.x, _camera.rotation_degrees.y])
	_check_true("a camera continua ortografica",
		_camera.projection == Camera3D.PROJECTION_ORTHOGONAL)

	# O corpo gira para encarar o movimento.
	var facing := -_player.global_transform.basis.z
	facing.y = 0.0
	_check_true("o corpo encara a direcao do movimento",
		facing.normalized().dot(moved.normalized()) > 0.9,
		"dot = %.3f" % facing.normalized().dot(moved.normalized()))

	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


func _check_true(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s%s" % [label, (" — " + detail) if detail != "" else ""])
	else:
		_failures += 1
		printerr("  FAIL %s%s" % [label, (" — " + detail) if detail != "" else ""])
