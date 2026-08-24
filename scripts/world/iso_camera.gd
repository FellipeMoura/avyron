class_name IsoCamera
extends Camera3D

## Câmera isométrica ortográfica travada. Segue o alvo com lookahead.
##
## O ângulo NÃO é configurável em gameplay, e isso é uma decisão travada, não
## uma simplificação: a silhueta que serve de critério de corte para cada
## criatura é a projeção do modelo vista de 30°/45°. Abrir a câmera para
## outros ângulos invalida o teste de silhueta de todo o bestiário.
##
## O **zoom**, ao contrário do ângulo, é ajustável — num lugar só. Batalha e
## chefe são proporções do mesmo `base_size`, então mexer nele move os três
## juntos, que é o comportamento desejado: são enquadramentos do mesmo rig,
## nunca cortes para outra câmera. O scroll do mouse entra como mais uma
## modulação desse mesmo `size`, não como uma câmera paralela — guardado como
## multiplicador (`_zoom_mult`) para sobreviver às transições de batalha em
## vez de ser descartado a cada uma.
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

## Tamanho ortográfico padrão. Este é o número que controla o zoom aparente, e
## é o inverso dele: tamanho maior enquadra mais mundo, ou seja, **menos** zoom.
##
## Era 12,0. O zoom caiu para 70% do que era — 12 / 0,7 — para caber mais mapa
## na tela.
@export var base_size: float = 17.15

## Modulações permitidas. Combate aproxima; chefe afasta. São modulações do
## mesmo enquadramento, nunca corte para outra câmera.
##
## São **proporções de `base_size`**, de propósito: mexer no zoom geral move a
## batalha junto, e é assim que tem de ser — o duelo é o mesmo enquadramento um
## pouco mais fechado, não uma segunda câmera com vida própria. Quem ajustar o
## `base_size` está ajustando os três.
@export var battle_zoom_ratio: float = 0.875   # -12.5%
@export var boss_zoom_ratio: float = 1.25      # +25%

## Pitch alvo durante a batalha. -18° é mais horizontal que os -30° do mapa —
## a câmera "abaixa a cabeça" para enquadrar os combatentes mais de lado, dando
## o corte cinematográfico clássico do início do duelo.
##
## O contrato do teste de silhueta (30°/45°) vale para EXPLORAÇÃO — durante a
## batalha o overlay do duelo ocupa praticamente toda a tela e a projeção do
## mundo pouco importa; o tilt está aqui pelo *feel* da entrada, não para
## revelar geometria nova.
@export var battle_pitch_degrees: float = -18.0

@export var zoom_in_duration: float = 0.5
@export var zoom_out_duration: float = 0.4

## Quanto a câmera se adianta na direção do movimento, em metros.
@export var lookahead_distance: float = 2.0
@export var follow_smoothing: float = 8.0
@export var lookahead_smoothing: float = 4.0

@export var target_path: NodePath

## Passo por notch de scroll, e faixa do multiplicador sobre `base_size`.
## Faixa relativa (não tamanho absoluto) de propósito: continua válida se
## `base_size` for retunado depois, sem precisar remedir os limites.
const ZOOM_STEP := 0.1
const ZOOM_MULT_MIN := 0.5
const ZOOM_MULT_MAX := 2.0

var _target: Node3D
var _lookahead := Vector3.ZERO
var _transition_tween: Tween
var _zoom_mult := 1.0

## Os dois combatentes, durante a batalha. Enquanto ambos estiverem
## presentes, o foco da câmera é o vão entre eles, não `_target` — é o que
## joga o jogador para a margem do quadro e deixa o duelo no meio, que é a
## composição de duelo (a exploração continua centrada no jogador).
var _focus_a: Node3D
var _focus_b: Node3D
## Trava o scroll durante a batalha: a câmera já está sob o tween de combate
## (`PROCESS_MODE_ALWAYS`, roda com o mundo pausado — ver `WorldRoot`), e
## scroll nesse meio-tempo brigaria com ele por `size` quadro a quadro.
var _in_battle := false


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = _zoomed_base_size()
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
	var focus: Vector3
	if _focus_a and is_instance_valid(_focus_a) and _focus_b and is_instance_valid(_focus_b):
		# Sem lookahead aqui: os dois combatentes assentam parados (ou quase),
		# e adiantar o quadro na direção de um deles puxaria o vão para o lado
		# de quem se moveu por último em vez de manter os dois enquadrados.
		_lookahead = Vector3.ZERO
		focus = (_focus_a.global_position + _focus_b.global_position) * 0.5
	elif _target:
		var desired_lookahead := Vector3.ZERO
		if _target is CharacterBody3D:
			var v: Vector3 = (_target as CharacterBody3D).velocity
			v.y = 0.0
			if v.length_squared() > 0.01:
				desired_lookahead = v.normalized() * lookahead_distance

		_lookahead = _lookahead.lerp(desired_lookahead, clampf(lookahead_smoothing * delta, 0.0, 1.0))
		focus = _target.global_position + _lookahead
	else:
		return

	global_position = global_position.lerp(
		_rig_position(focus), clampf(follow_smoothing * delta, 0.0, 1.0)
	)


## Posição da câmera para focar um ponto, recuando ao longo do eixo de visão.
##
## Usa o `transform.basis` corrente em vez das constantes de propósito: durante
## a transição de batalha o pitch é tweenado, e se a posição do rig continuasse
## sendo calculada a partir do ângulo antigo, o alvo escorregava do centro do
## quadro conforme a câmera tiltava. Como a projeção é ortográfica, a distância
## em si não altera o zoom aparente — só evita clipping — então basear a
## posição na orientação corrente é seguro.
func _rig_position(focus: Vector3) -> Vector3:
	# -Z é a direção para onde a câmera olha; recuar é ir no sentido oposto.
	return focus - transform.basis * Vector3(0, 0, -RIG_DISTANCE)


# ---------------------------------------------------------------------------
# transição de batalha
# ---------------------------------------------------------------------------

func enter_battle() -> void:
	_in_battle = true
	_tween_transition(_zoomed_base_size() * battle_zoom_ratio, battle_pitch_degrees, zoom_in_duration)

func enter_boss_battle() -> void:
	_in_battle = true
	_tween_transition(_zoomed_base_size() * boss_zoom_ratio, battle_pitch_degrees, zoom_in_duration)

func exit_battle() -> void:
	_in_battle = false
	clear_battle_focus()
	# Volta para o zoom que o jogador tinha escolhido, não para o `base_size`
	# cru — senão todo duelo resetaria o scroll dele.
	_tween_transition(_zoomed_base_size(), PITCH_DEGREES, zoom_out_duration)


## Prende o foco da câmera ao vão entre os dois combatentes em vez de
## `_target`. Chamado pelo diretor de encontro junto com `enter_battle`, com
## a companheira e o adversário (selvagem ou duelista de arena) — os mesmos
## dois corpos que `BattleStaging` encena. Se um dos dois faltar (playtest
## sem companheira, por exemplo), a câmera silenciosamente continua em
## `_target`, o mesmo padrão de "sem plateia, sem correção" de
## `BattleStaging.trainer_error`.
func set_battle_focus(a: Node3D, b: Node3D) -> void:
	_focus_a = a
	_focus_b = b


## Devolve o foco a `_target`. Chamado ao sair da batalha; também limpo aqui
## dentro por `exit_battle`, para nenhum chamador esquecer de destravar.
func clear_battle_focus() -> void:
	_focus_a = null
	_focus_b = null


## Tween paralelo de zoom (`size`) e pitch (`rotation_degrees:x`). Um único
## Tween com `set_parallel(true)` garante que as duas propriedades andem
## juntas, com a mesma easing — a leitura tem de ser de UM movimento, não de
## dois efeitos concorrentes.
func _tween_transition(target_size: float, target_pitch: float, duration: float) -> void:
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(self, "size", target_size, duration)
	_transition_tween.tween_property(self, "rotation_degrees:x", target_pitch, duration)


# ---------------------------------------------------------------------------
# zoom por scroll
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _in_battle or not (event is InputEventMouseButton and event.pressed):
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom(-ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom(ZOOM_STEP)


## Roda pra cima aproxima (`size` menor — ver docstring de `base_size`);
## roda pra baixo afasta. O estado é o multiplicador, nunca `size` direto,
## porque `enter_battle` precisa dele sobrevivendo à animação de batalha.
func _adjust_zoom(delta_mult: float) -> void:
	_zoom_mult = clampf(_zoom_mult + delta_mult, ZOOM_MULT_MIN, ZOOM_MULT_MAX)
	size = _zoomed_base_size()


func _zoomed_base_size() -> float:
	return base_size * _zoom_mult


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
