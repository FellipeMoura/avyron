class_name CompanionActor
extends Node3D

## A criatura ativa do jogador, seguindo ele pelo mapa.
##
## Puramente visual: sem CharacterBody3D, sem colisão. Isso é intencional —
## a companheira não pode ser clicável (o raycast do clique cai só em criaturas
## selvagens), não deve empurrar nem ser empurrada pelo jogador, e não precisa
## de gravidade porque flutua na altura de encaramento do próprio corpo.
##
## ## Por que trilha de migalhas, e não offset preso ao jogador
##
## A versão anterior mirava um ponto no espaço **local** do jogador e copiava
## `rotation.y` dele quadro a quadro. O resultado lia como duas peças da mesma
## engrenagem: girar no lugar fazia a companheira orbitar na mesma hora, e ela
## partia no mesmo quadro que o comando — nunca *atrás* do comando.
##
## Aqui ela persegue as posições por onde o jogador **realmente passou**,
## mantendo uma distância medida ao longo do caminho. Três coisas caem de
## graça disso, e são exatamente as que faltavam:
##
## - **Ela sai depois.** Enquanto a trilha não acumula `FOLLOW_DISTANCE`, o
##   alvo não anda — o jogador precisa esticar a coleira antes de puxar.
## - **Ela vai para as costas.** O alvo é um ponto do rastro, então ela chega
##   por trás e faz a mesma curva que ele fez, em vez de cortar na diagonal.
## - **Girar no lugar não move ninguém.** Rodar a câmera não deposita migalha,
##   então ela fica parada — que é o oposto de orbitar.
##
## A orientação também é dela: vem da própria direção de marcha, não do
## `rotation.y` do jogador. Parada, ela vira devagar para encarar o domador.

## Distância mantida **ao longo do caminho**, não em linha reta. É por isso que
## ela contorna em vez de cortar: numa curva fechada, um metro e meio de rastro
## pode ser meio metro de distância direta.
const FOLLOW_DISTANCE := 2.1

## Folga da coleira. É daqui que sai o atraso na largada: parada, a companheira
## está em cima do alvo, e o jogador precisa andar meio metro antes de ela ter
## motivo para se mexer — a 4 m/s, um oitavo de segundo de imobilidade, e só
## então a rampa de aceleração começa.
##
## Também é o que impede o tremor no lugar, corrigindo frações de centímetro
## contra um alvo que nunca fica perfeitamente parado.
const STOP_DISTANCE := 0.5

## Granularidade do rastro. Menor deixa a curva mais fiel e custa mais pontos;
## 25 cm é fino o bastante para o raio de giro do jogador e mantém a trilha em
## torno de meia dúzia de migalhas.
const TRAIL_SPACING := 0.25

## Quanto o atraso vira velocidade.
##
## Um controlador proporcional puro nunca zera o erro: em regime, a companheira
## fica parada no ponto em que a velocidade que o ganho pede iguala a do
## jogador. Isso **não** é defeito aqui — é o que faz a coleira esticar
## enquanto ele anda e encolher quando ele para. Com 7.0, ela anda ~3,3 m
## atrás ao caminhar (`WALK_SPEED` 5.2) e recolhe para ~2,3 m parada.
const CATCH_UP_GAIN := 7.0

## Teto acima do passo do jogador — sem essa folga ela nunca recupera o
## terreno perdido na largada (ver `_test_start_delay`), e a coleira estica
## para sempre.
const MAX_SPEED := PlayerController.WALK_SPEED * 1.12

## Mais lenta que a do jogador (0,15 s até andar): a rampa é a segunda metade
## do atraso na largada, depois da folga da coleira.
const ACCELERATION := 8.0
const DECELERATION := 14.0

## Mais lento que os 12.0 do jogador, de propósito: o giro dela chegando depois
## do dele é metade da leitura de "seguindo".
const TURN_SPEED := 7.0

## Abaixo disto ela conta como parada, e passa a encarar o domador.
const IDLE_SPEED := 0.05

## Marcha a partir da qual ela corre em vez de andar. Fração do passo do
## jogador, e não um número solto, pelo mesmo motivo de `MAX_SPEED`: os dois
## andam juntos, e um limiar independente divergiria no dia em que a
## velocidade dele mudasse.
const RUN_THRESHOLD := PlayerController.WALK_SPEED * 0.45


## Altura do chão SEM terreno — fallback para bancadas de teste que montam a
## companheira sem mundo. Com o relevo, `WorldRoot` injeta `terrain` e o Y
## vira consulta (`_ground_y`), exatamente a evolução que este comentário
## prometia quando o mapa ainda era plano.
##
## Estar aqui conserta um erro de um metro: a companheira grudava o Y no
## `global_position` do jogador, que é o **centro da cápsula** dele (~0,9 m), e
## depois ainda subia meia altura do próprio corpo. Resultado, ela flutuava na
## altura do tronco dele — invisível enquanto andava ao lado, e desenhada por
## cima dele assim que passou a andar atrás.
const GROUND_Y := 0.0

## Amplitude e frequência do bob vertical em repouso. Um trilobita parado que
## não respira é um adereço no chão; um leve sobe-e-desce dá vida sem custar
## nada — e casa com o rig flutuante que Arambi usa por padrão. Em movimento
## os dois crescem, em `_bob`.
const BOB_AMPLITUDE := 0.04
const BOB_HZ := 1.1

var creature_code := ""
var display_name := ""
var element_code := ""
var size_meters := 1.8
var model_url := ""
## Injetado por `WorldRoot` depois do spawn; nulo em bancada = chão plano.
var terrain: MapTerrain

var _player: Node3D
var _mesh_root: Node3D
var _anim: AnimationPlayer
var _base_y := 0.0

## Malhas do corpo, guardadas para a aura do Despertar Ancestral poder inflar
## uma casca irmã de cada uma. Refeitas junto com o corpo em `_build_visual`,
## porque `set_creature` troca a criatura ativa sem destruir o ator.
var _mesh_instances: Array[MeshInstance3D] = []

var _awakened := false
var _aura_shells: Array[MeshInstance3D] = []
var _aura_light: OmniLight3D

## Posições por onde o jogador passou, da mais antiga para a mais recente.
var _trail: Array[Vector3] = []

var _speed := 0.0
var _heading := Vector3.FORWARD
var _bob_phase := 0.0


## Ponto de entrada. `db` é o Bestiary autoload; `code` é o CRT-XXX da
## criatura ativa; `player` é o corpo do domador para seguir.
static func create(db: BestiaryData, code: String, player: Node3D) -> CompanionActor:
	var c := db.creature(code)
	if c.is_empty():
		push_error("CompanionActor: criatura %s nao existe no bundle" % code)
		return null

	var actor := CompanionActor.new()
	actor.creature_code = code
	actor.display_name = str(c["name"])
	actor.element_code = str(c["element"])
	actor.size_meters = float(c["stats"]["sizeMeters"])
	# Mesmo cuidado do CreatureActor: `modelUrl` null não pode virar "<null>".
	var url: Variant = c.get("modelUrl")
	actor.model_url = url if url is String else ""
	actor._player = player
	return actor


func _ready() -> void:
	if _player == null:
		push_error("CompanionActor: sem jogador para seguir")
		return

	_build_visual()

	# Nasce já atrás do jogador, na distância de regime. Sem isso o primeiro
	# quadro a coloca na origem do mundo e ela atravessa o mapa correndo.
	var behind := _player.global_transform.basis.z  # +Z é a retaguarda: a frente é -Z
	global_position = _player.global_position + behind * FOLLOW_DISTANCE
	global_position.y = _ground_y()
	_heading = -behind
	rotation.y = atan2(-_heading.x, -_heading.z)
	_seed_trail(behind)


func _ground_y() -> float:
	return terrain.height_at(global_position) if terrain else GROUND_Y


## Semeia o rastro como se o jogador já tivesse vindo em linha reta até aqui.
##
## Sem isto a trilha nasce com um ponto só; o alvo, que é o ponto a
## `FOLLOW_DISTANCE` de rastro atrás, cai em cima do próprio jogador por falta
## de trilha para recuar — e a companheira dispara para os pés dele no primeiro
## quadro, exatamente o oposto do que ela deve fazer.
func _seed_trail(behind: Vector3) -> void:
	_trail.clear()
	var steps := maxi(1, int(ceil(FOLLOW_DISTANCE / TRAIL_SPACING)))
	# Da mais antiga (onde ela está) para a mais recente (onde ele está).
	for i in range(steps, 0, -1):
		_trail.append(_player.global_position + behind * (FOLLOW_DISTANCE * float(i) / float(steps)))
	_trail.append(_player.global_position)


func _process(delta: float) -> void:
	if _player == null:
		return

	_record_trail()
	_advance(delta)
	_face(delta)
	_bob(delta)
	_update_clip()

	# Apoiada no chão, como qualquer criatura do mapa. O `_advance` já trabalha
	# só no plano; isto é a garantia de que nada de fora empurrou o Y — e,
	# com relevo, é o que a faz acompanhar a colina sem precisar de física.
	global_position.y = _ground_y()


# ---------------------------------------------------------------------------
# trilha
# ---------------------------------------------------------------------------

## Deposita uma migalha quando o jogador andou o bastante, e descarta as que
## ficaram para trás do ponto de seguimento — o rastro é uma janela sobre o
## passado recente, não um histórico.
func _record_trail() -> void:
	var here := _player.global_position
	if _trail.is_empty() or here.distance_to(_trail[-1]) >= TRAIL_SPACING:
		_trail.append(here)

	# Uma folga além da distância de seguimento mantém o segmento onde o alvo
	# é interpolado; cortar exatamente no limite tiraria o chão dele.
	var limit := FOLLOW_DISTANCE + TRAIL_SPACING * 2.0
	var travelled := 0.0
	var ahead := here
	for i in range(_trail.size() - 1, -1, -1):
		travelled += ahead.distance_to(_trail[i])
		ahead = _trail[i]
		if travelled > limit:
			_trail = _trail.slice(i)
			return


## O ponto do rastro a `FOLLOW_DISTANCE` de caminho atrás do jogador.
##
## Enquanto a trilha for mais curta que isso — parado, ou nos primeiros passos
## depois de sair do lugar — devolve a migalha mais antiga, que está onde a
## companheira já se encontra. É esse retorno que produz o atraso na largada,
## sem precisar de nenhum temporizador.
func _follow_target() -> Vector3:
	var remaining := FOLLOW_DISTANCE
	var ahead := _player.global_position

	for i in range(_trail.size() - 1, -1, -1):
		var point := _trail[i]
		var segment := ahead.distance_to(point)
		if segment >= remaining:
			return ahead.lerp(point, remaining / segment) if segment > 0.0 else point
		remaining -= segment
		ahead = point

	return ahead


# ---------------------------------------------------------------------------
# marcha
# ---------------------------------------------------------------------------

func _advance(delta: float) -> void:
	var to_target := _follow_target() - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	# Velocidade proporcional ao atraso, descontada a zona morta: a transição
	# entre parar e andar fica contínua em vez de ligar no talo.
	var desired := 0.0
	if distance > STOP_DISTANCE:
		desired = clampf((distance - STOP_DISTANCE) * CATCH_UP_GAIN, 0.0, MAX_SPEED)

	var rate := ACCELERATION if desired > _speed else DECELERATION
	_speed = move_toward(_speed, desired, rate * delta)

	if _speed <= 0.0 or distance <= 0.0001:
		return

	var direction := to_target / distance
	# Nunca passar do alvo num quadro longo — ultrapassar produziria o
	# vaivém clássico de quem persegue com passo fixo.
	global_position += direction * minf(_speed * delta, distance)
	_heading = direction


func _face(delta: float) -> void:
	var want := _heading

	if _speed < IDLE_SPEED:
		# Parada, encara o domador. Uma criatura que fica de costas para quem
		# ela segue parece um objeto largado ali.
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.0001:
			want = to_player.normalized()

	if want.length_squared() < 0.0001:
		return

	# A frente de um nó no Godot é -Z. Negar as duas componentes alinha o eixo
	# certo; `atan2(x, z)` deixaria o corpo andando de costas.
	var target_yaw := atan2(-want.x, -want.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


## Bob por fase acumulada, não por `tempo * frequência`: como a frequência
## varia com a velocidade, multiplicar o tempo faria a onda saltar toda vez que
## ela acelera ou freia.
func _bob(delta: float) -> void:
	if _mesh_root == null:
		return
	# Corpo com rig anima a própria respiração; o bob sintético por cima
	# leria como um modelo quicando num pistão.
	if _anim != null:
		return
	var motion := clampf(_speed / PlayerController.WALK_SPEED, 0.0, 1.6)
	_bob_phase += delta * TAU * BOB_HZ * (1.0 + motion)
	_mesh_root.position.y = _base_y + sin(_bob_phase) * BOB_AMPLITUDE * (1.0 + motion * 1.5)


# ---------------------------------------------------------------------------
# corpo
# ---------------------------------------------------------------------------

## Escolhe o clipe pela marcha real, com o mesmo contrato do CreatureActor:
## sem clipe correspondente (cápsula, ou voador sem `Walk`), nada muda.
##
## A escada tem `Run` porque ela acompanha um jogador que CORRE: em regime a
## companheira viaja perto de `PlayerController.WALK_SPEED` (5,2 m/s, teto em
## `MAX_SPEED`), e tocar `Walk` nessa marcha a faria deslizar ao lado dele
## exatamente como ele deslizava antes de ganhar o `Run`.
func _update_clip() -> void:
	if _anim == null:
		return
	var clip := _clip_for_speed(_speed)
	if _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.2)


## O clipe da marcha. Cai para `Walk` quando o corpo não tem `Run` — os
## placeholders variam, e silenciar aqui deixaria a criatura presa no clipe
## anterior em vez de andar.
func _clip_for_speed(speed: float) -> String:
	if speed < IDLE_SPEED:
		return "Idle"
	if speed >= RUN_THRESHOLD and _anim.has_animation("Run"):
		return "Run"
	return "Walk"


# ---------------------------------------------------------------------------
# contrato de encenação (BattleStaging)
# ---------------------------------------------------------------------------
#
# Durante o duelo o mundo está pausado e o `_process` daqui não roda: quem move
# e anima este corpo é a `BattleStaging`. Ver o mesmo par em `CreatureActor`
# sobre por que os métodos são chamados por nome e não por tipo.

## Ela já vive apoiada no chão — a origem do nó É o chão, e o corpo sobe pelo
## `position.y` do mesh filho. Zero, portanto, e não meia altura: somar aqui a
## faria flutuar durante o duelo exatamente a meia cápsula do próprio corpo.
func staged_ground_offset() -> float:
	return 0.0


## A marcha imposta pela encenação. Grava em `_speed` em vez de só tocar o
## clipe porque é esse o campo que `_update_clip`, `_face` e o bob leem: deixá-lo
## com a marcha de antes do engate faria ela voltar da pausa andando parada.
func staged_gait(speed: float) -> void:
	_speed = speed
	_update_clip()


## Mesmo motivo do `CreatureActor`: nó pausado não anima, e sem isto o corpo
## dela atravessa a cena congelado no quadro em que o duelo abriu.
func staged_animating(enabled: bool) -> void:
	if _anim != null:
		_anim.process_mode = Node.PROCESS_MODE_ALWAYS if enabled else Node.PROCESS_MODE_INHERIT


## Aura do Despertar Ancestral — o mesmo contrato por nome de `CreatureActor`,
## para quem governa o duelo acender os dois lados sem saber de qual tipo cada
## corpo é.
##
## A luz entra em `_mesh_root`, não no ator: é `_mesh_root` que carrega o
## deslocamento de apoio (`_base_y`) e o bob, então a luz acompanha a
## respiração do corpo em vez de ficar cravada no chão sob ele.
##
## Corpo de cápsula fica só com a luz — sem malha importada não há o que
## inflar. É degradação aceitável: a luz é justamente a metade que se lê de
## longe na câmera isométrica.
func set_awakening_aura(active: bool) -> void:
	if _awakened == active:
		return
	_awakened = active

	if active:
		_aura_shells = ElementPalette.attach_aura(_mesh_instances, element_code)
		_aura_light = ElementPalette.build_aura_light(element_code, size_meters)
		if _mesh_root != null:
			_mesh_root.add_child(_aura_light)
		else:
			add_child(_aura_light)
	else:
		ElementPalette.detach_aura(_aura_shells)
		_aura_shells.clear()
		if _aura_light != null:
			_aura_light.queue_free()
			_aura_light = null


func is_awakened() -> bool:
	return _awakened



func _build_visual() -> void:
	if _mesh_root:
		_mesh_root.queue_free()
	# O corpo antigo vai embora, e com ele as cascas da aura — que são filhas
	# das malhas dele. Baixar a bandeira aqui é o que impede um Despertar
	# trocar de criatura no meio e ficar marcado como aceso sem casca nenhuma.
	set_awakening_aura(false)
	var visual := CreatureActor.build_visual(size_meters, element_code, creature_code, model_url)
	_anim = visual["anim"]
	_mesh_instances = visual["mesh_instances"]
	_mesh_root = Node3D.new()
	_mesh_root.name = "Visual"
	_mesh_root.add_child(visual["mesh"])
	add_child(_mesh_root)

	# A cápsula do CreatureActor sobe meia-altura via `position.y` do próprio
	# actor; aqui, como o mesh vive num nó filho, o offset vai nele. Guardo
	# como base para o bob oscilar em torno.
	_base_y = float(visual["height"]) * 0.5
	_mesh_root.position.y = _base_y


## Trocar a criatura ativa (ex.: quando o jogador manda outra do time à
## frente). Só o corpo é refeito — posição, rastro e marcha continuam, porque
## quem entra assume o lugar de quem saiu em vez de nascer na origem do mundo.
func set_creature(db: BestiaryData, code: String) -> void:
	var c := db.creature(code)
	if c.is_empty():
		return
	creature_code = code
	display_name = str(c["name"])
	element_code = str(c["element"])
	size_meters = float(c["stats"]["sizeMeters"])
	var url: Variant = c.get("modelUrl")
	model_url = url if url is String else ""
	_build_visual()
