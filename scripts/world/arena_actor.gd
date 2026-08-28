class_name ArenaActor
extends InteractableActor

## Um duelista de arena parado no mapa (documento `glifos-e-portais`).
##
## Mesma forma do comerciante, placa em ember/vermelho em vez de âmbar: "isto
## é desafio", não "isto é loja". Mesma exigência de legibilidade por silhueta
## que criatura e comerciante já cumprem.
##
## Tudo vem do bestiário via `role = duelist` (`BestiaryData.duelists_in_map`):
## identidade, mapa e — desde 2026-08 — o duelo em si, no bloco
## `duelists[].duel` (tabela `npc_duelists`). Antes disso o oponente, o nível
## e o Glifo eram constantes no `WorldPopulator`, com a justificativa de que
## uma arena só não valia uma tabela; o modelo de uma arena por mapa derrubou
## a justificativa, e o nível nunca deveria ter estado em código de qualquer
## forma (regra 1).
##
## `grants_glyph` vazio é estado NORMAL, não dado faltando: só a arena do
## último mapa de uma era concede Glifo — as intermediárias são duelo com
## recompensa própria. `PlayerProgress.grant_glyph("")` já devolve `false`,
## então nada precisa ser checado aqui.

const HEIGHT := 1.9
const RADIUS := 0.32

const COL_BODY := Color("#4A3038")
const COL_SIGN := Color("#C6402F")

var duelist_code := ""

## Quem o jogador enfrenta e em que nível — o "conteúdo" desta arena.
var opponent_code := ""
var opponent_level := 1

## Código do Glifo concedido numa vitória (`"DALETH"`, sem o prefixo
## "Glifo" — esse é só de exibição, ver `PlayerProgress`).
var grants_glyph := ""

## Receita de aparência vinda do bundle (`duelists[].appearance`). Vazia =
## catálogo ainda não vestiu este NPC, e a cápsula segue como fallback —
## mesmo contrato do `MerchantActor`.
var appearance: Dictionary = {}


static func create(data: Dictionary, at: Vector3, opponent: String, level: int, glyph: String) -> ArenaActor:
	var a := ArenaActor.new()
	a.duelist_code = str(data.get("code", ""))
	a.display_name = str(data.get("name", a.duelist_code))
	a.opponent_code = opponent
	a.opponent_level = level
	a.grants_glyph = glyph
	var recipe: Variant = data.get("appearance")
	if recipe is Dictionary:
		a.appearance = recipe
	a.position = at
	return a


func _ready() -> void:
	body_height = HEIGHT

	var rig := CharacterRig.create(appearance)
	if rig != null:
		# Pés na base da cápsula de colisão — a origem do ator é o centro dela.
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

	# Vermelho-ember: mesma linguagem de "dá para interagir" que a placa âmbar
	# do comerciante estabelece, cor diferente para não ler como loja de longe.
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(0.28, 0.28, 0.06)
	attach_sign(sign_mesh, COL_SIGN, 0.6)

	var shape := CapsuleShape3D.new()
	shape.height = HEIGHT
	shape.radius = RADIUS
	attach_collision(shape)

	ground_on_spot()
