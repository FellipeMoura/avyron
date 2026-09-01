class_name PlayerController
extends CharacterBody3D

## Locomoção do domador. Livre, não presa a grid, velocidade única.
##
## `WALK_SPEED` guarda o nome por herança, mas 5,2 m/s é marcha de CORRIDA —
## humano andando faz ~1,4 m/s. Era daí que vinha o deslize: o corpo viajava a
## 5,2 tocando o ciclo de `Walk`, que fora calibrado num `WALK_SPEED` anterior
## de 4,0 e nunca remedido depois de ele subir 30%. A correção foi dar o clipe
## certo à marcha, não mexer na velocidade — `CharacterRig.update_motion`
## escolhe `Run` acima de `RUN_THRESHOLD`, e o jogador está sempre acima dele.
## Se ainda restar deslize, o ajuste seguinte é a CADÊNCIA (`speed_scale` do
## AnimationPlayer), não o clipe nem a velocidade.
##
## Especificação: documento `movimento-e-controles` no bestiário.

const WALK_SPEED := 5.2

## Tempo de 0 até a velocidade de caminhada, e de qualquer velocidade até 0.
const ACCEL_TIME := 0.15
const BRAKE_TIME := 0.10

## Velocidade de subida do empuxo, quando `_floating()` está ativo.
##
## Até 2026-09-01 o corpo seguia a colisão o tempo todo, gravidade incluída,
## também em mar aberto — o que combinava com a maior parte do leito (raso,
## perto da cota), mas o Mar Profundo (`MapTerrain.ABYSS_*`) desce 15 m e sobe
## de volta numa rampa mais íngreme que os 45° que o `CharacterBody3D` aceita
## como piso. Resultado: o jogador caía lá dentro e não tinha como escalar de
## volta andando — "cai, some e não volta mais". A partir daqui, quando
## `_floating()` está ativo o corpo NÃO segue mais o leito: cai normalmente
## enquanto está acima da cota (entrar na água por cima ainda afunda um
## pouco, para não flutuar no ar) e sobe de volta para a cota assim que fica
## abaixo dela. É empuxo por velocidade, não teleporte de posição — continua
## passando por `move_and_slide`, então colisão horizontal (e vertical, se o
## corpo trombar nalgum relevo que ainda esteja acima da cota, como o topo do
## recife) segue valendo normalmente.
##
## O gatilho é `MapTerrain.should_float` — ver `_floating()` e o histórico das
## duas versões erradas que vieram antes dele no comentário de lá.
const FLOAT_RISE_SPEED := 3.0

## Faixa ao redor da cota em que a velocidade vertical do empuxo zera em vez
## de alternar entre subir e cair. Sem isto o corpo ultrapassa o alvo a cada
## quadro (sobe a `FLOAT_RISE_SPEED` fixos, sem desacelerar perto da cota) e a
## gravidade do quadro seguinte não zera a velocidade herdada — só a reduz aos
## poucos —, então ele continua subindo um pouco além do alvo antes de
## finalmente cair de novo. O resultado lia como "quicando" mesmo parado.
const FLOAT_DEADBAND := 0.1

## A aparência do domador na v1 — sem tela de criação, uma receita fixa do
## kit de personagens (mesmo sistema dos NPCs, ver CharacterRig). Quando a
## criação de personagem entrar, esta constante vira o valor inicial do que
## o jogador escolher e o escolhido persiste no save — nunca no bestiário,
## que só conhece NPC.
const DEFAULT_RECIPE := {
	"gender": "male",
	"hair": "Hair_SimpleParted",
	"body": "Male_Ranger_Body",
	"arms": "Male_Ranger_Arms",
	"legs": "Male_Ranger_Legs",
	"feet": "Male_Ranger_Feet_Boots",
}

## Quão rápido o corpo gira para encarar a direção do movimento.
@export var turn_speed: float = 12.0

@export var gravity: float = 24.0

## Relevo do mapa, injetado por `WorldRoot`. Nulo (bancada de teste sem mundo)
## = ninguém está na água, e o corpo anda como sempre andou.
var terrain: MapTerrain

var _speed_target := 0.0
var _rig: CharacterRig



func _ready() -> void:
	_rig = CharacterRig.create(DEFAULT_RECIPE)
	if _rig == null:
		return
	# Pés na base da cápsula de colisão (origem do corpo é o centro dela).
	var shape := $Collision.shape as CapsuleShape3D
	_rig.position.y = -shape.height * 0.5
	add_child(_rig)
	# A cápsula segue existindo como colisão; o cilindro visual sai de cena.
	$Mesh.visible = false


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := IsoCamera.screen_to_world_direction(input)

	# Aceleração e frenagem são definidas por tempo, não por força: é assim
	# que os documentos especificam, e é o que mantém o feel igual
	# independente da velocidade alvo.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if direction.is_zero_approx():
		var brake := (WALK_SPEED / BRAKE_TIME) * delta
		horizontal = horizontal.move_toward(Vector3.ZERO, brake)
	else:
		var accel := (WALK_SPEED / ACCEL_TIME) * delta
		horizontal = horizontal.move_toward(direction * WALK_SPEED, accel)
		_face_direction(direction, delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if _floating():
		var target_y := terrain.water_line + staged_ground_offset()
		var diff := target_y - global_position.y
		if absf(diff) < FLOAT_DEADBAND:
			velocity.y = 0.0
		elif diff > 0.0:
			velocity.y = FLOAT_RISE_SPEED
		else:
			velocity.y -= gravity * delta
	elif is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()

	if _rig != null:
		_rig.update_motion(ground_speed(), submerged())


## O domador está debaixo d'água?
##
## Medido nos PÉS, não no centro do corpo: é o pé que decide se ele já subiu a
## rampa da costa, e testar o centro o faria "sair da água" meio metro antes de
## o corpo sair.
##
## O PZ-01 é o leito de um mar — fora do platô da costa a resposta é sempre
## sim, e por isso o nado é o estado NORMAL da exploração, não a exceção. Quem
## responde é o terreno (`MapTerrain.submerged`), com a mesma cota que
## fragmenta a névoa.
func submerged() -> bool:
	if terrain == null:
		return false
	return terrain.submerged(global_position - Vector3(0.0, staged_ground_offset(), 0.0))


## Verdadeiro quando a física normal (gravidade + colisão) para de valer no
## eixo Y, e o empuxo (ver `FLOAT_RISE_SPEED`) assume.
##
## `MapTerrain.should_float(pos)` — leito fundo ou íngreme demais para andar,
## a MESMA pergunta que `CompanionActor` faz (via `surface_or_ground`) para
## resolver o próprio Y sem ter física nenhuma. Deliberadamente NÃO consulta
## `is_on_floor()`: essa foi a versão anterior (revertida no mesmo dia), e o
## defeito dela é sutil — `is_on_floor()` reflete o QUADRO atual do motor, não
## só o terreno. Um corpo momentaneamente no ar por qualquer motivo alheio à
## profundidade (cair de um teleporte, de um `y` de partida acima do chão) já
## fica `not is_on_floor()`, e como `submerged()` é incondicional fora de
## `on_dry_land`, isso bastava para flutuar em vez de cair até o leito raso e
## comum que estava logo abaixo — nunca chegava a ser tocado. Consultar o
## RELEVO (`should_float`, calculado do mesmo campo de altura que gera a
## malha e a colisão) em vez do ESTADO do motor evita os dois problemas de
## uma vez: fecha a lacuna que fazia o Mar Profundo "descer e depois subir" e
## não abre a nova que fazia o leito raso comum flutuar à toa.
func _floating() -> bool:
	return terrain != null and terrain.should_float(global_position)



func _face_direction(direction: Vector3, delta: float) -> void:
	# No Godot a frente de um nó é -Z, não +Z. `atan2(x, z)` alinharia o eixo
	# +Z com a direção, deixando o corpo andando de costas — foi exatamente o
	# que aconteceu até o teste de cena pegar. Negar as duas componentes
	# alinha -Z, que é a frente de verdade.
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


## Velocidade horizontal atual, para a máquina de animação escolher entre
## `Idle`, `Walk` e `Run`.
func ground_speed() -> float:
	return Vector3(velocity.x, 0.0, velocity.z).length()


# ---------------------------------------------------------------------------
# contrato de encenação (BattleStaging)
# ---------------------------------------------------------------------------
#
# Na abertura do duelo o mundo está pausado e o `_physics_process` daqui não
# roda: quem leva este corpo até o posto de plateia é a `BattleStaging`. Ver o
# mesmo par em `CreatureActor` sobre por que os métodos são chamados por nome.

## Quanto a origem do corpo fica acima do chão: meia cápsula de colisão, que é
## a mesma medida que o rig usa para pôr os pés no lugar (`_ready`). Lida da
## forma, e não de uma constante, pelo mesmo motivo do raio em
## `EncounterDirector._player_radius` — duas medidas do mesmo corpo
## discordariam no dia em que uma delas mudasse.
func staged_ground_offset() -> float:
	var collision := get_node_or_null("Collision") as CollisionShape3D
	if collision and collision.shape is CapsuleShape3D:
		return (collision.shape as CapsuleShape3D).height * 0.5
	return 0.0


## A marcha imposta pela encenação, pela mesma escada da exploração.
##
## Zera a velocidade junto: a encenação é dona deste corpo enquanto o mundo
## está pausado, e a velocidade guardada do instante do engate voltaria a valer
## no quadro em que a árvore despausa — o jogador daria um tranco na direção em
## que estava andando antes de o duelo abrir.
func staged_gait(speed: float) -> void:
	velocity = Vector3.ZERO
	if _rig != null:
		_rig.update_motion(speed, submerged())


## A encenação é dona deste corpo enquanto o mundo está pausado, e nó pausado
## não anima: sem isto o rig fica congelado no quadro em que o duelo abriu.
func staged_animating(enabled: bool) -> void:
	if _rig != null:
		_rig.animate_while_paused(enabled)


