class_name CraftingBenchActor
extends InteractableActor

## A bancada — onde minério vira equipamento (documento `equipamentos`).
##
## É a **única** fonte de Amplificador e Encantador no jogo. Isso é escolha,
## não limitação de escopo: enquanto a aquisição for um lugar só, a posse tem
## um dono só (`PlayerLoadout.acquire`), e não se repete aqui o furo que o
## posto do Relicário tem — lá dá para vestir qualquer modelo do catálogo sem
## nunca o ter conquistado.
##
## Mesma família do posto e do comerciante: ponto fixo em código, sem entrada
## no bestiário. Não existe `npc_role` para "bancada", e inventar um agora
## seria cadastrar uma coluna antes do consumidor — o comerciante só virou
## dado quando havia dois comerciantes a descrever.
##
## A silhueta é um **prisma baixo e largo**: nem cápsula (comerciante, posto),
## nem bloco alto (guardião). De longe tem de ler como mesa, não como pessoa,
## porque o gesto que ela oferece não é conversa.

const HEIGHT := 0.95
const WIDTH := 1.3
const DEPTH := 0.8

const COL_BODY := Color("#6B5A3E")
const COL_SIGN := Color("#C6552F")

## A bancada como estrutura de ferraria — cenário; o ferreiro fica diante
## dela (ver `InteractableActor.attach_npc`).
const MODEL_PATH := "res://models/village/ferreiro.glb"
## Aumento de 200% pedido pelo usuário em 2026-09-18 — mesmo motivo do
## comerciante (`merchant_actor.gd`).
const MODEL_SCALE := 3.0

## O ferreiro. Receita FIXA pelo mesmo motivo do posto (ver
## `RelicStationActor.NPC_RECIPE`): a bancada não é NPC de catálogo. Camponês
## de cabelo raspado e sem barba — o comerciante do bundle é o barbudo de
## cabelo repartido. `Fixing_Kneeling`: ajoelhado consertando, laço de
## trabalho da UAL1 (ver `GaitRig.LOOPED_CLIPS`).
const NPC_RECIPE := {
	"gender": "male",
	"hair": "Hair_Buzzed",
	"eyebrows": "Eyebrows_Regular",
	"body": "Male_Peasant_Body",
	"arms": "Male_Peasant_Arms",
	"legs": "Male_Peasant_Legs",
	"feet": "Male_Peasant_Feet",
}
const NPC_SIDE := 1.0
const NPC_CLIP := "Fixing_Kneeling"


static func create(at: Vector3) -> CraftingBenchActor:
	var a := CraftingBenchActor.new()
	# Sem nome no catálogo, como o posto: o substantivo É o nome, e é ele que
	# as mensagens do mundo interpolam.
	a.display_name = "A bancada"
	a.position = at
	return a


func _ready() -> void:
	body_height = HEIGHT

	var model := _load_model(MODEL_PATH, MODEL_SCALE)
	if model != null:
		add_child(model)
	var rig := attach_npc(NPC_RECIPE, NPC_SIDE, NPC_CLIP)
	if model == null and rig == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(WIDTH, HEIGHT, DEPTH)

		var material := StandardMaterial3D.new()
		material.albedo_color = COL_BODY
		material.roughness = 0.9
		mesh.material = material

		var body := MeshInstance3D.new()
		body.name = "Mesh"
		body.mesh = mesh
		add_child(body)

	# Placa em prisma, na cor ember que a HUD já usa para custo e desperdício —
	# a bancada é o lugar onde se gasta.
	var sign_mesh := PrismMesh.new()
	sign_mesh.size = Vector3(0.28, 0.28, 0.28)
	attach_sign(sign_mesh, COL_SIGN)

	var shape := BoxShape3D.new()
	shape.size = Vector3(WIDTH, HEIGHT, DEPTH)
	attach_collision(shape)
	attach_npc_collision(rig)

	ground_on_spot()
