class_name PlayerRig
extends GaitRig

## O corpo do domador: um `.glb` fechado, com esqueleto e clipes PRÓPRIOS.
##
## Até 2026-09-07 o jogador era montado pelo mesmo `CharacterRig` dos NPCs — uma
## receita de peças do kit de personagens, animada por retarget nas bibliotecas
## UAL. O kit continua sendo o sistema dos NPCs e só deles; o jogador ganhou
## corpo próprio, e as duas coisas deixaram de ser a mesma.
##
## A troca não mexeu em nenhum chamador porque o contrato entre corpo e jogo
## nunca foi a montagem — é o VOCABULÁRIO de clipes. `models/player.glb` chega
## do Meshy AI já falando `Idle`/`Walk`/`Run`/`Swim`/`Swim_Idle`/`Harvest`/
## `Throw`, normalizado por `avyron-bestiary/scripts/convert-meshy.mjs`, então
## a escada de marcha herdada de `GaitRig` escolhe entre eles sem saber de onde
## vieram. Mesmo caminho dos corpos Meshy definitivos de criatura: sem
## retarget, sem biblioteca compartilhada, `find_animation_player` e pronto.
##
## Duas medidas do arquivo que valem estar escritas, porque cada uma quase
## virou um número inventado:
##
## - **Altura 1,68 m, e nada de escala.** O corpo mede 1,64 m de pé no `Idle`
##   (osso mais baixo em +0,04, mais alto em +1,68) contra 1,53 m do corpo UAL
##   que ele substitui. A cápsula de colisão tem 1,80 m, e é tentador esticar a
##   malha até enchê-la — mas 1 unidade = 1 metro é regra da casa, 1,68 m é um
##   humano plausível, e cápsula sobrando é o normal de toda cápsula. Escalar
##   seria escolher um número por estética sem medida por trás.
## - **`swim_lift` e `swim_idle_lift` ficam em zero.** O `Swim` do corpo UAL
##   deita o nadador em torno da origem do rig (medido: y de -0,54 a +0,11), e
##   por isso `CharacterRig` o levanta 0,9 m — sem isso o nadador arrasta a
##   barriga no leito. O `Swim` deste corpo já nasce pairando (y de +0,29 a
##   +0,88): posto cru, ele fica praticamente onde o outro só chegava
##   levantado. Herdar o 0,9 o penduraria um metro acima do fundo, boiando. O
##   `Swim_Idle` daqui é outra pose que a da UAL: o corpo boia DE PÉ, com os
##   pés em +0,19 e a cabeça em +1,60 (quadril em +1,0), e não pendurado
##   1,42 m abaixo da origem — foi ele que deixou a escada de `GaitRig` parar
##   de tocar `Swim` com o corpo parado.
##
## O que NÃO veio de graça foi o `Swim`: ele chegou do Meshy com root motion
## (2,21 m para a frente em 4,57 s, o único dos sete clipes que andava). Quem
## move este corpo é o `CharacterBody3D`, então a malha viajaria em dobro e
## voltaria de um salto a cada volta do ciclo. Corrigido no conversor, não
## aqui — clipe do jogo é in-place por contrato, e compensar em código deixaria
## o próximo corpo repetir o defeito.

const MODEL_PATH := "res://models/player.glb"

## Os modelos do Meshy olham para +Z, como os placeholders de criatura; a frente
## de um nó no jogo é -Z (regra 4 do `CLAUDE.md`). Confirmado neste arquivo pelo
## osso `headfront`, 0,21 m à frente do `Head` no eixo +Z. Sem este giro,
## `PlayerController._face_direction` viraria o corpo para o rumo do movimento
## e ele andaria de costas — a mesma classe de bug da regra 4, só que na malha
## em vez do cálculo de ângulo.
const MODEL_YAW := PI


## Monta o corpo do jogador. Devolve `null` quando o `.glb` não carrega — quem
## chama cai para a cápsula, mesmo contrato do `CharacterRig.create` com kit
## ausente e do `CreatureActor.build_visual` com modelo faltando.
static func create() -> PlayerRig:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_warning("PlayerRig: corpo do jogador nao carregou de %s" % MODEL_PATH)
		return null

	var rig := PlayerRig.new()
	rig.name = "PlayerRig"

	var body := packed.instantiate() as Node3D
	body.name = "Body"
	body.rotation.y = MODEL_YAW
	rig.add_child(body)
	# Guardado porque é ELE que subiria se este corpo precisasse de flutuação —
	# não o rig, cuja posição quem monta define ("os pés em y=0 local").
	rig._body = body

	rig._anim = find_animation_player(body)
	if rig._anim == null:
		# Sem clipe o corpo fica de pé e imóvel. Não é fallback para cápsula:
		# um corpo parado ainda é o corpo certo, e a escada de marcha silencia
		# sozinha (`play_clip` com `_anim` nulo não faz nada).
		push_warning("PlayerRig: %s sem AnimationPlayer — corpo fica estatico" % MODEL_PATH)
		return rig

	mark_looping(rig._anim)
	if rig._anim.has_animation("Idle"):
		rig._anim.play("Idle")
	return rig
