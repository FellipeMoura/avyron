class_name RelicStationActor
extends StaticBody3D

## O posto do Relicário no mapa — onde depositar/retirar do storage e trocar
## de modelo (documento `relicario`: "exige estar em um ponto fixo, tipo
## Centro/PC"). Mesmo padrão físico de `MerchantActor` (corpo estático,
## clique por raycast), silhueta diferente pra não confundir os dois.
##
## Não é data-driven pelo bestiário como o comerciante — não existe `npc_role`
## pra isso ainda, então a posição é fixa em código, o mesmo estágio em que o
## comerciante também esteve antes de existir NPC.

signal engaged(actor: RelicStationActor)

const HEIGHT := 1.9
const RADIUS := 0.32

const COL_BODY := Color("#4A5A7A")
const COL_SIGN := Color("#7A8C6B")

## Mesmo raciocínio de `MerchantActor.INTERACT_RANGE`.
const INTERACT_RANGE := 4.5

var _sign: MeshInstance3D
var _time := 0.0


static func create(at: Vector3) -> RelicStationActor:
	var a := RelicStationActor.new()
	a.position = at
	return a


func _ready() -> void:
	var mesh := CapsuleMesh.new()
	mesh.height = HEIGHT
	mesh.radius = RADIUS

	var material := StandardMaterial3D.new()
	material.albedo_color = COL_BODY
	material.roughness = 0.85
	mesh.material = material

	var body := MeshInstance3D.new()
	body.name = "Mesh"
	body.mesh = mesh
	add_child(body)

	# Placa em anel (torus) em vez do cubo do comerciante — mesma linguagem de
	# "dá pra interagir", silhueta diferente o bastante pra distinguir de longe.
	var sign_mesh := TorusMesh.new()
	sign_mesh.inner_radius = 0.10
	sign_mesh.outer_radius = 0.18
	var sign_material := StandardMaterial3D.new()
	sign_material.albedo_color = COL_SIGN
	sign_material.emission_enabled = true
	sign_material.emission = COL_SIGN
	sign_material.emission_energy_multiplier = 0.5
	sign_mesh.material = sign_material

	_sign = MeshInstance3D.new()
	_sign.name = "Sign"
	_sign.mesh = sign_mesh
	_sign.position.y = HEIGHT * 0.5 + 0.45
	add_child(_sign)

	var shape := CapsuleShape3D.new()
	shape.height = HEIGHT
	shape.radius = RADIUS
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	add_child(collision)

	# Soma, não atribuição: o spot chega já na altura do terreno (a costa é
	# elevada) e o corpo sobe meia altura a partir dali.
	position.y += HEIGHT * 0.5


func _process(delta: float) -> void:
	if _sign == null:
		return
	_time += delta
	_sign.position.y = HEIGHT * 0.5 + 0.45 + sin(_time * TAU * 0.5) * 0.06
	_sign.rotation.x = _time * 0.8


func flat_distance_to(point: Vector3) -> float:
	var d := global_position - point
	d.y = 0.0
	return d.length()


func request_engage() -> void:
	engaged.emit(self)
