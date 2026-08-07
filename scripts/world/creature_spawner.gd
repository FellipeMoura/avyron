class_name CreatureSpawner
extends Node3D

## Povoa o mapa com as criaturas do bioma.
##
## Lê o bundle — nada de lista de criaturas escrita em cena. Acrescentar uma
## espécie ao PZ-01 no bestiário e re-exportar já a coloca no mundo, sem tocar
## em código nem em cena. É o mesmo contrato que vale para stats e golpes.

## Mapa a povoar. Quando houver mais de um, vira parâmetro da cena.
@export var map_code := "PZ-01"
@export var creature_count := 8
@export var spawn_radius := 22.0
@export var min_separation := 4.0
@export var level := 10

## Semente fixa por padrão: um mapa que muda de disposição a cada play
## atrapalha comparar duas execuções durante o playtest.
@export var spawn_seed := 20260807

signal creature_engaged(actor: CreatureActor)

var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _actors: Array[CreatureActor] = []


func _ready() -> void:
	_rng.seed = spawn_seed
	_player = get_parent().get_node_or_null("Player")
	if _player == null:
		push_error("CreatureSpawner: nenhum nó Player irmão encontrado")
		return
	populate()


func populate() -> void:
	var db := get_node_or_null("/root/Bestiary") as BestiaryData
	if db == null:
		push_error("CreatureSpawner: autoload Bestiary indisponivel")
		return

	var pool := db.creatures_in_map(map_code)
	if pool.is_empty():
		push_warning("CreatureSpawner: nenhuma criatura no mapa %s" % map_code)
		return

	var placed: Array[Vector3] = []
	for i in creature_count:
		var data: Dictionary = pool[_rng.randi() % pool.size()]
		var spot := _find_spot(placed)
		if spot == Vector3.INF:
			break
		placed.append(spot)

		var actor := CreatureActor.create(data, spot, _player, spawn_seed + i)
		actor.name = "%s_%d" % [str(data["code"]), i]
		actor.engaged.connect(_on_engaged)
		add_child(actor)
		_actors.append(actor)


## Procura um ponto livre. Sem a separação mínima, duas criaturas nascem
## sobrepostas e a física as arremessa no primeiro quadro.
func _find_spot(placed: Array[Vector3]) -> Vector3:
	for _attempt in 30:
		var angle := _rng.randf() * TAU
		var dist := sqrt(_rng.randf()) * spawn_radius
		var candidate := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		# Longe do ponto de partida do jogador, para ele não abrir o jogo
		# já dentro de um encontro.
		if candidate.length() < 6.0:
			continue
		var ok := true
		for p in placed:
			if candidate.distance_to(p) < min_separation:
				ok = false
				break
		if ok:
			return candidate
	return Vector3.INF


func _on_engaged(actor: CreatureActor) -> void:
	creature_engaged.emit(actor)


func actors() -> Array[CreatureActor]:
	return _actors
