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

## Coleira até `_home`. Quando a criatura ultrapassa esta distância, o próximo
## alvo de patrulha vem enviesado de volta em vez de sorteio livre — sem isso
## ela pode vagar indefinidamente para fora do bioma.
const HOME_LEASH := 8.0

## Multiplicador de energia da emissão quando a criatura está selecionada.
## Um valor baixo evita "queimar" a cor do elemento — o realce tem de ser lido
## como "esta é a selecionada", não como um efeito de luz forte.
const SELECT_EMISSION_ENERGY := 0.55

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
var _material: StandardMaterial3D
var _selected := false


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
	var visual := build_capsule_visual(size_meters, element_code)
	_mesh = visual["mesh"]
	_material = visual["material"]
	add_child(_mesh)
	add_child(visual["nose"])

	var height: float = visual["height"]
	var radius: float = visual["radius"]

	var shape := CapsuleShape3D.new()
	shape.height = height
	shape.radius = radius
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	_collision.shape = shape
	add_child(_collision)

	position.y = height * 0.5


## Raio do corpo, derivado do tamanho de jogo.
##
## A cápsula usa o tamanho como ALTURA e tira o raio dele, para o volume crescer
## junto e um Arthropleura não virar um poste fino.
##
## Está separado do `build_capsule_visual` porque o afastamento de duelo precisa
## saber onde a **borda** de cada corpo está, e não só desenhá-lo: dois bichos
## de 2,5 m parados à mesma distância central que dois trilobitas ficariam
## encostados. Duas derivações do raio em lugares diferentes discordariam no dia
## em que uma delas mudasse.
static func capsule_radius(size_meters: float) -> float:
	return clampf(size_meters * 0.28, 0.15, 1.2)


## Constrói o visual reutilizável de uma criatura: cápsula colorida pelo
## elemento, com a marca de frente que deixa ler a direção de encaramento.
## Devolve um dicionário com os nós e as medidas — o CompanionActor consome o
## mesmo layout, pra manter a leitura consistente entre selvagem e domesticada.
##
## O material com emissão preparada (desligada) já sai daqui, então quem quiser
## acender o realce depois só precisa de `emission_enabled = true`.
static func build_capsule_visual(size_meters: float, element_code: String) -> Dictionary:
	var radius := capsule_radius(size_meters)
	var height := maxf(size_meters, radius * 2.0 + 0.01)

	var mesh := CapsuleMesh.new()
	mesh.height = height
	mesh.radius = radius

	var material := StandardMaterial3D.new()
	material.albedo_color = ELEMENT_COLORS.get(element_code, Color("#6B7280"))
	material.roughness = 0.9
	material.emission = ELEMENT_COLORS.get(element_code, Color("#F2EDE0"))
	material.emission_energy_multiplier = SELECT_EMISSION_ENERGY
	material.emission_enabled = false
	mesh.material = material

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = mesh

	# Marca de frente, como no jogador — sem ela não dá para ler para onde a
	# criatura está virada.
	var nose := MeshInstance3D.new()
	nose.name = "Facing"
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(radius * 0.4, radius * 0.4, radius * 0.9)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, height * 0.2, -(radius + radius * 0.45))

	return {
		"mesh": mesh_node,
		"nose": nose,
		"material": material,
		"height": height,
		"radius": radius,
	}


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
			# Zerar X/Z aqui não é redundante: `move_and_slide` devolve a
			# velocidade AJUSTADA pela resolução de colisão com o chão, e sem
			# reescrever a cada quadro esse resíduo (~10⁻³) se acumula e vira
			# a "tremedeira" visível em criaturas em repouso. Os outros
			# estados não sofrem porque todos sobrescrevem velocity a cada
			# quadro — PATROL/ENGAGE via `_move_towards`, ALERT via `_brake`.
			velocity.x = 0.0
			velocity.z = 0.0
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
			# Sem esta saída, uma criatura que engajou continua perseguindo
			# para sempre — mesmo com o jogador do outro lado do mapa. Um
			# múltiplo generoso do raio de detecção dá pré-luta em fuga
			# tensa mas evita a "sombra" que persegue infinitamente.
			if distance > DETECT_RADIUS_OPEN * 2.0:
				_enter_idle()

	# Contato não inicia mais combate — o disparo do encontro é por clique.
	# As agressivas continuam perseguindo por pressão visual; a decisão de
	# entrar em batalha é sempre do jogador, no `WorldRoot`.

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
	# Ancora o alvo na POSIÇÃO ATUAL, não em `_home`. O esquema antigo pegava
	# alvo em `_home + offset`, e uma criatura que tivesse drifted para o
	# extremo oeste do seu círculo podia receber o próximo alvo no extremo
	# leste — 12 m de distância no lado oposto. Como a criatura já estava
	# perto do limite de 0.6 m que encerra a patrulha, ela oscilava entre os
	# dois pontos, o que o usuário via como "presa no mesmo eixo com o bico
	# variando entre duas direções". Ancorar no `global_position` faz cada
	# patrulha ser uma perna genuína de caminhada.
	var away := global_position - _home
	away.y = 0.0
	var angle: float
	if away.length() > HOME_LEASH:
		# Longe demais: aponta de volta para casa com folga de ±90° para
		# a direção não ser rígida — a criatura ainda parece explorar, mas
		# no rumo geral do bioma dela.
		var back_angle := atan2(-away.z, -away.x)
		angle = back_angle + _rng.randf_range(-PI * 0.5, PI * 0.5)
	else:
		angle = _rng.randf() * TAU
	var dist := _rng.randf_range(1.5, PATROL_RADIUS)
	_patrol_target = global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _move_towards(target: Vector3, speed: float, delta: float) -> void:
	var dir := target - global_position
	dir.y = 0.0
	var distance := dir.length()
	if distance < 0.05:
		# Chegou. Zerar explicitamente evita o ping-pong do modelo antigo:
		# ele apenas retornava, e a velocidade do quadro anterior seguia
		# aplicada por `move_and_slide`, fazendo a criatura passar reto do
		# alvo, virar 180° no quadro seguinte para voltar, passar reto de
		# novo, e assim por diante — o que o usuário via como "bico
		# alternando entre duas direções sem transição visual".
		velocity.x = 0.0
		velocity.z = 0.0
		return
	dir = dir / distance
	# Cap a velocidade para não estourar o alvo neste quadro. Sem isto, uma
	# criatura correndo (CHASE_SPEED) sempre passa 5–6 cm além do jogador
	# parado, o que reintroduz o mesmo ping-pong só que na perseguição.
	var step_speed: float = minf(speed, distance / maxf(delta, 0.0001))
	velocity.x = dir.x * step_speed
	velocity.z = dir.z * step_speed
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
	set_selected(false)
	_enter_idle()


## Realce visual da criatura selecionada pelo clique. É um toggle simples de
## emissão no material — nada de spawnar node novo por seleção. A cor da
## emissão foi armazenada quando o corpo foi construído.
func set_selected(selected: bool) -> void:
	if _material == null or _selected == selected:
		return
	_selected = selected
	_material.emission_enabled = selected


func is_selected() -> bool:
	return _selected


## Marca a criatura como já engajada e emite o sinal. Chamado pelo WorldRoot
## no segundo clique — mantém o contrato de "só uma batalha por criatura até
## `reset_engagement`".
func request_engage() -> void:
	if _engaged_once:
		return
	_engaged_once = true
	engaged.emit(self)
