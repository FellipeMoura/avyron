class_name CreatureActor
extends CharacterBody3D

## Uma criatura no mapa.
##
## O corpo é placeholder — cápsula escalada pelo tamanho de jogo e colorida
## pelo elemento. O que já é definitivo é tudo o mais: escala real em unidades
## Godot, máquina de estados de navegação, raio de detecção. Trocar a forma
## por um `.glb` depois não mexe em nada disto.
##
## Especificação: `movimento-e-controles`, seção "IA no mapa".

enum State { IDLE, PATROL, ALERT, ENGAGE }

## Raio de detecção em campo aberto. Bioma denso reduz para 3 m — ver o
## documento; enquanto não houver bioma modelado, vale o aberto.
const DETECT_RADIUS_OPEN := 6.0
const DETECT_RADIUS_DENSE := 3.0

## Velocidade de perseguição: 80% da caminhada do jogador, para dar espaço de
## fuga sem tornar a perseguição trivial.
const CHASE_SPEED := PlayerController.WALK_SPEED * 0.8
const PATROL_SPEED := 1.2

const IDLE_MIN := 1.5
const IDLE_MAX := 4.0
const PATROL_RADIUS := 6.0

## Distância em que o encontro dispara.
const ENGAGE_RADIUS := 1.6

signal engaged(actor: CreatureActor)

var creature_code := ""
var display_name := ""
var element_code := ""
var size_meters := 1.8
## Espécies de perfil defensivo não iniciam combate — só reagem.
var aggressive := true

var state: State = State.IDLE
var _home := Vector3.ZERO
var _patrol_target := Vector3.ZERO
var _timer := 0.0
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _engaged_once := false

var _mesh: MeshInstance3D
var _collision: CollisionShape3D


## Cor por elemento. Placeholder honesto: a paleta final vem da banda
## dominante em `identidade-visual`, mas aqui o que importa é conseguir
## distinguir de longe o que se está enfrentando.
const ELEMENT_COLORS := {
	"ELE-001": Color("#C6552F"),  # Fogo
	"ELE-002": Color("#3E6F8E"),  # Agua
	"ELE-003": Color("#7A8C6B"),  # Natureza
	"ELE-004": Color("#8A7047"),  # Terra
	"ELE-005": Color("#C9A227"),  # Eletricidade
	"ELE-006": Color("#8FB8C9"),  # Gelo
}


static func create(data: Dictionary, at: Vector3, player: Node3D, seed_value: int) -> CreatureActor:
	var a := CreatureActor.new()
	a.creature_code = str(data["code"])
	a.display_name = str(data["name"])
	a.element_code = str(data["element"])
	a.size_meters = float(data["stats"]["sizeMeters"])
	# Herói é chefe de bioma: sempre engaja. O resto varia com o papel.
	a.aggressive = str(data.get("role", "")) != "regular"
	a._player = player
	a._home = at
	a.position = at
	a._rng.seed = seed_value
	return a


func _ready() -> void:
	_build_body()
	_enter_idle()


func _build_body() -> void:
	# A cápsula usa o tamanho como ALTURA e deriva o raio dela, para o volume
	# crescer junto e um Arthropleura não virar um poste fino.
	var radius := clampf(size_meters * 0.28, 0.15, 1.2)
	var height := maxf(size_meters, radius * 2.0 + 0.01)

	var mesh := CapsuleMesh.new()
	mesh.height = height
	mesh.radius = radius

	var material := StandardMaterial3D.new()
	material.albedo_color = ELEMENT_COLORS.get(element_code, Color("#6B7280"))
	material.roughness = 0.9
	mesh.material = material

	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = mesh
	add_child(_mesh)

	var shape := CapsuleShape3D.new()
	shape.height = height
	shape.radius = radius
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	_collision.shape = shape
	add_child(_collision)

	# Marca de frente, como no jogador — sem ela não dá para ler para onde a
	# criatura está virada.
	var nose := MeshInstance3D.new()
	nose.name = "Facing"
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(radius * 0.4, radius * 0.4, radius * 0.9)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, height * 0.2, -(radius + radius * 0.45))
	add_child(nose)

	position.y = height * 0.5


func _physics_process(delta: float) -> void:
	if _player == null:
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()

	match state:
		State.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_enter_patrol()
		State.PATROL:
			_move_towards(_patrol_target, PATROL_SPEED, delta)
			if global_position.distance_to(_patrol_target) < 0.6:
				_enter_idle()
		State.ALERT:
			# Encara o jogador mas não avança: dá ao jogador a chance de
			# recuar antes de virar luta.
			_face(to_player, delta)
			_brake(delta)
			if distance > DETECT_RADIUS_OPEN * 1.3:
				_enter_idle()
			elif aggressive:
				state = State.ENGAGE
		State.ENGAGE:
			_move_towards(_player.global_position, CHASE_SPEED, delta)

	# Encostar sempre inicia o combate, inclusive em ALERT.
	#
	# Antes isto só valia em ENGAGE, e o efeito era que criatura de perfil
	# defensivo — que por design nunca sai de ALERT — era impossível de
	# enfrentar: ela olhava para o jogador para sempre. Quem não persegue
	# ainda reage a quem chega perto demais.
	if state in [State.ALERT, State.ENGAGE] and distance <= ENGAGE_RADIUS and not _engaged_once:
		_engaged_once = true
		engaged.emit(self)

	if state in [State.IDLE, State.PATROL] and distance <= DETECT_RADIUS_OPEN:
		state = State.ALERT

	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _enter_idle() -> void:
	state = State.IDLE
	_timer = _rng.randf_range(IDLE_MIN, IDLE_MAX)
	velocity = Vector3.ZERO


func _enter_patrol() -> void:
	state = State.PATROL
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(1.5, PATROL_RADIUS)
	_patrol_target = _home + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _move_towards(target: Vector3, speed: float, delta: float) -> void:
	var dir := target - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face(dir, delta)


func _brake(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 12.0 * delta)
	velocity.x = h.x
	velocity.z = h.z


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var d := direction.normalized()
	# -Z é a frente no Godot, como no controlador do jogador.
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), clampf(8.0 * delta, 0.0, 1.0))


## Permite reengajar depois de uma batalha resolvida.
func reset_engagement() -> void:
	_engaged_once = false
	_enter_idle()
