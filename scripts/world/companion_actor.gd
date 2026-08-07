class_name CompanionActor
extends Node3D

## A criatura ativa do jogador, andando ao lado dele no mapa.
##
## Puramente visual: sem CharacterBody3D, sem colisão. Isso é intencional —
## a companheira não pode ser clicável (o raycast do clique cai só em criaturas
## selvagens), não deve empurrar nem ser empurrada pelo jogador, e não precisa
## de gravidade porque flutua na altura de encaramento do próprio corpo.
##
## Segue o jogador em coordenadas locais dele (atrás e ao lado), o que faz a
## companheira orbitar quando o jogador gira, em vez de ficar cravada numa
## direção do mundo.

## Offset em espaço local do jogador. -Z é a frente; a companheira anda meio
## passo atrás e um pouco ao lado, para não obstruir o corpo dele na câmera
## isométrica.
const FOLLOW_OFFSET := Vector3(0.7, 0.0, 1.5)

## Suavização do follow: quanto maior, mais rápida a companheira "cola" no
## offset alvo. 4.0 dá a leitura de "seguindo" sem parecer arrastada nem
## teleportada.
const FOLLOW_SMOOTHING := 4.0

## Amplitude e frequência do bob vertical. Um trilobita parado que não
## respira é um adereço no chão; um leve sobe-e-desce dá vida sem custar
## nada — e casa com o rig flutuante que Loricati usa por padrão.
const BOB_AMPLITUDE := 0.04
const BOB_HZ := 1.1

var creature_code := ""
var display_name := ""
var element_code := ""
var size_meters := 1.8

var _player: Node3D
var _mesh_root: Node3D
var _base_y := 0.0
var _time := 0.0


## Ponto de entrada. `db` é o Bestiary autoload; `code` é o CRT-XXX da
## criatura ativa; `player` é o corpo do domador para seguir.
static func create(db: BestiaryData, code: String, player: Node3D) -> CompanionActor:
	var c := db.creature(code)
	if c.is_empty():
		push_error("CompanionActor: criatura %s nao existe no bundle" % code)
		return null

	var actor := CompanionActor.new()
	actor.creature_code = code
	actor.display_name = str(c["name"])
	actor.element_code = str(c["element"])
	actor.size_meters = float(c["stats"]["sizeMeters"])
	actor._player = player
	return actor


func _ready() -> void:
	if _player == null:
		push_error("CompanionActor: sem jogador para seguir")
		return

	var visual := CreatureActor.build_capsule_visual(size_meters, element_code)
	_mesh_root = Node3D.new()
	_mesh_root.name = "Visual"
	_mesh_root.add_child(visual["mesh"])
	_mesh_root.add_child(visual["nose"])
	add_child(_mesh_root)

	# A cápsula do CreatureActor sobe meia-altura via `position.y` do próprio
	# actor; aqui, como o mesh vive num nó filho, o offset vai nele. Guardo
	# como base para o bob oscilar em torno.
	_base_y = float(visual["height"]) * 0.5
	_mesh_root.position.y = _base_y

	# Aparece já na posição correta — sem isso o primeiro quadro tem a
	# companheira na origem do mundo e ela "voa" para o jogador.
	global_position = _target_position()


func _process(delta: float) -> void:
	if _player == null:
		return

	_time += delta

	var target := _target_position()
	global_position = global_position.lerp(target, clampf(FOLLOW_SMOOTHING * delta, 0.0, 1.0))

	# Bob vertical no mesh, não no nó raiz — assim o follow lateral e o bob
	# são independentes e não brigam pelo mesmo canal.
	if _mesh_root:
		_mesh_root.position.y = _base_y + sin(_time * TAU * BOB_HZ) * BOB_AMPLITUDE

	# Encara para onde o jogador está encarando. Girar em separado (em vez de
	# copiar o transform inteiro) mantém o smoothing de posição intocado.
	rotation.y = _player.rotation.y


func _target_position() -> Vector3:
	# Basis do jogador aplicada ao offset local — quando ele gira, a
	# companheira orbita junto.
	return _player.global_position + _player.global_transform.basis * FOLLOW_OFFSET


## Trocar a criatura ativa (ex.: quando o jogador manda outra do time à
## frente). Reconstrói o corpo com o novo elemento e tamanho.
func set_creature(db: BestiaryData, code: String) -> void:
	var c := db.creature(code)
	if c.is_empty():
		return
	creature_code = code
	display_name = str(c["name"])
	element_code = str(c["element"])
	size_meters = float(c["stats"]["sizeMeters"])

	if _mesh_root:
		_mesh_root.queue_free()
	var visual := CreatureActor.build_capsule_visual(size_meters, element_code)
	_mesh_root = Node3D.new()
	_mesh_root.name = "Visual"
	_mesh_root.add_child(visual["mesh"])
	_mesh_root.add_child(visual["nose"])
	add_child(_mesh_root)
	_base_y = float(visual["height"]) * 0.5
	_mesh_root.position.y = _base_y
