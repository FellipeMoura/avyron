class_name RelicStationActor
extends InteractableActor

## O posto do Relicário no mapa — onde depositar/retirar do storage e trocar
## de modelo (documento `relicario`: "exige estar em um ponto fixo, tipo
## Centro/PC").
##
## Não é data-driven pelo bestiário como o comerciante — não existe `npc_role`
## pra isso ainda, então a posição é fixa em código, o mesmo estágio em que o
## comerciante também esteve antes de existir NPC.

const HEIGHT := 1.9
const RADIUS := 0.32

const COL_BODY := Color("#4A5A7A")
const COL_SIGN := Color("#7A8C6B")


static func create(at: Vector3) -> RelicStationActor:
	var a := RelicStationActor.new()
	# Não é NPC e não tem nome no catálogo: o próprio substantivo serve de
	# `display_name`, que é o que as mensagens do mundo interpolam.
	a.display_name = "O posto do relicario"
	a.position = at
	return a


func _ready() -> void:
	body_height = HEIGHT
	# O torus gira mostrando o furo, não sobre si mesmo como as placas chapadas.
	sign_spin_axis = Vector3.RIGHT

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

	# Anel em vez do cubo do comerciante — mesma linguagem de "dá pra
	# interagir", silhueta distinguível de longe.
	var sign_mesh := TorusMesh.new()
	sign_mesh.inner_radius = 0.10
	sign_mesh.outer_radius = 0.18
	attach_sign(sign_mesh, COL_SIGN)

	var shape := CapsuleShape3D.new()
	shape.height = HEIGHT
	shape.radius = RADIUS
	attach_collision(shape)

	ground_on_spot()
