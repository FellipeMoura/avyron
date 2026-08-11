class_name ArenaActor
extends StaticBody3D

## Um duelista de arena parado no mapa (documento `glifos-e-portais`).
##
## Clona a forma de `MerchantActor` — `StaticBody3D` pelo mesmo motivo (o
## clique do mundo é raycast físico) — mas a placa vem em tom ember/vermelho
## em vez de âmbar: "isto é desafio", não "isto é loja". Mesma exigência de
## legibilidade por silhueta que criatura e comerciante já cumprem.
##
## Identidade (`code`/`name`) e mapa vêm do bestiário via `role = duelist`
## (`BestiaryData.duelists_in_map`). Contra quem o duelista luta e qual Glifo
## ele concede **não** vêm do bundle — são decisão de conteúdo do jogo, no
## mesmo nível que `WorldRoot.starter_code`/`encounter_level` já são, porque
## o catálogo não tem coluna para "oponente de arena" e não precisa: são só
## dois duelistas nesta era, ligados um a um a um Glifo fixo.

signal engaged(actor: ArenaActor)

const HEIGHT := 1.9
const RADIUS := 0.32

const COL_BODY := Color("#4A3038")
const COL_SIGN := Color("#C6402F")

## Mesmo raciocínio de `MerchantActor.INTERACT_RANGE`.
const INTERACT_RANGE := 4.5

var duelist_code := ""
var display_name := ""

## Quem o jogador enfrenta e em que nível — o "conteúdo" desta arena.
var opponent_code := ""
var opponent_level := 1

## Código do Glifo concedido numa vitória (`"DALETH"`, sem o prefixo
## "Glifo" — esse é só de exibição, ver `PlayerProgress`).
var grants_glyph := ""

var _sign: MeshInstance3D
var _time := 0.0


static func create(data: Dictionary, at: Vector3, opponent: String, level: int, glyph: String) -> ArenaActor:
	var a := ArenaActor.new()
	a.duelist_code = str(data.get("code", ""))
	a.display_name = str(data.get("name", a.duelist_code))
	a.opponent_code = opponent
	a.opponent_level = level
	a.grants_glyph = glyph
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

	# A placa em vermelho-ember: mesma linguagem de "dá para interagir" que a
	# placa âmbar do comerciante já estabelece, cor diferente para não ler
	# como loja à distância.
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(0.28, 0.28, 0.06)
	var sign_material := StandardMaterial3D.new()
	sign_material.albedo_color = COL_SIGN
	sign_material.emission_enabled = true
	sign_material.emission = COL_SIGN
	sign_material.emission_energy_multiplier = 0.6
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

	position.y = HEIGHT * 0.5


func _process(delta: float) -> void:
	if _sign == null:
		return
	_time += delta
	_sign.position.y = HEIGHT * 0.5 + 0.45 + sin(_time * TAU * 0.5) * 0.06
	_sign.rotation.y = _time * 0.8


## Distância no plano até um ponto. Mesmo padrão de `MerchantActor`.
func flat_distance_to(point: Vector3) -> float:
	var d := global_position - point
	d.y = 0.0
	return d.length()


func request_engage() -> void:
	engaged.emit(self)
