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

## Barraca do comerciante — a estrutura é cenário; a pessoa, montada da
## receita do bundle por `attach_npc`, fica diante dela (ver o comentário de
## `InteractableActor.attach_npc`: de 2026-09-18 a 20 a barraca substituía o
## humano, e a receita do catálogo tinha virado código morto).
const MODEL_PATH := "res://models/village/comerciante.glb"
## Aumento de 200% pedido pelo usuário em 2026-09-18 — o modelo lia pequeno
## demais perto do jogador na primeira integração.
const MODEL_SCALE := 3.0
## Lado da porta em que o comerciante fica e a pose dele: braços cruzados,
## esperando freguês. No arquivo da UAL2 o clipe chama `Idle_FoldArms_Loop`;
## o importador glTF do Godot corta o sufixo `_Loop` (é a convenção dele para
## marcar loop), e na biblioteca fundida ele vive como `Idle_FoldArms` — ver
## `GaitRig.LOOPED_CLIPS`.
const NPC_SIDE := 1.0
const NPC_CLIP := "Idle_FoldArms"

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

	var model := _load_model(MODEL_PATH, MODEL_SCALE)
	if model != null:
		add_child(model)
	# A pessoa entra com ou sem estrutura: sem o `.glb` ela É o comerciante,
	# de pé no centro do ator (footprint zero → offset zero), como antes de
	# 2026-09-18. Sem kit nem receita, sobra a cápsula.
	var rig := attach_npc(appearance, NPC_SIDE, NPC_CLIP)
	if model == null and rig == null:
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
	attach_npc_collision(rig)

	ground_on_spot()
