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
## Quadros pro corpo assentar depois de largar em queda livre sobre o mar
## aberto (y=6 até o leito raso, ~5,5 m de queda). Medido por sonda direta:
## em headless o `_process` da `SceneTree` roda bem mais rápido que o passo
## de física (60 Hz fixos) — a proporção observada foi de ~0,4 quadro de
## física por quadro de `_process` —, então o orçamento tem de ser em
## quadros de PROCESS, não de física, e generoso: 90 ainda pegava o corpo em
## queda livre a -15 m/s.
const SETTLE_FRAMES_OVER_SEA := 260
## Janela final (em quadros) onde a posição Y é amostrada para detectar
## oscilação residual — o corpo "quicando" mesmo já parado no leito.
const STABILITY_WINDOW := 30
## Quadros pra nadar do mar aberto, atravessar o ponto de acesso da ilha
## (`MapTerrain.ACCESS_RAMPS[2]`, a 20 m de distância) e assentar de vez no
## topo — não basta chegar na borda da rampa, tem de sobrar tempo pra
## gravidade resolver o resto da subida via colisão real.
const CROSS_FRAMES := 320
## Quadros pro corpo assentar no leito raso ANTES de começar a andar — mesma
## queda livre de y=6 que `_step_settle_check` mede (~200 quadros de
## `_process` em headless, não os 60 que a proporção físico/processo ingênua
## sugeriria).
const SETTLE_ON_GROUND_FRAMES := 220

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
## 0 = medindo a caminhada, 1 = sondando o bioma por posição, 2 = queda livre
## sobre o mar aberto, 3 = travessia a pé até o ponto de acesso da ilha.
var _phase := 0
var _probe := 0
var _probe_frames := 0
var _settle_frames := 0
var _settle_min_y := INF
var _settle_max_y := -INF
var _cross_frames := 0


func _initialize() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	_player = _scene.get_node("Player")
	_camera = _scene.get_node("IsoCamera")


func _process(_delta: float) -> bool:
	_frames += 1

	if _phase == 3:
		return _step_crossing_check()

	if _phase == 2:
		return _step_settle_check()

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
	if _probe >= probes.size():
		_phase = 2
	return false


## Larga o corpo em queda livre sobre o mar aberto (mesmo ponto da sonda de
## bioma "o mar profundo" acima) e prova que ele assenta no leito raso
## (`MapTerrain.SEA_HEIGHT`) por gravidade normal, sem quicar — e continua
## submerso lá, porque fora da terra firme é sempre mar (`submerged`),
## independente da altura.
##
## Histórico: até 2026-09-01 isto testava o EMPUXO (o corpo boiava na cota em
## vez de afundar), porque o mar tinha profundidade de verdade e um poço de
## 15 m (Mar Profundo, removido) prendia quem caísse lá numa rampa íngreme
## demais para escalar de volta andando. O poço não existe mais, e agora nem
## o mar aberto comum tem profundidade que justifique empuxo — encolher
## `SEA_HEIGHT` até o leito ficar sempre raso tornou o sistema de empuxo
## inteiro desnecessário (removido de `PlayerController`/`MapTerrain`).
func _step_settle_check() -> bool:
	if _settle_frames == 0:
		_player.global_position = biome_probes()[3][0]
		_player.velocity = Vector3.ZERO
	_settle_frames += 1
	# Amostra só a cauda: os primeiros quadros ainda são queda livre, com
	# variação grande e esperada — a pergunta aqui é se o corpo SOSSEGA no
	# leito, não a trajetória até lá.
	if _settle_frames > SETTLE_FRAMES_OVER_SEA - STABILITY_WINDOW:
		_settle_min_y = minf(_settle_min_y, _player.global_position.y)
		_settle_max_y = maxf(_settle_max_y, _player.global_position.y)
	if _settle_frames < SETTLE_FRAMES_OVER_SEA:
		return false

	print("\nqueda livre sobre o mar aberto:")
	var capsule := (_player.get_node("Collision") as CollisionShape3D).shape as CapsuleShape3D
	var feet := _player.global_position.y - capsule.height * 0.5
	_check_true("assenta no leito raso, nao boia na cota (pes %.2f, SEA_HEIGHT %.2f)" % [
		feet, MapTerrain.SEA_HEIGHT],
		absf(feet - MapTerrain.SEA_HEIGHT) < 0.1)
	_check_true("nao fica quicando parado (amplitude %.3f m nos ultimos %d quadros)" % [
		_settle_max_y - _settle_min_y, STABILITY_WINDOW],
		(_settle_max_y - _settle_min_y) < 0.15)
	var terrain := _scene.get_node_or_null("Ground") as MapTerrain
	if terrain:
		_check_true("continua submerso, longe de qualquer terra firme",
			terrain.submerged(_player.global_position))

	_phase = 3
	return false


## Diferente da fase 2 (queda livre no mar aberto): aqui o corpo ANDA de
## verdade, via input real (não teleporte), do mar aberto até dentro de um
## ponto de acesso (`MapTerrain.ACCESS_RAMPS[2]`, o da ilha da arena) — prova
## que a rampa calibrada (`ACCESS_RAMP_INNER`/`OUTER`) é andável na prática,
## não só na conta analítica que `test_world.gd` já confere.
##
## Início no mar aberto, ao sul do ponto de acesso (que fica em (0, -9), de
## frente pra costa) — assenta no leito raso primeiro (mesma folga de
## `_step_settle_check`), depois anda pra dentro dele. `move_left` +
## `move_down` juntos (matemática de `IsoCamera.screen_to_world_direction`,
## mesma da direção W já provada em `_test_direction_math` de
## `test_world.gd`) andam em +Z do mundo, direto rumo ao ponto de acesso.
func _step_crossing_check() -> bool:
	if _cross_frames == 0:
		_player.global_position = Vector3(0.0, 6.0, -20.0)
		_player.velocity = Vector3.ZERO

	_cross_frames += 1

	if _cross_frames == SETTLE_ON_GROUND_FRAMES:
		Input.action_press("move_left")
		Input.action_press("move_down")
	if _cross_frames < SETTLE_ON_GROUND_FRAMES + CROSS_FRAMES:
		return false

	Input.action_release("move_left")
	Input.action_release("move_down")

	print("\ntravessia a nado ate o ponto de acesso da ilha:")
	var terrain := _scene.get_node_or_null("Ground") as MapTerrain
	var capsule := (_player.get_node("Collision") as CollisionShape3D).shape as CapsuleShape3D
	var feet := _player.global_position.y - capsule.height * 0.5
	_check_true("passou de verdade pelo ponto de acesso (z %.2f, partiu de -20)" % _player.global_position.z,
		_player.global_position.z > -15.0)
	_check_true("assentou em LAND_HEIGHT depois de subir a rampa (pes %.2f, LAND_HEIGHT %.2f)" % [
		feet, MapTerrain.LAND_HEIGHT],
		absf(feet - MapTerrain.LAND_HEIGHT) < 0.1)
	if terrain:
		_check_true("o terreno concorda: esta em terra firme",
			terrain.on_dry_land(_player.global_position))

	_summary()
	return true


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
