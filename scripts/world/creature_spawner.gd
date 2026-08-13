class_name CreatureSpawner
extends Node3D

## Povoa o mapa com as criaturas do bioma e mantém a população ao longo do
## tempo.
##
## Lê o bundle — nada de lista de criaturas escrita em cena. Acrescentar uma
## espécie ao PZ-01 no bestiário e re-exportar já a coloca no mundo, sem tocar
## em código nem em cena. É o mesmo contrato que vale para stats e golpes.
##
## Ciclo de vida da criatura selvagem:
##   `_spawn_one`  → escolhe do pool do mapa, sorteia posição, adiciona actor.
##   `remove_actor`→ tira do mapa (via `queue_free`) e agenda respawn.
##   `_process`    → conta timers e chama `_spawn_one` quando algum expira.

## Mapa a povoar. Quando houver mais de um, vira parâmetro da cena.
@export var map_code := "PZ-01"
@export var creature_count := 8
@export var spawn_radius := 22.0
@export var min_separation := 4.0
@export var level := 10

## Janela de respawn. Uma criatura derrotada volta em algum ponto entre estes
## dois valores. Curto o bastante para o mapa não esvaziar durante uma sessão
## de playtest, longo o bastante para vitória ainda ter peso.
@export var respawn_min_sec: float = 20.0
@export var respawn_max_sec: float = 40.0

## Semente fixa por padrão: um mapa que muda de disposição a cada play
## atrapalha comparar duas execuções durante o playtest.
@export var spawn_seed := 20260807

signal creature_engaged(actor: CreatureActor)
## Emitido quando o povoamento muda (spawn ou remoção). O WorldRoot escuta
## para atualizar o hint com a contagem corrente.
signal population_changed()

var _rng := RandomNumberGenerator.new()
var _actors: Array[CreatureActor] = []
var _pool: Array = []
var _respawn_timers: Array[float] = []
## Contador incremental usado como sufixo de nome e semente por actor. Não
## reciclado ao remover — evita colisão de nome se dois actors do mesmo
## `creature_code` coexistirem em janelas de respawn próximas.
var _seed_counter := 0


func _ready() -> void:
	_rng.seed = spawn_seed
	populate()


func populate() -> void:
	var db := get_node_or_null("/root/Bestiary") as BestiaryData
	if db == null:
		push_error("CreatureSpawner: autoload Bestiary indisponivel")
		return

	_pool = db.creatures_in_map(map_code)
	if _pool.is_empty():
		push_warning("CreatureSpawner: nenhuma criatura no mapa %s" % map_code)
		return

	for _i in creature_count:
		if not _spawn_one():
			break


## Spawna uma criatura no mapa, escolhendo do pool. Devolve false se não
## conseguiu achar espaço (todas as tentativas de `_find_spot` falharam).
func _spawn_one() -> bool:
	if _pool.is_empty():
		return false
	var data: Dictionary = _pool[_rng.randi() % _pool.size()]
	var spot := _find_spot(_current_positions())
	if spot == Vector3.INF:
		return false

	var actor := CreatureActor.create(data, spot, spawn_seed + _seed_counter)
	_seed_counter += 1
	actor.name = "%s_%d" % [str(data["code"]), _seed_counter]
	actor.engaged.connect(_on_engaged)
	add_child(actor)
	_actors.append(actor)
	population_changed.emit()
	return true


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


func _current_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for a in _actors:
		if is_instance_valid(a):
			out.append(a.global_position)
	return out


## Remove definitivamente uma criatura do mapa e, se `respawn` for true,
## agenda um novo slot na fila. Vitória agenda respawn; captura não — a
## criatura vai para o time e não volta ao bioma.
func remove_actor(actor: CreatureActor, respawn: bool = true) -> void:
	if actor == null:
		return
	_actors.erase(actor)
	if is_instance_valid(actor):
		actor.queue_free()
	if respawn:
		_respawn_timers.append(_rng.randf_range(respawn_min_sec, respawn_max_sec))
	population_changed.emit()


func _process(delta: float) -> void:
	if _respawn_timers.is_empty():
		return
	# Duas passadas para não mutar o array enquanto itera. Contagem primeiro,
	# reconstrução do array pendente segundo, spawns por último.
	var expired := 0
	var still: Array[float] = []
	for t in _respawn_timers:
		var new_t := t - delta
		if new_t <= 0.0:
			expired += 1
		else:
			still.append(new_t)
	_respawn_timers = still
	for _i in expired:
		if not _spawn_one():
			# Sem espaço: recoloca o timer curto para tentar de novo. Mapa
			# cheio é raro, mas se acontecer não queremos perder o slot.
			_respawn_timers.append(_rng.randf_range(2.0, 5.0))


func _on_engaged(actor: CreatureActor) -> void:
	creature_engaged.emit(actor)


func actors() -> Array[CreatureActor]:
	return _actors


## Quantos slots de respawn estão em espera. Útil pro teste — não faz parte
## do contrato de gameplay.
func pending_respawns() -> int:
	return _respawn_timers.size()
