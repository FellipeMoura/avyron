class_name MerchantActor
extends InteractableActor

## Um comerciante parado no mapa.
##
## A silhueta é deliberadamente diferente da de uma criatura: mais alta, mais
## estreita, e com a placa flutuando acima. Num mapa isométrico cheio de
## cápsulas coloridas por elemento, "isso aqui não é bicho" precisa ser
## legível de longe — a mesma exigência que o documento de arte faz das
## criaturas, aplicada a quem não é uma.
##
## Físico, alcance de interação, placa e apoio no chão vêm de
## `InteractableActor`.

const HEIGHT := 1.75
const RADIUS := 0.30

const COL_BODY := Color("#5A6472")
const COL_SIGN := Color("#C6552F")

var merchant_code := ""

## Receita de aparência vinda do bundle (`merchants[].appearance`). Vazia =
## catálogo ainda não vestiu este NPC, e a cápsula segue como fallback.
var appearance: Dictionary = {}


static func create(data: Dictionary, at: Vector3) -> MerchantActor:
	var a := MerchantActor.new()
	a.merchant_code = str(data.get("code", ""))
	a.display_name = str(data.get("name", a.merchant_code))
	var recipe: Variant = data.get("appearance")
	if recipe is Dictionary:
		a.appearance = recipe
	a.position = at
	return a


func _ready() -> void:
	body_height = HEIGHT

	var rig := CharacterRig.create(appearance)
	if rig != null:
		# Pés na base da cápsula de colisão — a origem do ator é o centro dela
		# (ver `ground_on_spot()` no fim).
		rig.position.y = -HEIGHT * 0.5
		add_child(rig)
	else:
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

	# Cubo âmbar: "aqui se negocia".
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(0.28, 0.28, 0.06)
	attach_sign(sign_mesh, COL_SIGN)

	var shape := CapsuleShape3D.new()
	shape.height = HEIGHT
	shape.radius = RADIUS
	attach_collision(shape)

	ground_on_spot()
