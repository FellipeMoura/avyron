class_name PortalGuardianActor
extends InteractableActor

## O guardião que barra o portal de progressão (documento `glifos-e-portais`).
##
## Não é data-driven pelo bestiário — mesmo estágio que `RelicStationActor`
## já está: não existe `npc_role` de guardião ainda, então fica fixo em
## código. Silhueta deliberadamente diferente de ator nenhum já existente —
## corpo em bloco alto (portal/monólito), não cápsula — porque isto não é
## "mais um NPC", é a barreira em si.
##
## `can_pass()` é a checagem de lógica, separada de qualquer texto de
## diálogo — quem chama (`WorldRoot`) decide a mensagem, mas a decisão de
## deixar passar mora aqui, não na UI.

const HEIGHT := 2.6
const WIDTH := 0.7
const DEPTH := 0.5

const COL_BODY := Color("#3A4652")
const COL_SIGN := Color("#8FB8D6")

## Código do Glifo exigido (`"DALETH"`) e nome de exibição do destino
## (`"Titanor"`) — só para a mensagem; a checagem em si é por código.
var required_glyph := ""
var destination_label := ""

## Injetado por `WorldRoot`, que já resolveu o autoload — o mesmo motivo de
## `_db` nunca ser buscado pelo identificador global bare em nenhum ator
## deste mundo. `null` só em playtest de cena solta.
var _progress: PlayerProgress


static func create(at: Vector3, glyph: String, destination: String, progress: PlayerProgress) -> PortalGuardianActor:
	var a := PortalGuardianActor.new()
	a.required_glyph = glyph
	a.destination_label = destination
	a._progress = progress
	# Sem nome de catálogo, como o posto: o substantivo é o `display_name`.
	a.display_name = "O guardiao"
	a.position = at
	return a


func _ready() -> void:
	body_height = HEIGHT

	var mesh := BoxMesh.new()
	mesh.size = Vector3(WIDTH, HEIGHT, DEPTH)

	var material := StandardMaterial3D.new()
	material.albedo_color = COL_BODY
	material.roughness = 0.7
	mesh.material = material

	var body := MeshInstance3D.new()
	body.name = "Mesh"
	body.mesh = mesh
	add_child(body)

	# Prisma: "ward" do portal, silhueta que não repete cápsula
	# (criatura/comerciante/arena) nem torus (posto do Relicário).
	var sign_mesh := PrismMesh.new()
	sign_mesh.size = Vector3(0.22, 0.30, 0.22)
	attach_sign(sign_mesh, COL_SIGN, 0.6)

	var shape := BoxShape3D.new()
	shape.size = Vector3(WIDTH, HEIGHT, DEPTH)
	attach_collision(shape)

	ground_on_spot()


## A checagem de lógica em si — separada de qualquer diálogo/UI.
func can_pass() -> bool:
	return required_glyph != "" and _progress != null and _progress.has_glyph(required_glyph)
