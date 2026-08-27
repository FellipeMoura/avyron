class_name WorldSelection
extends RefCounted

## Seleção de criatura por clique: raycast contra o mundo, destaque visual no
## ator, painel de identificação, e auto-desseleção quando o jogador se
## afasta demais.
##
## `RefCounted`, sem nó próprio — os únicos efeitos colaterais são em nós que
## já existem (`CreatureActor.set_selected`, `CreatureInfoPanel`); nunca cria
## nó novo. `WorldRoot._process` chama `update()` a cada quadro para a
## checagem de distância; todo o resto é reativo a clique.
##
## Extraído de `WorldRoot` porque misturava três coisas que crescem por
## motivos diferentes: o que o raycast pode acertar (criatura, comerciante,
## posto, arena, guardião — cresce a cada NPC novo), a seleção em si (só
## criatura), e a decisão do que fazer com cada tipo de acerto (que continua
## em `WorldRoot.handle_click_at`, porque é ela quem sabe abrir loja vs.
## engatar duelo vs. falar com o guardião).

## Distância a partir da qual a seleção cai sozinha. Um pouco além do raio de
## detecção da criatura (6 m) — o jogador se afastou o bastante para o alvo
## não ser mais o assunto imediato.
const DESELECT_DISTANCE := 15.0

## Alcance máximo do raycast do clique. 60 m cobre folgadamente qualquer
## coisa visível dentro do enquadramento ortográfico de 12 unidades.
const CLICK_RAY_LENGTH := 60.0

var _parent: Node3D
var _camera: IsoCamera
var _player: Node3D
var _info: CreatureInfoPanel
var _db: BestiaryData
var _encounter_level: int

var _selected: CreatureActor


func setup(
	parent: Node3D, camera: IsoCamera, player: Node3D, info: CreatureInfoPanel,
	db: BestiaryData, encounter_level: int
) -> void:
	_parent = parent
	_camera = camera
	_player = player
	_info = info
	_db = db
	_encounter_level = encounter_level


func selected_actor() -> CreatureActor:
	return _selected


## Solta a seleção quando o jogador vagou para longe. Chamado do `_process`
## de `WorldRoot`. Sem isto, um alvo esquecido do outro lado do mapa continua
## brilhando e o painel fica poluindo a HUD.
func update() -> void:
	if _selected == null:
		return
	if not is_instance_valid(_selected):
		clear()
		return
	if _player and _selected.global_position.distance_to(_player.global_position) > DESELECT_DISTANCE:
		clear()


## Devolve o corpo clicado — criatura, comerciante, posto do relicário, arena
## ou guardião do portal — ou `null`. Quem decide o que fazer com o resultado
## é `WorldRoot.handle_click_at`.
func pick_body(screen_pos: Vector2) -> Node3D:
	if _camera == null:
		return null
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * CLICK_RAY_LENGTH
	var space := _parent.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	# Ignora o próprio jogador — clicar em cima dele com uma criatura atrás
	# não deve "roubar" o clique da criatura.
	if _player and _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	# Duas famílias, não a lista das classes concretas: `InteractableActor`
	# cobre loja, posto, arena e guardião, e ator novo entra sem tocar aqui.
	# Esta lista já foi a segunda cópia do despacho do `WorldRoot`, e esquecer
	# de atualizá-la fazia o raycast devolver null — clique que não faz nada,
	# sem erro.
	if collider is CreatureActor or collider is InteractableActor:
		return collider as Node3D
	return null


func select(actor: CreatureActor) -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = actor
	_selected.set_selected(true)
	if _info and _db:
		_info.show_for(_db, actor.creature_code, _encounter_level, actor.size_meters)


func clear() -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = null
	if _info:
		_info.clear()
