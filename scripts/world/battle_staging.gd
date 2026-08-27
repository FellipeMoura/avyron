class_name BattleStaging
extends Node

## Leva os três corpos do duelo até os postos de batalha e os mantém lá
## enquanto a luta dura: os dois combatentes de frente um para o outro, à
## distância de duelo, e o domador atrás da própria criatura, encarando o
## adversário junto com ela.
##
## O combate acontece **no mesmo espaço do mapa**, sem corte para arena — então
## o par que o jogador vê durante a luta é o par que estava andando por ali
## meio segundo antes: a companheira atrás do domador e a criatura selvagem
## onde a perseguição parou. Sem encenação, o duelo abre com os dois de costas,
## colados ou a oito metros de distância, e o overlay narra um confronto que a
## imagem não mostra.
##
## ## Os três ANDAM até o posto — não escorregam até ele
##
## A primeira versão empurrava `global_position` no plano e mais nada. O
## resultado era o oposto do que a encenação existe para produzir: três corpos
## em pose de repouso planando de lado e, desde que o mapa ganhou relevo,
## planando por dentro dele. Três coisas consertam isso, e as três moram aqui
## porque os corpos estão **pausados** e não conseguem se mexer sozinhos:
##
## - **Clipe.** Cada corpo recebe a marcha imposta (`staged_gait`) e escolhe
##   entre parar, andar, correr e nadar com a mesma escada que usa na
##   exploração. E `staged_animating` liga o modo de animar pausado: escolher o
##   clipe não bastava, porque `AnimationPlayer` é pausável — ele ficava
##   selecionado e congelado no quadro zero, e o corpo atravessava a cena numa
##   pose estática.

## - **Rumo.** Enquanto falta caminho, o corpo encara **para onde vai**; só
##   dentro da `SETTLE_BAND` ele gira para o adversário. Encarar o adversário
##   desde o quadro zero era o que fazia a aproximação ler como peça arrastada
##   no tabuleiro — e o afastamento, como moonwalk.
## - **Chão.** Depois de andar no plano, o corpo reencosta no relevo:
##   `terrain.height_at` mais o apoio que cada um declara em
##   `staged_ground_offset`.
##
## ## O relevo, e por que a altura passou a ser assunto daqui
##
## Enquanto o mapa era plano, ignorar o Y era correto — zero em toda parte. Com
## `MapTerrain` deixou de ser: a selvagem nasce num raio de 22 m e a zona plana
## acaba em 16, então a maioria dos duelos começa em ladeira. Empurrar só X/Z
## ali enterra o corpo na colina, e como a física está pausada ninguém
## despenetra durante o duelo. O jogador e a selvagem são `CharacterBody3D`: no
## `paused = false` o `move_and_slide` acha a cápsula funda dentro do
## `HeightMapShape3D` e a expulsa — era isso que prendia o jogador no solo ou o
## arremessava. Perto da borda era pior: o posto do domador é derivado para
## FORA do par, e com uma selvagem na borda de spawn ele caía além dos ±30 m da
## malha, onde não há chão nenhum. Daí `MapTerrain.clamp_to_bounds`.
##
## **Sem terreno injetado nada disso roda e o Y fica intocado** — o contrato
## antigo. É o que mantém a bancada de `Node3D` solto da suíte medindo
## geometria pura, sem ter de conhecer relevo.
##
## ## Por que isto pode mexer na posição direto
##
## O mundo fica **pausado** durante o duelo (`get_tree().paused = true`), e nó
## pausado não processa: a máquina de estados da `CreatureActor` e a trilha da
## `CompanionActor` estão as duas congeladas. Este nó roda com
## `PROCESS_MODE_ALWAYS`, como a câmera, e por isso tem controle exclusivo dos
## três corpos — não há perseguição nem seguimento disputando o mesmo
## `global_position`. É o que dispensa física, colisão e trava de prioridade.
##
## ## A correção é simétrica, e é isso que preserva o lugar do encontro
##
## Cada um anda **metade** do erro de distância. Duas consequências caem de
## graça: o ponto médio entre os dois não se move, então a briga acontece onde
## eles se encontraram em vez de escorregar para o lado do mais lento; e nenhum
## dos dois faz todo o trabalho, que é o que faria a cena ler como "um foge" ou
## "um avança" em vez de "os dois se medem".
##
## O domador fica **de fora** dessa simetria. O posto dele é derivado da posição
## da criatura, não negociado com ninguém — puxá-lo para o cálculo faria o ponto
## do encontro escorregar na direção de quem está só assistindo.

## Folga fixa entre as bordas dos dois corpos, em metros. Constante de
## apresentação: é enquadramento, não balanceamento — nenhum número daqui muda
## dano, captura ou qualquer coisa que um designer ajustaria no bestiário.
const BASE_GAP := 0.8

## Parcela da folga que cresce com o tamanho somado dos dois. Um par de
## Arthropleura precisa de mais ar entre os corpos que um par de trilobitas
## para a mesma leitura de "frente a frente" — a folga constante sozinha
## deixaria os grandes espremidos e os pequenos em campos opostos.
const GAP_PER_METER := 0.35

## Multiplicador de enquadramento sobre a distância geométrica.
##
## A soma dos raios mais a folga dá o ponto em que os dois corpos *apenas* se
## livram — geometricamente correto e cênicamente errado: lido de cima, em
## projeção ortográfica, um par nessa distância parece agarrado, não em duelo.
## O 2,5 abre o vão até a leitura de "os dois se mediram e pararam", e foi
## escolhido olhando a cena, não derivado de nada.
##
## Multiplica o resultado inteiro, e os limites abaixo acompanham: aplicá-lo
## só à folga faria o par grande crescer proporcionalmente menos que o pequeno,
## que é o oposto do que a distância precisa fazer.
const DUEL_SPREAD := 2.5

## Limites do afastamento, já na escala do `DUEL_SPREAD`. O piso impede corpos
## sobrepostos quando os dois são minúsculos; o teto impede que um par gigante
## saia do enquadramento de 12 unidades da câmera ortográfica.
const MIN_STANDOFF := 2.5
const MAX_STANDOFF := 17.5

## Zona morta em torno da distância ideal. Sem ela os dois corrigiriam frações
## de milímetro para sempre, e o resultado seria um tremor a dois — o mesmo
## defeito que `CompanionActor.STOP_DISTANCE` existe para evitar.
const TOLERANCE := 0.12

## Ritmo do reposicionamento, proporcional ao que falta andar — o mesmo
## controlador que a `CompanionActor` usa para seguir o jogador
## (`CATCH_UP_GAIN`), e pelo mesmo motivo: velocidade fixa obriga a escolher
## entre um acerto de meio metro que demora e uma travessia de dez que vira
## salto. Com o ganho, quem está longe parte correndo e chega andando, e é a
## própria desaceleração que produz a troca de clipe `Run` → `Walk` → `Idle`
## sem ninguém orquestrar nada.
##
## O piso mantém o último palmo andando em vez de derreter em câmera lenta; o
## teto é o que separa "tomar posição" de "atravessar o mapa teleportado".
const APPROACH_GAIN := 2.6
const APPROACH_SPEED_MIN := 0.9
const APPROACH_SPEED_MAX := 4.0

## Giro para encarar. Mais rápido que o avanço porque virar a cabeça vem antes
## de dar o passo — se os dois andassem antes de se encarar, a aproximação
## leria como duas peças deslizando de lado.
const TURN_SPEED := 6.0

## Distância a partir da qual o corpo encara o RUMO em vez do adversário.
##
## Dentro dela o que falta é um acerto de postura e o corpo já olha para quem
## vai enfrentar; fora dela é caminhada, e um corpo que caminha olhando para o
## lado (ou de ré) denuncia que quem o move não é ele. O afastamento paga o
## preço de dar as costas por alguns metros — é o único rumo honesto com um
## clipe de locomoção que só anda para frente.
const SETTLE_BAND := 1.0

## Ar entre o corpo do domador e o da criatura dele, além dos dois raios. O
## suficiente para os corpos não se tocarem em projeção ortográfica.
const TRAINER_GAP := 1.2

## Multiplicador de enquadramento sobre o recuo do domador, irmão do
## `DUEL_SPREAD` e pela mesma razão: a distância geométrica põe os dois corpos
## quase encostados, e em projeção ortográfica isso lê como uma peça só — o
## multiplicador abre esse vão até separar visualmente quem é quem.
##
## Era ×3; reduzido pela metade (×1.5) a pedido, pra aproximar o domador da
## própria criatura em combate.
##
## Multiplica o recuo inteiro, não só a folga — a mesma escolha do
## `DUEL_SPREAD`, para o afastamento crescer junto com o tamanho da criatura em
## vez de ficar proporcionalmente menor nos bichos grandes.
const TRAINER_SPREAD := 1.5

## Ritmo do domador tomando posição, no mesmo esquema proporcional dos
## combatentes. O teto é a marcha de exploração dele: é a velocidade para a
## qual o clipe `Run` do rig foi escolhido, então tomar posição correndo lê
## igual a correr pelo mapa. Ganho maior que o do par porque o posto dele é
## preso à criatura, que também está andando — com o mesmo ritmo ele nunca
## alcançaria a própria marca enquanto ela avança.
const TRAINER_GAIN := 3.0
const TRAINER_SPEED_MIN := 1.0
const TRAINER_SPEED_MAX := PlayerController.WALK_SPEED

var _a: Node3D
var _b: Node3D
var _size_a := 1.0
var _size_b := 1.0

## O domador, e o raio do corpo dele. Opcional: em playtest de cena solta pode
## não haver jogador, e um duelo sem plateia continua sendo um duelo.
var _trainer: Node3D
var _trainer_radius := 0.35

## Relevo do mapa, injetado por quem monta a encenação. Nulo (bancada de teste)
## desliga apoio no chão e limite de borda — ver a docstring sobre por que o
## contrato antigo continua valendo sem ele.
var terrain: MapTerrain

## Eixo do confronto no último quadro em que ele foi mensurável. Serve de
## retrato para o caso degenerado: se os dois corpos ocuparem exatamente o
## mesmo ponto no plano, a direção entre eles não existe, e sem uma memória o
## afastamento escolheria um rumo aleatório por quadro.
var _axis := Vector3.FORWARD


## Monta a encenação para um par. `size_*` são os tamanhos de jogo em metros —
## vêm do bundle, e é deles que sai a distância.
static func create(a: Node3D, size_a: float, b: Node3D, size_b: float) -> BattleStaging:
	var s := BattleStaging.new()
	s.name = "BattleStaging"
	s._a = a
	s._b = b
	s._size_a = size_a
	s._size_b = size_b
	# Roda com o mundo parado, como a câmera. Sem isto a encenação inteira
	# ficaria congelada junto com o que ela deveria encenar.
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	return s


## Distância alvo entre os **centros** dos dois corpos.
##
## Somar os raios é o que faz a conta funcionar em escala real: o vão que se vê
## é sempre `gap`, independentemente de o par ser dois trilobitas de 15 cm ou
## dois Arthropleura de 2,5 m. Medir de centro a centro sem os raios daria
## bichos grandes sobrepostos e pequenos distantes, com o mesmo número.
static func standoff_for(size_a: float, size_b: float) -> float:
	var gap := BASE_GAP + (size_a + size_b) * GAP_PER_METER
	var centers := CreatureActor.capsule_radius(size_a) \
		+ CreatureActor.capsule_radius(size_b) + gap
	return clampf(centers * DUEL_SPREAD, MIN_STANDOFF, MAX_STANDOFF)


## Põe o domador na cena, atrás da criatura dele. `radius` é o raio do corpo
## dele — vem da cena, não de uma constante daqui, para não haver duas medidas
## do mesmo jogador.
func set_trainer(node: Node3D, radius: float) -> void:
	_trainer = node
	_trainer_radius = maxf(0.0, radius)


func standoff() -> float:
	return standoff_for(_size_a, _size_b)


## Distância entre o domador e a criatura dele, no eixo do confronto. Atrás
## dela, e fora do corpo dela: quem assiste não ocupa o lugar de quem luta.
func trainer_offset() -> float:
	var centers := CreatureActor.capsule_radius(_size_a) + _trainer_radius + TRAINER_GAP
	return centers * TRAINER_SPREAD


## Quanto falta para o domador chegar ao posto dele. Zero sem domador — sem
## plateia não há erro a corrigir, e quem espera a cena assentar precisa que
## esse caso conte como assentado em vez de esperar para sempre.
func trainer_error() -> float:
	if _trainer == null or not is_instance_valid(_trainer) or not _both_alive():
		return 0.0
	return _flat(_trainer_spot() - _trainer.global_position).length()


## O posto do domador: atrás da criatura dele, no eixo do confronto. `_axis`
## aponta de `_a` para `_b`, então recuar é subtrair.
##
## O limite de borda entra AQUI, e não só na hora de escrever a posição, para o
## erro ser medido contra um ponto alcançável: um posto fora do mapa deixaria o
## domador empurrando a parede para sempre, correndo no lugar, e
## `trainer_error` nunca zeraria — quem espera a cena assentar esperaria a
## batalha inteira.
func _trainer_spot() -> Vector3:
	var spot := _a.global_position - _axis * trainer_offset()
	return terrain.clamp_to_bounds(spot) if terrain else spot


## Distância corrente entre os dois, no plano. -1 quando um dos lados sumiu —
## a criatura pode ter sido liberada no meio do quadro.
func current_distance() -> float:
	if not _both_alive():
		return -1.0
	return _flat(_b.global_position - _a.global_position).length()


func _process(delta: float) -> void:
	step(delta)


## Enquanto esta encenação estiver na árvore, os corpos que ela move animam
## mesmo com o mundo pausado — e voltam ao normal quando ela sai.
##
## `AnimationPlayer` é pausável como qualquer nó, então escolher o clipe certo
## não bastava: ele ficava selecionado e **congelado no quadro zero**, e os três
## corpos atravessavam a cena numa pose estática. Medido antes da correção:
## `current_animation_position` = 0,000 em todos os quadros da caminhada.
##
## `_exit_tree` roda no `queue_free` da encenação, que acontece ANTES de o mundo
## despausar (ver `EncounterDirector._on_duel_closed`) — então nenhum corpo fica
## com o modo ligado depois que ele volta a andar sozinho.
func _enter_tree() -> void:
	_set_animating(true)


func _exit_tree() -> void:
	_set_animating(false)


func _set_animating(enabled: bool) -> void:
	for node in [_a, _b, _trainer]:
		if node != null and is_instance_valid(node) and node.has_method("staged_animating"):
			node.call("staged_animating", enabled)



## Um passo da encenação. Público para os testes headless: medir convergência
## quadro a quadro por API é mais estável que esperar o motor chamar `_process`
## num tempo que o teste não controla.
func step(delta: float) -> void:
	if not _both_alive() or delta <= 0.0:
		return

	var separation := _flat(_b.global_position - _a.global_position)
	var distance := separation.length()

	# Eixo mensurável vira a memória; degenerado reaproveita a última. É o que
	# impede dois corpos exatamente sobrepostos de escolherem um rumo diferente
	# a cada quadro e vibrarem no lugar.
	if distance > 0.001:
		_axis = separation / distance
	var axis := _axis

	var error := standoff() - distance
	# Metade para cada um: é a simetria que preserva o ponto do encontro.
	var remaining := absf(error) * 0.5
	var move_a := Vector3.ZERO
	var move_b := Vector3.ZERO
	if absf(error) > TOLERANCE:
		# Nunca além do que falta — passar do ponto no mesmo quadro produziria
		# o vaivém clássico de quem persegue com passo fixo.
		var speed := clampf(remaining * APPROACH_GAIN, APPROACH_SPEED_MIN, APPROACH_SPEED_MAX)
		var stride := minf(speed * delta, remaining)
		# Erro positivo = estão perto demais e precisam se afastar.
		var apart := 1.0 if error > 0.0 else -1.0
		move_a = -axis * stride * apart
		move_b = axis * stride * apart
	else:
		remaining = 0.0

	# `_b` encara o sentido oposto: os dois olham para o mesmo eixo, de pontas
	# contrárias.
	_advance(_a, move_a, remaining, axis, delta)
	_advance(_b, move_b, remaining, -axis, delta)

	# Depois dos combatentes, e não junto: o posto do domador é medido a partir
	# de onde a criatura dele **está**, então calculá-lo antes deixaria a marca
	# sempre um quadro atrasada em relação a ela.
	_stage_trainer(axis, delta)


## Um corpo dando um passo da encenação: anda, apoia, encara e anima.
##
## `remaining` é quanto ainda falta ANDAR — não o que foi andado neste quadro.
## É essa medida, e não a passada, que separa "ainda estou indo" de "cheguei":
## a passada encolhe junto com a desaceleração e cruzaria a `SETTLE_BAND` cedo
## demais, girando o corpo para o adversário a meio caminho.
func _advance(node: Node3D, offset: Vector3, remaining: float, opponent: Vector3, delta: float) -> void:
	var applied := _place(node, offset)

	var facing := opponent
	if remaining > SETTLE_BAND and applied.length_squared() > 0.0:
		facing = applied.normalized()
	_face(node, facing, delta)

	_gait(node, applied.length() / delta)


## Leva o domador para trás da própria criatura, encarando o adversário.
##
## Ele não entra na correção simétrica dos combatentes de propósito. O posto
## dele é derivado, não negociado: puxá-lo para o cálculo faria o ponto do
## encontro escorregar na direção de quem está só assistindo.
func _stage_trainer(axis: Vector3, delta: float) -> void:
	if _trainer == null or not is_instance_valid(_trainer):
		return

	# `_axis` já foi atualizado neste quadro, então `_trainer_spot` e o `axis`
	# recebido descrevem o mesmo eixo.
	var to_spot := _flat(_trainer_spot() - _trainer.global_position)
	var gap := to_spot.length()
	var offset := Vector3.ZERO
	if gap > TOLERANCE:
		var speed := clampf(gap * TRAINER_GAIN, TRAINER_SPEED_MIN, TRAINER_SPEED_MAX)
		offset = to_spot / gap * minf(speed * delta, gap)

	# Encara o mesmo lado que a criatura dele — os dois olham para o adversário
	# — assim que o posto está ao alcance; antes disso, para onde ele vai.
	_advance(_trainer, offset, gap, axis, delta)


## Escreve a posição do corpo: anda no plano, respeita a borda do mapa e
## reencosta no chão. Devolve o deslocamento **de fato aplicado**, que é o que
## alimenta o clipe e o rumo.
##
## A diferença importa no limite do mapa: um corpo empurrado contra a borda
## recebe deslocamento zero de volta e, com ele, marcha zero — para parado
## encarando o adversário em vez de correr no lugar contra uma parede.
##
## Roda mesmo com deslocamento zero de propósito: um corpo que engatou o duelo
## já enterrado numa colina (a companheira não tem física para tirá-lo de lá)
## se conserta no primeiro quadro da encenação em vez de ficar assim a luta
## inteira.
func _place(node: Node3D, offset: Vector3) -> Vector3:
	var before := node.global_position
	var target := before + offset
	if terrain:
		target = terrain.clamp_to_bounds(target)
		target.y = terrain.height_at(target) + _ground_offset(node)
	node.global_position = target
	return _flat(target - before)


## Quanto a origem do corpo fica acima do chão. Vem do próprio corpo porque as
## três regras divergem — a `CreatureActor` sobe meia cápsula, a
## `CompanionActor` fica no chão com o mesh deslocado, o jogador apoia no centro
## da cápsula de colisão — e a encenação não deve conhecer nenhuma delas.
##
## `call` por nome, e não chamada tipada: `_a`/`_b`/`_trainer` são `Node3D`, e a
## bancada da suíte monta a geometria com `Node3D` solto de propósito. Sem o
## método, apoio zero — que com `terrain` nulo nem chega a ser consultado.
func _ground_offset(node: Node3D) -> float:
	if node.has_method("staged_ground_offset"):
		return float(node.call("staged_ground_offset"))
	return 0.0


## Entrega a marcha imposta ao corpo, que escolhe o clipe com a mesma escada
## que usa quando anda sozinho. Silencioso para quem não implementa o contrato.
func _gait(node: Node3D, speed: float) -> void:
	if node.has_method("staged_gait"):
		node.call("staged_gait", speed)


## Vira o nó para o rumo dado. Só mexe no yaw: a altura é assunto do `_place`,
## e escrever rotação em X/Z deitaria corpos que só sabem ficar de pé.
func _face(node: Node3D, direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	# A frente de um nó no Godot é -Z. Negar as duas componentes alinha o eixo
	# certo; `atan2(x, z)` deixaria o corpo de costas para o adversário.
	var target_yaw := atan2(-direction.x, -direction.z)
	node.rotation.y = lerp_angle(
		node.rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _both_alive() -> bool:
	return _a != null and is_instance_valid(_a) \
		and _b != null and is_instance_valid(_b)


## Achata no plano do chão. O afastamento é uma questão de piso: incluir o Y
## faria um par de alturas diferentes se afastar horizontalmente para compensar
## uma diferença vertical que ninguém quer corrigir.
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
