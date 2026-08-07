class_name IsoCamera
extends Camera3D

## Câmera isométrica ortográfica travada. Segue o alvo com lookahead.
##
## O ângulo NÃO é configurável em gameplay, e isso é uma decisão travada, não
## uma simplificação: a silhueta que serve de critério de corte para cada
## criatura é a projeção do modelo vista de 30°/45°. Abrir a câmera para
## outros ângulos invalida o teste de silhueta de todo o bestiário.
##
## Especificação: documentos `camera-e-perspectiva` e
## `escala-e-camera-de-batalha` no bestiário.

## Inclinação acima do horizonte.
const PITCH_DEGREES := -30.0
## Azimute.
const YAW_DEGREES := 45.0

## Distância da câmera ao alvo ao longo do eixo de visão. Como a projeção é
## ortográfica, isto não muda o tamanho aparente — só evita clipping.
const RIG_DISTANCE := 20.0

## Tamanho ortográfico padrão. Este é o número que controla o zoom aparente.
@export var base_size: float = 12.0

## Modulações permitidas. Combate aproxima; chefe afasta. São modulações do
## mesmo enquadramento, nunca corte para outra câmera.
@export var battle_zoom_ratio: float = 0.875   # -12.5%
@export var boss_zoom_ratio: float = 1.25      # +25%

@export var zoom_in_duration: float = 0.5
@export var zoom_out_duration: float = 0.4

## Quanto a câmera se adianta na direção do movimento, em metros.
@export var lookahead_distance: float = 2.0
@export var follow_smoothing: float = 8.0
@export var lookahead_smoothing: float = 4.0

@export var target_path: NodePath

var _target: Node3D
var _lookahead := Vector3.ZERO
var _size_tween: Tween


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = base_size
	# Ortográfica com alvo à frente: o near precisa ser negativo o bastante
	# para não recortar o que está entre a câmera e o ponto de foco.
	near = 0.05
	far = 200.0
	rotation_degrees = Vector3(PITCH_DEGREES, YAW_DEGREES, 0.0)

	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	if _target:
		global_position = _rig_position(_target.global_position)


func set_target(node: Node3D) -> void:
	_target = node
	if _target:
		global_position = _rig_position(_target.global_position)


func _physics_process(delta: float) -> void:
	if not _target:
		return

	var desired_lookahead := Vector3.ZERO
	if _target is CharacterBody3D:
		var v: Vector3 = (_target as CharacterBody3D).velocity
		v.y = 0.0
		if v.length_squared() > 0.01:
			desired_lookahead = v.normalized() * lookahead_distance

	_lookahead = _lookahead.lerp(desired_lookahead, clampf(lookahead_smoothing * delta, 0.0, 1.0))

	var focus := _target.global_position + _lookahead
	global_position = global_position.lerp(
		_rig_position(focus), clampf(follow_smoothing * delta, 0.0, 1.0)
	)


## Posição da câmera para focar um ponto, recuando ao longo do eixo de visão.
func _rig_position(focus: Vector3) -> Vector3:
	var basis_ := Basis.from_euler(
		Vector3(deg_to_rad(PITCH_DEGREES), deg_to_rad(YAW_DEGREES), 0.0)
	)
	# -Z é a direção para onde a câmera olha; recuar é ir no sentido oposto.
	return focus - basis_ * Vector3(0, 0, -RIG_DISTANCE)


# ---------------------------------------------------------------------------
# modulações de zoom
# ---------------------------------------------------------------------------

func enter_battle() -> void:
	_tween_size(base_size * battle_zoom_ratio, zoom_in_duration)

func enter_boss_battle() -> void:
	_tween_size(base_size * boss_zoom_ratio, zoom_in_duration)

func exit_battle() -> void:
	_tween_size(base_size, zoom_out_duration)


func _tween_size(target_size: float, duration: float) -> void:
	if _size_tween and _size_tween.is_valid():
		_size_tween.kill()
	_size_tween = create_tween()
	_size_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_size_tween.tween_property(self, "size", target_size, duration)


# ---------------------------------------------------------------------------
# conversão de input
# ---------------------------------------------------------------------------

## Converte input de tela para direção no plano do chão.
##
## O jogador nunca pressiona "norte do mundo" — sempre "norte da tela". Sem
## esta rotação de 45°, andar com W move na diagonal visual, que é o erro
## clássico de câmera isométrica.
static func screen_to_world_direction(input: Vector2) -> Vector3:
	if input.is_zero_approx():
		return Vector3.ZERO
	var yaw := deg_to_rad(YAW_DEGREES)
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	return dir.normalized()
