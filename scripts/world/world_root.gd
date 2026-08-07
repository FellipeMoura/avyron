class_name WorldRoot
extends Node3D

## Raiz do mapa de exploração.
##
## Por enquanto só faz a ponte para a tela de duelo. Quando o encontro no mapa
## existir — detecção por raio, patrulha, `engage` — a batalha vai começar
## in-world sem troca de cena, conforme `escala-e-camera-de-batalha`. A troca
## de cena aqui é andaime de playtest, não a arquitetura final.

const DUEL_SCENE := "res://scenes/duel.tscn"

@onready var _hint: Label = _build_hint()


func _build_hint() -> Label:
	var layer := CanvasLayer.new()
	add_child(layer)

	var label := Label.new()
	label.text = "WASD anda · Shift corre · [B] duelo de teste"
	label.add_theme_color_override("font_color", Color("#6B7280"))
	label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	label.offset_left = 20
	label.offset_top = -40
	label.offset_bottom = -16
	layer.add_child(label)
	return label


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_B:
			get_tree().change_scene_to_file(DUEL_SCENE)
