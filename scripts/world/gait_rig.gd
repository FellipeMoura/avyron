class_name GaitRig
extends Node3D

## A máquina de marcha de um corpo humano: dada a velocidade e o meio, qual
## clipe toca.
##
## Separada da montagem (`CharacterRig`) desde 2026-09-07, quando o jogo teve
## por dez dias dois corpos humanos de montagem diferente — o jogador num
## `.glb` fechado do Meshy, os NPCs no kit — que precisavam responder igual.
## Desde 2026-09-17 todo humano é kit outra vez, mas a divisão ficou porque
## continua verdadeira: o que a escada precisa de um corpo é só o VOCABULÁRIO
## de clipes (`Idle`/`Walk`/`Run`/`Swim`/`Swim_Idle`/`Harvest`) e o número
## medido no próprio clipe de nado (`swim_lift`); montagem é outro assunto. O
## `CLAUDE.md` exige que a escada seja uma só ("a escolha do clipe é sempre
## uma escada de marcha e meio, nunca um literal fixo no chamador"), e é aqui
## que ela mora. Os helpers estáticos (`find_skeleton`, `find_animation_player`,
## `mark_looping`) são reusados pelos atores de criatura.

## Clipes contínuos, que devem tocar em loop. O importador de glTF não marca
## loop em nada, então quem monta o corpo marca — e só estes. `Harvest`,
## `Throw`, `Attack` e `Death` ficam de fora de propósito: são gesto único, e
## quem precisar repetir um deles relança o clipe explicitamente (ver
## `_advance_mining_loop`).
##
## `Idle_FoldArms` e `Fixing_Kneeling` entraram em 2026-09-20 como poses de
## espera dos NPCs da vila (comerciante e ferreiro): o primeiro é loop de
## autoria da UAL2 (no arquivo chama `Idle_FoldArms_Loop`; o importador glTF
## do Godot CORTA o sufixo `_Loop`, que é a convenção dele para loop — o nome
## aqui é o que a biblioteca fundida tem, medido por sonda, não o do
## manifest), o segundo é laço de trabalho — mesma classe de `Sit`/`Push`.
## Fora desta lista o clipe congelaria no último quadro e `current_animation`
## viraria `""` (a lição do `HitReact`, no CLAUDE.md).
const LOOPED_CLIPS := [
	"Idle", "Walk", "Run", "Sprint", "Talk", "Sit", "Sit_Talk",
	"Crouch", "Crouch_Walk", "Swim", "Swim_Idle", "Jump_Idle",
	"Cast_Idle", "Push", "Walk_Carry", "Dance",
	"Idle_FoldArms", "Fixing_Kneeling",
]

## Marcha a partir da qual o corpo corre em vez de andar, em m/s. Constante de
## apresentação — é a transição andar/correr de um humano real (~2 m/s), não um
## número que um designer ajuste no bestiário.
const RUN_THRESHOLD := 2.2

## Abaixo disto o corpo está "parado" para toda a máquina de marcha — jogador
## e NPCs por igual. Pública porque `PlayerController.is_moving()` e o botão
## de minerar de `WorldRoot` precisam concordar com esta escada sobre o que é
## "parado"; um segundo `0.05` escrito à mão em outro arquivo divergiria no
## dia em que só um dos dois fosse ajustado.
const IDLE_THRESHOLD := 0.05

## Cadência do ciclo de `Walk` (`speed_scale` do `AnimationPlayer`), separada
## do clipe e da velocidade real do corpo — exatamente o ajuste que o
## comentário de `PlayerController.WALK_SPEED` reserva para quando sobrar
## deslize depois de clipe e velocidade corrigidos. `1.0` tocava o ciclo no
## ritmo em que ele foi autorado, mais lento que o pé precisa varrer o chão na
## marcha atual do jogo — o pé plantado parece arrastar para trás enquanto o
## corpo avança. Constante de apresentação (ver `CLAUDE.md`, "velocidade de
## giro da câmera" é a mesma classe de exceção): não descreve nada físico, só
## calibra o clipe contra a marcha do jogo, e é candidata a reajuste por
## olho — não por medição — se a próxima rodada de playtest ainda achar pouco
## ou demais.
const WALK_CADENCE := 1.3

## Clipe de mineração. Fica de FORA de `LOOPED_CLIPS` de propósito: aquela
## lista é o contrato de loop de TODO corpo humano, e marcar loop nela vazaria
## para qualquer uso futuro do mesmo clipe (uma cena de colheita que precise de
## um único gesto, por exemplo) herdar looping sem pedir. O "loop" aqui é
## sintético e escopado: `_advance_mining_loop` relança o clipe do zero quando
## o `AnimationPlayer` termina, e só enquanto `_mining` for true.
const MINE_CLIP := "Harvest"

## Tempo de entrar e sair da flutuação do nado. Casado com o crossfade de clipe
## (0,2 s) e um pouco maior: o corpo tem de acabar de deitar antes de estar todo
## no alto, senão ele sobe de pé e depois deita, que lê como elevador.
const SWIM_BLEND_TIME := 0.35

## Quanto o corpo do nadador sobe em relação aos próprios pés, em metros,
## enquanto toca `Swim`.
##
## É medida do CLIPE, não do sistema, e por isso é campo de instância em vez de
## constante daqui: compensa o quanto o `Swim` daquele corpo específico foi
## autorado acima ou abaixo da origem do rig. Zero = o clipe já nasce na altura
## certa e não há o que compensar, que é o caso do corpo do jogador.
var swim_lift := 0.0

## O mesmo, para `Swim_Idle`. Um campo por clipe porque os dois foram autorados
## em alturas diferentes no MESMO corpo: na UAL o boiador pende 0,88 m mais
## fundo que o nadador (ver `CharacterRig.SWIM_IDLE_LIFT`), e uma compensação
## única deixaria um dos dois no leito. Zero no corpo do jogador, como
## `swim_lift`.
var swim_idle_lift := 0.0

var _anim: AnimationPlayer
## O nó do corpo, que sobe quando ele nada (ver `swim_lift`/`swim_idle_lift`).
var _body: Node3D
var _swimming := false
var _mining := false


## Troca de clipe: silencia quando o clipe não existe, não reinicia o que já
## toca.
func play_clip(clip: String) -> void:
	if _anim == null:
		return
	if _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.2)


func has_clip(clip: String) -> bool:
	return _anim != null and _anim.has_animation(clip)


## Escolhe o clipe pela marcha real e pelo meio: parado, andando, correndo ou
## nadando.
##
## Era binário (`Idle`/`Walk`) e por isso o jogador deslizava: ele se move a
## `PlayerController.WALK_SPEED` = 5,2 m/s, que é marcha de CORRIDA (humano
## andando faz ~1,4 m/s), e o ciclo de `Walk` foi calibrado a 4,0 antes de a
## velocidade subir 30%. Nenhum blend cobre uma defasagem dessa ordem — o que
## faltava era o clipe certo, não um ajuste de mistura.
##
## A escada fica aqui, e não no chamador, porque humano é UM sistema de marcha
## mesmo tendo dois corpos: um NPC que um dia passear a 1,5 m/s ganha o `Walk`
## pela mesma chamada que dá `Run` ao jogador. Trocar o literal por "Run" teria
## tirado o andar do sistema inteiro para consertar um corpo só.
##
## `swimming` vem de fora porque quem sabe onde a água está é o mundo, não o
## corpo: no PZ-01 é `MapTerrain.submerged`, e é o estado NORMAL da exploração
## — o mapa é o leito de um mar, e só o platô da costa e a ilha são secos.
##
## `allow_run` existe para o corpo que quer animar `Walk` mesmo acima de
## `RUN_THRESHOLD` — desde 2026-09-17 é o caso do jogador (ver
## `PlayerController.WALK_SPEED`), que se move na marcha de corrida mas anima
## como se andasse, por decisão de produto. `false` só desliga o RAMO de
## `Run`; a escada `Idle`/`Walk` e o nado continuam iguais, e por curto-
## circuito de `and` nem `has_clip("Run")` chega a ser consultado.
func update_motion(
	speed: float, swimming: bool = false, mining: bool = false,
	idle_threshold: float = IDLE_THRESHOLD, allow_run: bool = true
) -> void:
	# Guardado antes de qualquer saída: é `_process` quem faz o corpo subir, e
	# ele precisa saber do meio mesmo que o clipe de nado não exista.
	_swimming = swimming
	_mining = mining

	# Mineração tem prioridade sobre a escada normal. Quem chama garante que
	# só liga `mining` com o corpo parado (`WorldRoot` cancela a sessão ao
	# detectar movimento antes de este método ser chamado de novo), então não
	# precisa entrar como mais um ramo dentro da escada de marcha.
	if mining and has_clip(MINE_CLIP):
		_reset_cadence()
		play_clip(MINE_CLIP)
		return

	if swimming:
		# Parado dentro d'água o corpo boia (`Swim_Idle`); em movimento, nada
		# (`Swim`). Até 2026-09-07 era `Swim` nas duas marchas, e não por
		# descuido: o único `Swim_Idle` que existia era o da UAL, pose de boiar
		# na SUPERFÍCIE pendurada 1,42 m abaixo da origem do rig — trocar de
		# clipe a cada parada fazia o corpo subir e descer quase um metro, e a
		# coluna d'água do PZ-01 (1,65 m) não tem folga para levantá-lo. O
		# corpo do jogador trouxe um `Swim_Idle` DE PÉ (medido: y de +0,19 a
		# +1,60, quadril em +1,0, contra +0,6 no `Swim`), e a escada passou a
		# alternar. A altura de cada clipe continua sendo medida do corpo, não
		# da escada — ver `swim_lift`/`swim_idle_lift` e `_advance_float`.
		# Corpo sem `Swim_Idle` continua dando braçada no lugar, que é o que um
		# submerso faz; corpo sem `Swim` nenhum cai para a escada seca.
		if speed < idle_threshold and has_clip("Swim_Idle"):
			_reset_cadence()
			play_clip("Swim_Idle")
			return
		if has_clip("Swim"):
			_reset_cadence()
			play_clip("Swim")
			return

	if speed < idle_threshold:
		_reset_cadence()
		play_clip("Idle")
		return
	# `has_clip` antes de pedir `Run`: `play_clip` silencia no clipe ausente,
	# e silenciar aqui deixaria o corpo preso no clipe anterior em vez de cair
	# para o `Walk`, que todo corpo humano do jogo tem.
	if allow_run and speed >= RUN_THRESHOLD and has_clip("Run"):
		_reset_cadence()
		play_clip("Run")
		return
	if _anim != null:
		_anim.speed_scale = WALK_CADENCE
	play_clip("Walk")


## Devolve o `AnimationPlayer` ao ritmo autorado. Todo ramo que NÃO é `Walk`
## passa por aqui antes de tocar o próprio clipe — sem isto, `WALK_CADENCE`
## vazaria para `Idle`/`Run`/`Swim`/`Harvest` na primeira vez que o corpo
## andasse e ficaria acelerado para sempre, porque `speed_scale` é do
## `AnimationPlayer` inteiro, não do clipe.
func _reset_cadence() -> void:
	if _anim != null:
		_anim.speed_scale = 1.0


## Deixa este corpo animar mesmo com a árvore pausada.
##
## Existe porque `AnimationPlayer` é pausável como qualquer nó: durante a
## abertura do duelo o mundo para, e o clipe escolhido pela encenação ficava
## **selecionado mas congelado no quadro zero** — os três corpos atravessavam a
## cena numa pose estática, que é exatamente o deslize que a encenação existe
## para acabar. Medido: `current_animation_position` = 0,000 em todos os
## quadros da caminhada.
##
## Ligado só enquanto a encenação é dona do corpo, e não sempre, de propósito:
## numa tela de loja o mundo congela e uma criatura presa no meio do `Walk`
## fica *parada* — ligar isto o tempo todo a faria andar no lugar, sem sair do
## lugar, que é pior.
##
## O modo cascateia para o `AnimationPlayer` filho e para o `_process` daqui,
## que é quem move a flutuação do nado.
func animate_while_paused(enabled: bool) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS if enabled else Node.PROCESS_MODE_INHERIT


func _process(delta: float) -> void:
	_advance_float(delta)
	_advance_mining_loop()


## Sobe o corpo quando ele nada, e o devolve ao chão quando ele sai da água.
##
## A altura persegue a cota do clipe de nado que está tocando — `swim_lift` no
## `Swim`, `swim_idle_lift` no `Swim_Idle` — e zero fora d'água. A transição
## entre as três é sempre interpolada, à velocidade que cruza a maior das
## cotas em `SWIM_BLEND_TIME`: um deslocamento menor (parar de nadar e boiar)
## leva proporcionalmente menos, e casa com o crossfade do clipe do mesmo
## jeito que a borda de entrar e sair d'água já casava.
##
## Sai cedo com as duas cotas zeradas em vez de escrever `position.y = 0.0`
## todo quadro: o corpo cujos clipes já nascem na altura certa não tem
## flutuação nenhuma para animar, e quem quiser deslocar esse `_body` por outro
## motivo não deve encontrar este método pisando no valor.
func _advance_float(delta: float) -> void:
	if _body == null or (is_zero_approx(swim_lift) and is_zero_approx(swim_idle_lift)):
		return
	var target := 0.0
	if _swimming:
		var floating := _anim != null and _anim.current_animation == "Swim_Idle"
		target = swim_idle_lift if floating else swim_lift
	var rate := maxf(swim_lift, swim_idle_lift) / SWIM_BLEND_TIME
	_body.position.y = move_toward(_body.position.y, target, rate * delta)


## Relança `Harvest` do início quando ele termina. `Harvest` não está em
## `LOOPED_CLIPS` (ver o comentário da constante `MINE_CLIP`), então o
## `AnimationPlayer` para e trava no último quadro sozinho — isto o mantém em
## movimento enquanto a sessão de mineração durar. Só dispara com `_mining`
## true; quando a sessão acaba, `update_motion` já é chamado de novo com
## `mining = false` no próximo `_physics_process` do jogador, e a escada
## normal assume sozinha.
func _advance_mining_loop() -> void:
	if not _mining or _anim == null:
		return
	if _anim.current_animation == MINE_CLIP and not _anim.is_playing():
		# Blend 0.0: um crossfade de 0.2s a cada repetição do MESMO clipe
		# produziria um "respiro" visível toda vez que ele reinicia.
		_anim.play(MINE_CLIP, 0.0)


## Marca loop nos clipes contínuos — ver `LOOPED_CLIPS` sobre por que não são
## todos. Mexe no recurso `Animation` da instância, não no arquivo.
static func mark_looping(player: AnimationPlayer) -> void:
	for clip in player.get_animation_list():
		if String(clip) in LOOPED_CLIPS:
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := find_animation_player(child)
		if found != null:
			return found
	return null


static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := find_skeleton(child)
		if found != null:
			return found
	return null
