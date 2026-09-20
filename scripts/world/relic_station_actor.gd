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

## O posto, como estrutura — cenário; a pessoa fica diante dele (ver
## `InteractableActor.attach_npc`).
const MODEL_PATH := "res://models/village/posto.glb"
## Aumento de 200% pedido pelo usuário em 2026-09-18 — mesmo motivo do
## comerciante (`merchant_actor.gd`).
const MODEL_SCALE := 3.0

## A guardiã do posto. Receita FIXA aqui, e não no bestiário, porque o posto
## não é NPC de catálogo — é ponto de código, sem `npc_role` (ver o cabeçalho).
## Apresentação, como `PlayerController.PLAYER_RECIPE`: no dia em que o posto
## virar NPC de verdade, a receita migra para `npc_appearances` e este
## dicionário some. Camponesa de cabelo comprido, sem capuz: a primeira
## versão (ranger encapuzada) era, na captura de 2026-09-20, indistinguível
## do jogador parado a 2,5 m dela — mesmo capuz verde, mesma silhueta. A
## duelista (coques + ombreiras) e o comerciante (barbudo) já são outros.
## `Cast_Idle`: mãos em concha, de quem cuida de relíquias.
const NPC_RECIPE := {
	"gender": "female",
	"hair": "Hair_Long",
	"eyebrows": "Eyebrows_Female",
	"body": "Female_Peasant_Body",
	"arms": "Female_Peasant_Arms",
	"legs": "Female_Peasant_Legs",
	"feet": "Female_Peasant_Feet",
}
const NPC_SIDE := -1.0
const NPC_CLIP := "Cast_Idle"


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

	var model := _load_model(MODEL_PATH, MODEL_SCALE)
	if model != null:
		add_child(model)
	var rig := attach_npc(NPC_RECIPE, NPC_SIDE, NPC_CLIP)
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
	attach_npc_collision(rig)

	ground_on_spot()
