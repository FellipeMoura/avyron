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
## Quadros entre teleportar o corpo e ler o bioma. A troca é detectada no
## `_process` do `WorldRoot`, então ler no mesmo quadro em que se move leria o
## bioma anterior — e o teste passaria pelo motivo errado na primeira sonda,
## que é a que ainda não mudou de lugar.
const PROBE_FRAMES := 3

## Os lugares declarados do PZ-01 e o bioma que cada um deve responder.
##
## São as MESMAS geografias que o `MapTerrain` levanta — o platô da costa
## além da rampa, o miolo onde a ilha subiu, o mar aberto lá fora —, e é essa
## coincidência que a sonda prova: a partição vem do catálogo em coordenadas
## normalizadas, o relevo vem de constantes em metros, e os dois têm de estar
## descrevendo o mesmo mapa. Quando divergirem, é aqui que aparece.
##
## O `y` é alto de propósito: o corpo cai até o chão sozinho, e a partição não
## olha altura nenhuma — pôr o corpo dentro da malha só criaria uma ejeção de
## física para o teste ter de esperar passar.
## As posições são DERIVADAS das constantes do terreno, nunca metros escritos
## à mão: o resize de 2026-08-28 moveu a costa de -16 para -32, e uma sonda
## fixa em -23 teria continuado verde medindo o bioma errado no lugar errado.
static func biome_probes() -> Array:
	var half := float(MapTerrain.SIZE) * 0.5
	# Os CINCO biomas, um ponto cada. Cobrir só três deixava os dois últimos —
	# que são precisamente os que nasceram sem região e ficaram inalcançáveis
	# por semanas — sem nenhuma sonda que provasse que o mundo os alcança.
	#
	# A costa e o miolo saem das constantes do relevo, porque são geografia de
	# código. Os outros três saem em FRAÇÃO do meio-lado, porque são decisão do
	# desenho espacial e vivem no catálogo — escritos em metros, o próximo
	# resize os deixaria apontando para o bioma errado calados.
	return [
		[Vector3(MapTerrain.COAST_CENTER_X, 6.0, MapTerrain.COAST_TOP - 5.0), "BIO-002", "o plato da costa"],
		[Vector3(0.0, 6.0, 0.0), "BIO-003", "o miolo do mapa"],
		[Vector3(half * 0.2, 6.0, -half * 0.3), "BIO-001", "o mar raso"],
		[Vector3(half * 0.5, 6.0, half * 0.67), "BIO-004", "o mar profundo"],
		[Vector3(-half * 0.67, 6.0, half * 0.83), "BIO-014", "a plataforma glacial"],
	]

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
## 0 = medindo a caminhada, 1 = sondando o bioma por posição.
var _phase := 0
var _probe := 0
var _probe_frames := 0


func _initialize() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	_player = _scene.get_node("Player")
	_camera = _scene.get_node("IsoCamera")


func _process(_delta: float) -> bool:
	_frames += 1

	if _phase == 1:
		return _step_biome_probes()

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
	_phase = 1
	return false


## Teleporta o corpo para cada lugar declarado e cobra o bioma que o MUNDO
## responde — não o `MapBiomes` isolado, que `test_data` já cobre.
##
## A diferença entre as duas suítes é o que cada uma prova. Lá, que a
## geometria das regiões está certa. Aqui, que o `WorldRoot` está de fato
## perguntando: um `current_biome()` correto e um `_biome_code` que nunca
## acompanha passariam na outra suíte e deixariam a mineração presa no bioma
## da abertura — que é exatamente o estado anterior a esta rodada, e ele
## passava em tudo.
func _step_biome_probes() -> bool:
	var world := _scene as Node
	if _probe >= biome_probes().size():
		_summary()
		return true

	var probes := biome_probes()
	var probe: Array = probes[_probe]
	if _probe_frames == 0:
		_player.global_position = probe[0]
		_player.velocity = Vector3.ZERO
	_probe_frames += 1
	if _probe_frames <= PROBE_FRAMES:
		return false

	var expected := str(probe[1])
	_check_true("em %s o mundo responde %s" % [str(probe[2]), expected],
		str(world.call("current_biome")) == expected,
		"respondeu %s" % str(world.call("current_biome")))
	# O cache que a mineração e o painel leem, por reflexão — mesmo padrão do
	# `_world.get("_duel")` do resto das suítes.
	_check_true("o cache do mundo acompanhou em %s" % str(probe[2]),
		str(world.get("_biome_code")) == expected,
		"cache %s" % str(world.get("_biome_code")))

	_probe += 1
	_probe_frames = 0
	return false


func _report() -> void:
	var moved := _player.global_position - _start_pos
	moved.y = 0.0

	print("cena jogavel:")
	# A caminhada primeiro; o bioma por posição vem depois, em _step_biome_probes.
	_check_true("o jogador se moveu", moved.length() > 1.0,
		"%.2f m em %d quadros de fisica" % [moved.length(), _elapsed_physics])

	# W deve andar para onde a câmera olha, não na diagonal do mundo.
	var expected := IsoCamera.screen_to_world_direction(Vector2(0, -1))
	_check_true("andou na direcao de tela correta",
		moved.normalized().dot(expected) > 0.99,
		"direcao %s, esperada %s" % [str(moved.normalized().snappedf(0.01)), str(expected.snappedf(0.01))])

	# "Não afundou" era "o `y` não mudou" enquanto a origem do mapa era chão
	# plano. Deixou de ser quando a ILHA subiu ali: 90 quadros de W descem a
	# rampa, e essa queda é o relevo fazendo seu trabalho, não o corpo furando
	# o chão. A medida que continua valendo — e que também valeria no plano —
	# é a distância do PÉ ao terreno sob ele.
	var terrain := _scene.get_node_or_null("Ground") as MapTerrain
	var capsule := (_player.get_node("Collision") as CollisionShape3D).shape as CapsuleShape3D
	var feet := _player.global_position.y - capsule.height * 0.5
	var ground := terrain.height_at(_player.global_position) if terrain else 0.0
	_check_true("nao afundou no chao", absf(feet - ground) < 0.25,
		"pes %.2f, chao %.2f" % [feet, ground])

	# Velocidade de caminhada: 5.2 m/s (WALK_SPEED). A aceleração de 0.15 s
	# puxa a média um pouco para baixo, então a faixa aceita começa em 3.9 m/s.
	var seconds := float(_elapsed_physics) / Engine.physics_ticks_per_second
	var speed := moved.length() / seconds
	_check_true("velocidade proxima de andar (5.2 m/s)", speed > 3.9 and speed < 5.9,
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


func _summary() -> void:
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
