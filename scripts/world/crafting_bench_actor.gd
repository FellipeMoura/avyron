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


static func create(at: Vector3) -> CraftingBenchActor:
	var a := CraftingBenchActor.new()
	# Sem nome no catálogo, como o posto: o substantivo É o nome, e é ele que
	# as mensagens do mundo interpolam.
	a.display_name = "A bancada"
	a.position = at
	return a


func _ready() -> void:
	body_height = HEIGHT

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

	ground_on_spot()
