class_name WorldRoot
extends Node3D

## Raiz do mapa de exploração e árbitro do encontro.
##
## A batalha acontece **no mesmo espaço**, sem corte para outra cena: a tela
## de combate entra como overlay, a câmera dá o zoom de aproximação e o mundo
## congela atrás. É o que `escala-e-camera-de-batalha` especifica, e é por
## isso que a troca de cena que existia aqui antes saiu.

const DUEL_SCENE := "res://scenes/duel.tscn"

## Criatura do jogador enquanto não existe time montado por captura.
@export var starter_code := "CRT-002"
@export var encounter_level := 10

var _camera: IsoCamera
var _player: Node3D
var _spawner: CreatureSpawner
var _duel: DuelScreen
var _engaged_actor: CreatureActor
var _hint: Label


func _ready() -> void:
	_camera = get_node_or_null("IsoCamera") as IsoCamera
	_player = get_node_or_null("Player")

	# A câmera continua processando durante a pausa. Um Tween acompanha o
	# estado de pausa do nó a que está preso, então sem isto o zoom de entrada
	# em combate simplesmente não animaria — ficaria travado no valor inicial.
	if _camera:
		_camera.process_mode = Node.PROCESS_MODE_ALWAYS

	_spawner = CreatureSpawner.new()
	_spawner.name = "CreatureSpawner"
	_spawner.level = encounter_level
	add_child(_spawner)
	_spawner.creature_engaged.connect(_on_creature_engaged)

	_hint = _build_hint()
	_update_hint()


func _build_hint() -> Label:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)

	var label := Label.new()
	label.add_theme_color_override("font_color", Color("#6B7280"))
	label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	label.offset_left = 20
	label.offset_top = -44
	label.offset_bottom = -16
	layer.add_child(label)
	return label


func _update_hint() -> void:
	if _hint == null:
		return
	var count := _spawner.actors().size() if _spawner else 0
	_hint.text = "WASD anda · Shift corre · encoste numa criatura para lutar   (%d no mapa)" % count


# ---------------------------------------------------------------------------
# encontro
# ---------------------------------------------------------------------------

func _on_creature_engaged(actor: CreatureActor) -> void:
	if _duel != null:
		return  # já há um combate em curso

	_engaged_actor = actor

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


func _on_duel_closed(_outcome: int) -> void:
	get_tree().paused = false
	if _camera:
		_camera.exit_battle()

	var layer := get_node_or_null("DuelLayer")
	if layer:
		layer.queue_free()
	_duel = null

	if _engaged_actor and is_instance_valid(_engaged_actor):
		_engaged_actor.reset_engagement()
	_engaged_actor = null
	_update_hint()
