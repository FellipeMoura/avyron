class_name PlayerController
extends CharacterBody3D

## Locomoção do domador. Livre, não presa a grid.
##
## As velocidades e os tempos abaixo estão travados porque os ciclos de
## animação `walk` (~0.85 s por passo) e `run` (~0.50 s) foram calibrados a
## partir deles. Mudar a velocidade sem recalibrar os loops produz
## foot-sliding visível.
##
## Especificação: documento `movimento-e-controles` no bestiário.

const WALK_SPEED := 4.0
const RUN_SPEED := 7.0

## Tempo de 0 até a velocidade de caminhada, e de qualquer velocidade até 0.
const ACCEL_TIME := 0.15
const BRAKE_TIME := 0.10

## Quão rápido o corpo gira para encarar a direção do movimento.
@export var turn_speed: float = 12.0

@export var gravity: float = 24.0

var _speed_target := 0.0


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := IsoCamera.screen_to_world_direction(input)

	var running := Input.is_action_pressed("run")
	var max_speed := RUN_SPEED if running else WALK_SPEED

	# Aceleração e frenagem são definidas por tempo, não por força: é assim
	# que os documentos especificam, e é o que mantém o feel igual
	# independente da velocidade alvo.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if direction.is_zero_approx():
		var brake := (WALK_SPEED / BRAKE_TIME) * delta
		horizontal = horizontal.move_toward(Vector3.ZERO, brake)
	else:
		var accel := (WALK_SPEED / ACCEL_TIME) * delta
		horizontal = horizontal.move_toward(direction * max_speed, accel)
		_face_direction(direction, delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()


func _face_direction(direction: Vector3, delta: float) -> void:
	# No Godot a frente de um nó é -Z, não +Z. `atan2(x, z)` alinharia o eixo
	# +Z com a direção, deixando o corpo andando de costas — foi exatamente o
	# que aconteceu até o teste de cena pegar. Negar as duas componentes
	# alinha -Z, que é a frente de verdade.
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


## Velocidade horizontal atual, para a máquina de animação escolher entre
## `idle`, `walk` e `run`.
func ground_speed() -> float:
	return Vector3(velocity.x, 0.0, velocity.z).length()
