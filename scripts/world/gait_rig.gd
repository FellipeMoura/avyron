class_name GaitRig
extends Node3D

## A máquina de marcha de um corpo humano: dada a velocidade e o meio, qual
## clipe toca.
##
## Existe porque desde 2026-09-07 há DOIS corpos humanos no jogo, montados de
## formas incompatíveis, que precisam responder igual:
##
## - `CharacterRig` — os NPCs. Montado em runtime a partir de uma receita de
##   peças do kit de personagens, com as bibliotecas UAL re-endereçadas para o
##   esqueleto resultante.
## - `PlayerRig` — o jogador. Um `.glb` fechado do Meshy AI, com esqueleto e
##   clipes próprios, sem retarget nenhum.
##
## O que os dois têm em comum não é a montagem — é o VOCABULÁRIO de clipes
## (`Idle`/`Walk`/`Run`/`Swim`/`Harvest`, garantido na conversão pelo bestiário)
## e a escada que escolhe entre eles. O `CLAUDE.md` já exigia que essa escada
## fosse uma só ("a escolha do clipe é sempre uma escada de marcha e meio,
## nunca um literal fixo no chamador"); com dois corpos ela precisou de um dono
## em vez de uma cópia por corpo. A subclasse traz a montagem e o número medido
## no PRÓPRIO clipe (`swim_lift`); tudo o mais é daqui.

## Clipes contínuos, que devem tocar em loop. O importador de glTF não marca
## loop em nada, então quem monta o corpo marca — e só estes. `Harvest`,
## `Throw`, `Attack` e `Death` ficam de fora de propósito: são gesto único, e
## quem precisar repetir um deles relança o clipe explicitamente (ver
## `_advance_mining_loop`).
const LOOPED_CLIPS := [
	"Idle", "Walk", "Run", "Sprint", "Talk", "Sit", "Sit_Talk",
	"Crouch", "Crouch_Walk", "Swim", "Swim_Idle", "Jump_Idle",
	"Cast_Idle", "Push", "Walk_Carry", "Dance",
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

## Quanto o corpo do nadador sobe em relação aos próprios pés, em metros.
##
## É medida do CLIPE, não do sistema, e por isso é campo de instância em vez de
## constante daqui: compensa o quanto o `Swim` daquele corpo específico foi
## autorado acima ou abaixo da origem do rig. Zero = o clipe já nasce na altura
## certa e não há o que compensar, que é o caso do corpo do jogador.
var swim_lift := 0.0

var _anim: AnimationPlayer
## O nó do corpo, que sobe quando ele nada (ver `swim_lift`).
var _body: Node3D
var _swimming := false
var _float_blend := 0.0
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
func update_motion(
	speed: float, swimming: bool = false, mining: bool = false,
	idle_threshold: float = IDLE_THRESHOLD
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
		play_clip(MINE_CLIP)
		return

	if swimming and has_clip("Swim"):
		# `Swim` também parado, de propósito. Os dois corpos trazem um
		# `Swim_Idle`, mas ele é pose de boiar na SUPERFÍCIE — no corpo UAL o
		# nadador pendura 1,41 m abaixo da origem do rig, contra 0,54 m do
		# `Swim`. Alternar entre os dois obrigaria o corpo a subir e descer
		# quase um metro a cada parada, e os pés do boiador entrariam no leito,
		# porque a coluna de água do PZ-01 não tem essa folga. Quem paralisa
		# embaixo da água continua dando braçada para ficar no lugar, o que é o
		# que um corpo submerso faz.
		play_clip("Swim")
		return

	if speed < idle_threshold:
		play_clip("Idle")
		return
	# `has_clip` antes de pedir `Run`: `play_clip` silencia no clipe ausente,
	# e silenciar aqui deixaria o corpo preso no clipe anterior em vez de cair
	# para o `Walk`, que todo corpo humano do jogo tem.
	if speed >= RUN_THRESHOLD and has_clip("Run"):
		play_clip("Run")
		return
	play_clip("Walk")


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
## Só a BORDA é interpolada — entrar e sair da água. Dentro do nado a altura é
## fixa de propósito: um único clipe de locomoção submersa, uma única cota, e
## nenhum salto vertical no meio da exploração.
##
## Sai cedo com `swim_lift` zerado em vez de escrever `position.y = 0.0` todo
## quadro: o corpo cujo clipe já nasce na altura certa não tem flutuação
## nenhuma para animar, e quem quiser deslocar esse `_body` por outro motivo
## não deve encontrar este método pisando no valor.
func _advance_float(delta: float) -> void:
	if _body == null or is_zero_approx(swim_lift):
		return
	_float_blend = move_toward(_float_blend, 1.0 if _swimming else 0.0, delta / SWIM_BLEND_TIME)
	_body.position.y = swim_lift * _float_blend


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
