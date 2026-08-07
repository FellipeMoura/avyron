class_name WorldRoot
extends Node3D

## Raiz do mapa de exploração e árbitro do encontro.
##
## A batalha acontece **no mesmo espaço**, sem corte para outra cena: a tela
## de combate entra como overlay, a câmera dá o zoom de aproximação e o mundo
## congela atrás. É o que `escala-e-camera-de-batalha` especifica, e é por
## isso que a troca de cena que existia aqui antes saiu.
##
## Fluxo de encontro por clique:
##   1º clique numa criatura → seleciona (destaque no material) + painel de
##     identificação aparece.
##   2º clique na mesma criatura → dispara `request_engage` no actor, que
##     emite `engaged` e vira em combate.
##   clique numa criatura diferente → troca a seleção (equivale ao 1º clique
##     dela).
##   clique fora ou Esc → limpa seleção.
##   afastar mais de `DESELECT_DISTANCE` da selecionada → auto-desseleciona,
##     porque uma seleção "esquecida" atrás de você é ruído visual.
##
## Contato físico com a criatura não faz mais nada: a decisão de entrar em
## combate é sempre do jogador. Criaturas agressivas continuam perseguindo,
## por pressão visual, mas quem aperta o gatilho é o mouse.

const DUEL_SCENE := "res://scenes/duel.tscn"

## Alcance máximo do raycast do clique. 60 m cobre folgadamente qualquer
## coisa visível dentro do enquadramento ortográfico de 12 unidades.
const CLICK_RAY_LENGTH := 60.0

## Distância a partir da qual a seleção cai sozinha. Um pouco além do raio de
## detecção da criatura (6 m) — o jogador se afastou o bastante para o alvo
## não ser mais o assunto imediato.
const DESELECT_DISTANCE := 15.0

## Criatura do jogador enquanto não existe time montado por captura.
@export var starter_code := "CRT-002"
@export var encounter_level := 10

var _camera: IsoCamera
var _player: Node3D
var _spawner: CreatureSpawner
var _duel: DuelScreen
var _engaged_actor: CreatureActor
var _selected: CreatureActor
var _info: CreatureInfoPanel
var _hint: Label
var _db: BestiaryData
var _companion: CompanionActor
var _team: Array[String] = []
var _team_panel: PlayerTeamPanel
var _inventory: PlayerInventory
var _inventory_panel: InventoryPanel
var _mine_rng := RandomNumberGenerator.new()
var _mine_cooldown := 0.0
var _mine_label: Label

## Segundos entre minerações consecutivas.
const MINE_COOLDOWN_SEC := 3.0


func _ready() -> void:
	_camera = get_node_or_null("IsoCamera") as IsoCamera
	_player = get_node_or_null("Player")
	_db = get_node_or_null("/root/Bestiary") as BestiaryData

	# A câmera continua processando durante a pausa. Um Tween acompanha o
	# estado de pausa do nó a que está preso, então sem isto o zoom de entrada
	# em combate simplesmente não animaria — ficaria travado no valor inicial.
	if _camera:
		_camera.process_mode = Node.PROCESS_MODE_ALWAYS

	_inventory = PlayerInventory.new()
	_mine_rng.randomize()

	_spawner = CreatureSpawner.new()
	_spawner.name = "CreatureSpawner"
	_spawner.level = encounter_level
	add_child(_spawner)
	_spawner.creature_engaged.connect(_on_creature_engaged)
	# Mantém o hint em sincronia sem precisar polling: qualquer mudança de
	# população (spawn inicial, remoção pós-batalha, respawn) atualiza o
	# contador na HUD.
	_spawner.population_changed.connect(_update_hint)

	_spawn_companion()
	_build_hud()
	_update_hint()


func _spawn_companion() -> void:
	# Sem player não faz sentido spawnar quem segue; sem bestiário não temos
	# como resolver o código do starter em cor/tamanho.
	if _player == null or _db == null:
		return
	_companion = CompanionActor.create(_db, starter_code, _player)
	if _companion == null:
		return
	_companion.name = "Companion"
	add_child(_companion)


func _process(delta: float) -> void:
	if _mine_cooldown > 0.0:
		_mine_cooldown = maxf(0.0, _mine_cooldown - delta)

	# Solta a seleção quando o jogador vagou para longe. Sem isto, um alvo
	# esquecido do outro lado do mapa continua brilhando e o painel fica
	# poluindo a HUD.
	if _selected == null:
		return
	if not is_instance_valid(_selected):
		_clear_selection()
		return
	if _player and _selected.global_position.distance_to(_player.global_position) > DESELECT_DISTANCE:
		_clear_selection()


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)

	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color("#6B7280"))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 20
	_hint.offset_top = -44
	_hint.offset_bottom = -16
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hint)

	_info = CreatureInfoPanel.new()
	_info.name = "CreatureInfoPanel"
	layer.add_child(_info)

	_team_panel = PlayerTeamPanel.new()
	_team_panel.name = "TeamPanel"
	layer.add_child(_team_panel)
	if _db:
		_team_panel.setup(_db)

	_inventory_panel = InventoryPanel.new()
	_inventory_panel.name = "InventoryPanel"
	layer.add_child(_inventory_panel)
	_inventory.changed.connect(_on_inventory_changed)

	_mine_label = Label.new()
	_mine_label.name = "MineLabel"
	_mine_label.add_theme_color_override("font_color", Color("#7A8C6B"))
	_mine_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_mine_label.offset_left = 20
	_mine_label.offset_top = -68
	_mine_label.offset_bottom = -48
	_mine_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mine_label.hide()
	layer.add_child(_mine_label)


func _update_hint() -> void:
	if _hint == null:
		return
	var count := _spawner.actors().size() if _spawner else 0
	_hint.text = "WASD anda · Shift corre · clique numa criatura para ver, clique de novo para lutar   (%d no mapa)" % count


# ---------------------------------------------------------------------------
# input / seleção
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Durante a batalha o overlay processa em separado — nada aqui responde.
	if _duel != null:
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_ESCAPE and _selected != null:
			_clear_selection()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_F:
			trigger_mine()
			get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	handle_click_at(mb.position)
	get_viewport().set_input_as_handled()


## Ponto de entrada do clique. Público porque os testes headless disparam
## seleção e engate sem passar por evento de mouse — mais estável do que
## sintetizar `InputEventMouseButton` com coordenadas de tela.
func handle_click_at(screen_pos: Vector2) -> void:
	var actor := _pick_actor(screen_pos)
	handle_click_on(actor)


func handle_click_on(actor: CreatureActor) -> void:
	if actor == null:
		_clear_selection()
		return
	if actor == _selected:
		# Segundo clique na mesma criatura → engate.
		var to_engage := _selected
		_clear_selection()
		to_engage.request_engage()
	else:
		_select(actor)


func _pick_actor(screen_pos: Vector2) -> CreatureActor:
	if _camera == null:
		return null
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * CLICK_RAY_LENGTH
	var space := get_world_3d().direct_space_state
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
	if collider is CreatureActor:
		return collider as CreatureActor
	return null


func _select(actor: CreatureActor) -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = actor
	_selected.set_selected(true)
	if _info and _db:
		_info.show_for(_db, actor.creature_code, encounter_level, actor.size_meters)


func _clear_selection() -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = null
	if _info:
		_info.clear()


func selected_actor() -> CreatureActor:
	return _selected


func team() -> Array[String]:
	return _team


func inventory() -> PlayerInventory:
	return _inventory


# ---------------------------------------------------------------------------
# mineração
# ---------------------------------------------------------------------------

## Ponto de entrada da tecla F. Público para os testes headless dispararem
## sem sintetizar InputEventKey.
func trigger_mine() -> void:
	if _duel != null:
		return  # não minera durante combate
	if _mine_cooldown > 0.0:
		_show_mine_msg("Aguardando... (%.1fs)" % _mine_cooldown)
		return
	var ore := OreTable.sample(_mine_rng, "PZ-01")
	if ore.is_empty():
		return
	_inventory.add(str(ore["code"]))
	_mine_cooldown = MINE_COOLDOWN_SEC
	_show_mine_msg("Coletou: %s" % str(ore["name"]))


func _show_mine_msg(text: String) -> void:
	if _mine_label == null:
		return
	_mine_label.text = text
	_mine_label.show()
	# Remove a mensagem automaticamente num único Tween — cancela o anterior
	# se uma segunda mineração ocorrer antes dos 2 s expirarem.
	var t := create_tween()
	t.tween_interval(2.0)
	t.tween_callback(_mine_label.hide)


func _on_inventory_changed() -> void:
	if _inventory_panel:
		_inventory_panel.refresh(_inventory.entries())


# ---------------------------------------------------------------------------
# encontro
# ---------------------------------------------------------------------------

func _on_creature_engaged(actor: CreatureActor) -> void:
	if _duel != null:
		return  # já há um combate em curso

	_engaged_actor = actor
	_clear_selection()

	# Sem esconder o hint da HUD do mundo aqui, ele vaza atrás dos painéis do
	# duelo — o WASD do mapa fica no rodapé enquanto o combate acontece, o que
	# é ruído puro. O HudLayer inteiro apaga; o painel de identificação já
	# tinha sido escondido pelo `_clear_selection`.
	if _hint:
		_hint.visible = false
	if _team_panel:
		_team_panel.visible = false
	if _inventory_panel:
		_inventory_panel.visible = false
	if _mine_label:
		_mine_label.hide()

	var packed: PackedScene = load(DUEL_SCENE)
	_duel = packed.instantiate() as DuelScreen
	_duel.player_code = starter_code
	_duel.enemy_code = actor.creature_code
	_duel.duel_level = encounter_level
	_duel.closed.connect(_on_duel_closed)

	# CanvasLayer para o overlay ficar acima do 3D sem herdar a pausa do
	# mundo — a tela precisa continuar respondendo a tecla.
	var layer := CanvasLayer.new()
	layer.name = "DuelLayer"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(_duel)
	add_child(layer)

	if _camera:
		_camera.enter_battle()
	# Congela exploração e IA; o overlay segue processando.
	get_tree().paused = true


func _on_duel_closed(outcome: int) -> void:
	get_tree().paused = false
	if _camera:
		_camera.exit_battle()

	var layer := get_node_or_null("DuelLayer")
	if layer:
		layer.queue_free()
	_duel = null

	# Vitória → sai do mapa com respawn agendado.
	# Captura → sai do mapa SEM respawn; código entra no time do jogador.
	# Derrota/fuga → criatura permanece no mapa para poder ser reengajada.
	if _engaged_actor and is_instance_valid(_engaged_actor):
		if outcome == Battle.Outcome.PLAYER_WON:
			_spawner.remove_actor(_engaged_actor)
		elif outcome == Battle.Outcome.CAPTURED:
			_team.append(_engaged_actor.creature_code)
			_spawner.remove_actor(_engaged_actor, false)
			if _team_panel:
				_team_panel.refresh(_team)
		else:
			_engaged_actor.reset_engagement()
	_engaged_actor = null

	if _hint:
		_hint.visible = true
	if _team_panel:
		_team_panel.visible = true
	if _inventory_panel:
		_inventory_panel.visible = true
	# `_update_hint` também dispara via `population_changed` do spawner quando
	# a remoção ocorre, mas chamar aqui garante o texto certo mesmo nos
	# desfechos que não mexem na população.
	_update_hint()
