class_name MerchantActor
extends StaticBody3D

## Um comerciante parado no mapa.
##
## `StaticBody3D` e não `Node3D` porque o clique do mundo é um raycast físico:
## sem corpo de colisão ele seria invisível ao mouse. E estático e não
## `CharacterBody3D` porque ele não anda, não é empurrado e não persegue —
## quem tem máquina de estados é criatura selvagem.
##
## A silhueta é deliberadamente diferente da de uma criatura: mais alta, mais
## estreita, e com a placa flutuando acima. Num mapa isométrico cheio de
## cápsulas coloridas por elemento, "isso aqui não é bicho" precisa ser
## legível de longe — a mesma exigência que o documento de arte faz das
## criaturas, aplicada a quem não é uma.

signal engaged(actor: MerchantActor)

const HEIGHT := 1.75
const RADIUS := 0.30

const COL_BODY := Color("#5A6472")
const COL_SIGN := Color("#C6552F")

## Distância a partir da qual o clique não engaja mais. Um comerciante do
## outro lado do mapa não deve abrir loja porque o raycast alcançou.
const INTERACT_RANGE := 4.5

var merchant_code := ""
var display_name := ""

var _sign: MeshInstance3D
var _time := 0.0


static func create(data: Dictionary, at: Vector3) -> MerchantActor:
	var a := MerchantActor.new()
	a.merchant_code = str(data.get("code", ""))
	a.display_name = str(data.get("name", a.merchant_code))
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

	# A placa: cubo âmbar flutuando acima da cabeça, com bob lento. É o que
	# diz "dá para interagir" sem precisar de ícone de HUD.
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(0.28, 0.28, 0.06)
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
	# elevada) e o corpo sobe meia cápsula a partir dali.
	position.y += HEIGHT * 0.5


func _process(delta: float) -> void:
	if _sign == null:
		return
	_time += delta
	_sign.position.y = HEIGHT * 0.5 + 0.45 + sin(_time * TAU * 0.5) * 0.06
	_sign.rotation.y = _time * 0.8


## Distância no plano até um ponto. O clique do mundo usa isto para recusar
## interação a distância.
func flat_distance_to(point: Vector3) -> float:
	var d := global_position - point
	d.y = 0.0
	return d.length()


func request_engage() -> void:
	engaged.emit(self)
