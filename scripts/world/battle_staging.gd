class_name BattleStaging
extends Node

## Põe os dois combatentes de frente um para o outro, à distância de duelo, e
## os mantém assim enquanto a batalha dura. O domador entra na composição atrás
## da própria criatura, encarando o adversário junto com ela.
##
## O combate acontece **no mesmo espaço do mapa**, sem corte para arena — então
## o par que o jogador vê durante a luta é o par que estava andando por ali
## meio segundo antes: a companheira atrás do domador e a criatura selvagem
## onde a perseguição parou. Sem encenação, o duelo abre com os dois de costas,
## colados ou a oito metros de distância, e o overlay narra um confronto que a
## imagem não mostra.
##
## ## Por que isto pode mexer na posição direto
##
## O mundo fica **pausado** durante o duelo (`get_tree().paused = true`), e nó
## pausado não processa: a máquina de estados da `CreatureActor` e a trilha da
## `CompanionActor` estão as duas congeladas. Este nó roda com
## `PROCESS_MODE_ALWAYS`, como a câmera, e por isso tem controle exclusivo dos
## dois corpos — não há perseguição nem seguimento disputando o mesmo
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

## Ritmo do reposicionamento. Deliberadamente lento: o ajuste é um acerto de
## postura entre dois bichos que já se viram, não uma corrida. Rápido demais e
## a abertura do duelo vira um salto.
const APPROACH_SPEED := 2.0

## Giro para encarar. Mais rápido que o avanço porque virar a cabeça vem antes
## de dar o passo — se os dois andassem antes de se encarar, a aproximação
## leria como duas peças deslizando de lado.
const TURN_SPEED := 6.0

## Ar entre o corpo do domador e o da criatura dele, além dos dois raios. O
## suficiente para os corpos não se tocarem em projeção ortográfica.
const TRAINER_GAP := 1.2

## Multiplicador de enquadramento sobre o recuo do domador, irmão do
## `DUEL_SPREAD` e pela mesma razão: a distância geométrica põe os dois corpos
## quase encostados, e em projeção ortográfica isso lê como uma peça só. O ×3
## separa o domador da própria criatura o bastante para se ver quem é quem.
##
## Multiplica o recuo inteiro, não só a folga — a mesma escolha do
## `DUEL_SPREAD`, para o afastamento crescer junto com o tamanho da criatura em
## vez de ficar proporcionalmente menor nos bichos grandes.
const TRAINER_SPREAD := 3.0

## Ritmo do domador tomando posição. Acima do `APPROACH_SPEED` de propósito: o
## posto dele é preso à criatura, que também está andando, e com o mesmo ritmo
## ele nunca alcançaria a própria marca enquanto ela avança.
const TRAINER_SPEED := 3.0

var _a: Node3D
var _b: Node3D
var _size_a := 1.0
var _size_b := 1.0

## O domador, e o raio do corpo dele. Opcional: em playtest de cena solta pode
## não haver jogador, e um duelo sem plateia continua sendo um duelo.
var _trainer: Node3D
var _trainer_radius := 0.35

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
func _trainer_spot() -> Vector3:
	return _a.global_position - _axis * trainer_offset()


## Distância corrente entre os dois, no plano. -1 quando um dos lados sumiu —
## a criatura pode ter sido liberada no meio do quadro.
func current_distance() -> float:
	if not _both_alive():
		return -1.0
	return _flat(_b.global_position - _a.global_position).length()


func _process(delta: float) -> void:
	step(delta)


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

	_face(_a, axis, delta)
	# `_b` encara o sentido oposto: os dois olham para o mesmo eixo, de pontas
	# contrárias.
	_face(_b, -axis, delta)

	var error := standoff() - distance
	if absf(error) > TOLERANCE:
		# Metade para cada um, e nunca além do que falta — passar do ponto no
		# mesmo quadro produziria o vaivém clássico de quem persegue com passo
		# fixo.
		var half := absf(error) * 0.5
		var stride := minf(APPROACH_SPEED * delta, half)
		# Erro positivo = estão perto demais e precisam se afastar.
		var apart := 1.0 if error > 0.0 else -1.0

		_a.global_position -= axis * stride * apart
		_b.global_position += axis * stride * apart

	# Depois dos combatentes, e não junto: o posto do domador é medido a partir
	# de onde a criatura dele **está**, então calculá-lo antes deixaria a marca
	# sempre um quadro atrasada em relação a ela.
	_stage_trainer(axis, delta)


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
	if gap > TOLERANCE:
		_trainer.global_position += to_spot / gap * minf(TRAINER_SPEED * delta, gap)

	# Encara o mesmo lado que a criatura dele: os dois olham para o adversário.
	_face(_trainer, axis, delta)


## Vira o nó para o rumo dado. Só mexe no yaw: os dois corpos apoiam o Y em
## regras próprias — a `CreatureActor` sobe meia cápsula, a `CompanionActor`
## fica no chão com o mesh deslocado — e escrever altura aqui desfaria as duas.
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
