class_name ElementPalette
extends RefCounted

## Cor fixa e neutra para a aura do Despertar Ancestral e para os efeitos de
## golpe/status — não mais uma identidade visual por elemento.
##
## ## Por que isto deixou de ler o catálogo
##
## Até 2026-09 esta classe recolorizava o CORPO das criaturas placeholder
## (shader `element_palette.gdshader`, rampa `shadow`/`mid`/`highlight` do
## bundle) e usava a mesma rampa para tingir a aura do Despertar e os efeitos
## de golpe/status. Isso era premeditadamente provisório — ver ROADMAP.md,
## "Meia identidade já chegou sem asset novo": "o que a paleta compra é
## tempo", até o elenco ganhar corpo autoral (Meshy animado) em vez de dividir
## um placeholder por família de elemento.
##
## Essa frente começou em 2026-09 (`convert-meshy.mjs`, ver
## `CreatureActor.model_path`) e o elenco passou a convergir para UM só
## placeholder universal (`models/placeholders/dungeon/Imp.glb`) para toda
## criatura ainda sem corpo definitivo — dividido por TODOS os elementos ao
## mesmo tempo, não por família. Recolorir por elemento nesse cenário não
## distingue mais nada (toda criatura sem modelo compartilha o mesmo corpo,
## elemento nenhum ganha identidade própria), e os corpos Meshy definitivos
## trazem a própria arte, que não deve ser remapeada. A rampa por elemento
## saiu do bundle como decisão de conteúdo (regra 1 do CLAUDE.md) — o que
## sobra em código são só as constantes de apresentação (raio da aura,
## alcance da luz, escala dos efeitos de golpe), que já eram daqui.
##
## ## O que continua existindo
##
## A aura do Despertar (disco de área do BinbunVFX + `OmniLight3D`) e os
## efeitos de golpe/status (swing/claw/shield/charge) continuam — são
## feedback de COMBATE, não identidade do corpo, e continuam valiosos sem
## cor por elemento. Só a cor mudou: sempre a mesma rampa neutra
## (`NEUTRAL_*` abaixo), em vez de uma por elemento ou por carta.
##
## ## O que não existe mais
##
## Recoloração de corpo (`apply_body`, o shader de rampa, `cardPalette` por
## criatura).
##
## ## A exceção: o buff tem cor de elemento (2026-09-18)
##
## O efeito de BUFF voltou a ler `elements[].palette` do bundle
## (`element_ramp`). O argumento acima é sobre o CORPO — recolorir um
## placeholder único não distingue nada — e não vale pra partícula: a aura de
## buff é a mesma cena pra toda criatura, e a cor é a única coisa que diz de
## quem ela é. A rampa é conteúdo (regra 1 do CLAUDE.md), por isso vem do
## bundle e não de uma tabela aqui; sem bundle à mão (bancada solta, elemento
## desconhecido) cai na rampa neutra. O FEIXE do golpe do Despertar
## (`play_battle_beam`) entrou no mesmo dia e pela mesma regra. Golpe corpo a
## corpo, debuff, cura, carga e a aura do Despertar seguem neutros até cada um
## ser revisto. O golpe ELEMENTAR (`attack2`) fechou o conjunto: corte tingido
## mais estouro de impacto (`damage_elemental` + `impact`). Seguem neutros o
## golpe básico, debuff, cura, carga e a aura do Despertar.

## Cor "da criatura" quando só cabe uma — realce de seleção, aura, efeitos de
## golpe/status. Mesmo cinza de engenharia que antes só aparecia quando um
## elemento vinha sem paleta no bundle; agora é a cor de TODA criatura.
const NEUTRAL_MID := Color("#6B7280")
const NEUTRAL_SHADOW := Color("#2B2F36") # NEUTRAL_MID escurecido
const NEUTRAL_HIGHLIGHT := Color("#F2EDE0")
const NEUTRAL_AURA := NEUTRAL_HIGHLIGHT

## A luz é o que faz a aura ler na câmera isométrica com névoa: a criatura
## desperta ILUMINA o chão em volta, e isso se vê de longe mesmo quando o
## efeito de área é sutil. Alcance deriva do tamanho do corpo.
const AURA_LIGHT_RANGE_RATIO := 3.5
const AURA_LIGHT_ENERGY := 1.6

const AREA_VFX_SCENE := "res://assets/BinbunVFX_Vol2/ElementalMagicFX/effects/area/vfx_fire_area_01.tscn"
const CAST_VFX_SCENE := "res://assets/BinbunVFX_Vol2/ElementalMagicFX/effects/cast/vfx_fire_cast_01.tscn"

## Raio do disco de área como fração do tamanho de jogo — mesmo raciocínio de
## proporção relativa que a casca antiga usava para a espessura: um trilobita
## e um Arthropleura despertam com auras de escala diferente, não a mesma.
const AREA_RADIUS_RATIO := 0.55
const AREA_RADIUS_MIN := 0.6
const AREA_RADIUS_MAX := 2.4

## O burst de "cast" vem desenhado para uma cena de conjuração (3 esferas de
## flare recuando na direção do alvo, em X local) — não para um corpo que
## acende sozinho. Girado 90° em Z, o eixo dos flares aponta para cima em vez
## de para o lado, e lê como uma lufada subindo pelo corpo no instante do
## Despertar, e não como disparo lateral. A escala contém as 3 posições
## (1.5/2.5/4 m) dentro de uma altura proporcional ao porte da criatura.
const CAST_SCALE_RATIO := 0.3
const CAST_SCALE_MIN := 0.3
const CAST_SCALE_MAX := 1.4

const BATTLE_SWING_SCENE := "res://assets/BinbunVFX_Vol2/BattleFX/effects/swing/vfx_blank_swing.tscn"
const BATTLE_CLAW_SCENE := "res://assets/BinbunVFX_Vol2/BattleFX/effects/claw/vfx_blank_claw.tscn"
const BATTLE_SHIELD_SCENE := "res://assets/BinbunVFX_Vol2/BattleFX/effects/shield/vfx_blank_shield_01.tscn"
const BATTLE_CHARGE_SCENE := "res://assets/BinbunVFX_Vol2/BattleFX/effects/charge/vfx_blank_charge.tscn"

## Buff: a aura "Shatter" do StatusFX (versão Free — é a única cena de status
## que o pack gratuito traz; as demais do mostruário são do pago). Vem branca
## e cinza de fábrica, que é o que a deixa tingir limpo por elemento.
const BATTLE_BUFF_SCENE := "res://assets/BinbunVFX_Vol2/StatusFX/effects/status/vfx_status_shatter.tscn"

## A cena vem com `emission = 10`, pensada pra branco com glow no ambiente.
## O jogo não liga glow nem tonemap, então 10× uma cor SATURADA só estoura os
## canais no teto e o laranja do Fogo vira amarelo-claro. Neste valor a cor do
## elemento chega inteira na tela.
const BATTLE_BUFF_EMISSION := 2.2
const BATTLE_BUFF_PREPROCESS := 1.5

## Golpe do Despertar (`attackVariant: attack3`): o feixe de energia do pack
## "Beam VFX" (Free — traz UMA cena base, branca, feita pra ser tingida). O
## caminho é `assets/BinbunVFX/`, sem o `_Vol2` dos outros packs, porque é o
## que a cena do pack referencia por dentro; renomear quebraria os `ext_resource`.
const BATTLE_BEAM_SCENE := "res://assets/BinbunVFX/beam_vfx/effects/base/base_beam_vfx.tscn"

## Mesmo raciocínio de `BATTLE_BUFF_EMISSION`: a cena vem em 3,0 pensando em
## glow. Sem glow nem tonemap, 3× (e mesmo 2×) uma cor saturada estoura os
## canais e todo elemento vira o mesmo amarelo-claro — medido na primeira
## captura, em que só a Água ainda se distinguia.
const BATTLE_BEAM_EMISSION := 1.15

## Três peças da cena multiplicam a cor por conta própria, por cima de
## `emission`, e precisam de freio separado (ver `_tint_beam`): as bolas de
## origem e de impacto têm um clarão (`flash_emission`, 4 a 6 na cena) que sem
## glow vira um disco branco do tamanho do alvo, escondendo o corpo que
## apanha; e o shader das faíscas multiplica por 5 fixo.
const BATTLE_BEAM_FLASH_EMISSION := 1.35
const BATTLE_BEAM_SPARK_EMISSION := 0.3

## Quanto o miolo do feixe puxa do `highlight` pra `aura`. Miolo todo no
## `highlight` é claro demais pra dizer o elemento (o do Fogo é quase o da
## Eletricidade); todo na `aura` perde a leitura de "núcleo quente".
const BATTLE_BEAM_CORE_BLEND := 0.45

## O feixe não tem `AnimationPlayer`: quem o abre e fecha é `open_amount`
## (0 → 1 → 0), animado daqui por um `Tween`. Abrir é o disparo atravessando
## o vão; é DEPOIS dele que o alvo reage (`EncounterDirector` espera este
## tempo antes do `HitReact`). Fechar é o feixe afinando até sumir.
const BATTLE_BEAM_OPEN_TIME := 0.18
const BATTLE_BEAM_CLOSE_TIME := 0.22

## O feixe nasce à frente do corpo, não dentro dele: este fator sobre o raio
## da cápsula põe a bola de origem logo adiante do peito.
const BATTLE_BEAM_REACH_RATIO := 1.3

## Golpe ELEMENTAR (`attackVariant: attack2`): além do corte, um estouro de
## impacto na cor do elemento, do pack "Stylized Hit FX" (Free). Das seis
## cenas do pack entram as duas `impact`, escolhidas olhando a captura: as
## `hit` são estrelinhas que somem em 0,3 s e não carregam cor nenhuma na
## câmera do jogo, e as `big_impact` abrem anéis maiores que o vão do duelo.
## Qual das duas sai é sorteio ESTÁVEL no código da habilidade, a mesma regra
## de `BATTLE_ATTACK_SCENES`.
const BATTLE_IMPACT_SCENES := [
	"res://assets/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_01.tscn",
	"res://assets/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_02.tscn",
]

## Cada material da cena traz a própria `emission` (2 a 6), pensada pra glow.
## Sem glow nem tonemap isso estoura a cor do elemento pro branco — mesmo caso
## do buff e do feixe —, então todos recebem ESTE valor direto no material; o
## `emission` exportado pelo script do pack é só um multiplicador por cima.
const BATTLE_IMPACT_EMISSION := 1.3
const BATTLE_IMPACT_CORE_BLEND := 0.55

## A bola central (`ImpactSphere`) precisa de freio próprio: o shader dela
## multiplica por `emission` DUAS vezes (ao quadrado), é aditivo e desenha as
## duas faces da esfera somadas — com o valor dos outros materiais vira um
## disco amarelo-claro opaco em cima do alvo, de qualquer elemento.
const BATTLE_IMPACT_SPHERE_EMISSION := 0.8
const BATTLE_IMPACT_LIGHT_ENERGY := 1.2

## A animação da cena dura 1,6–2 s, mas o que se vê é o primeiro meio segundo
## (clarão 0,3 s, fagulhas 0,6 s). Vive um pouco além do compasso do golpe pra
## as últimas fagulhas não sumirem cortadas no meio.
const BATTLE_IMPACT_LIFETIME := 1.2

## As duas formas de golpe — nunca escolha por habilidade, só sorteio ESTÁVEL
## pelo código dela (mesmo golpe sempre sai com a mesma forma, mesmo raciocínio
## de sorteio estável que o resto do arquivo usa pra variedade sem aleatório).
const BATTLE_ATTACK_SCENES := [BATTLE_SWING_SCENE, BATTLE_CLAW_SCENE]

## Escala como fração do porte, com piso — os blanks vêm autorados pra um
## corpo por volta de 1,5-2 m; sem piso um trilobita de 15 cm receberia um
## efeito minúsculo demais pra ler na câmera isométrica.
const BATTLE_EFFECT_SCALE_RATIO := 0.5
const BATTLE_EFFECT_SCALE_MIN := 0.5
const BATTLE_EFFECT_SCALE_MAX := 1.6

## Vida de cada categoria, em segundos — presentação pura, não regra de
## catálogo. `charge` vem autorado com uma animação de 2,4 s (a barra de carga
## do golpe original); cortar no mesmo tempo do golpe deixaria a maior parte
## do efeito nunca aparecer.
const BATTLE_ATTACK_LIFETIME := 0.8
const BATTLE_STATUS_LIFETIME := 1.4
const BATTLE_CHARGE_LIFETIME := 2.6


# ---------------------------------------------------------------------------
# cor (sempre a mesma rampa neutra — os parâmetros seguem existindo só pra
# não obrigar quem chama a mudar de assinatura; nenhum deles é lido)
# ---------------------------------------------------------------------------

static func mid_color(_element_code: String = "", _creature_code: String = "") -> Color:
	return NEUTRAL_MID


static func shadow_color(_element_code: String = "", _creature_code: String = "") -> Color:
	return NEUTRAL_SHADOW


static func highlight_color(_element_code: String = "", _creature_code: String = "") -> Color:
	return NEUTRAL_HIGHLIGHT


static func aura_color(_element_code: String = "", _creature_code: String = "") -> Color:
	return NEUTRAL_AURA


## Rampa do elemento lida do bundle (`elements[].palette`), com as mesmas
## quatro chaves da neutra. `context` é qualquer nó na árvore — serve só pra
## achar o autoload por CAMINHO (`/root/Bestiary`), nunca pelo identificador
## global, que não existe no modo `--script` (mesmo motivo de `DuelScreen`).
## Tudo que falta — autoload, elemento, uma chave da paleta — cai na neutra,
## chave a chave: efeito cinza é melhor que efeito nenhum.
static func element_ramp(context: Node, element_code: String) -> Dictionary:
	var ramp := {
		"highlight": NEUTRAL_HIGHLIGHT,
		"mid": NEUTRAL_MID,
		"shadow": NEUTRAL_SHADOW,
		"aura": NEUTRAL_AURA,
	}
	if element_code == "" or context == null or not context.is_inside_tree():
		return ramp
	var db := context.get_tree().root.get_node_or_null("Bestiary") as BestiaryData
	if db == null:
		return ramp
	var palette: Dictionary = db.element(element_code).get("palette", {})
	for key: String in ramp.keys():
		if palette.has(key):
			ramp[key] = Color.from_string(str(palette[key]), ramp[key])
	return ramp


# ---------------------------------------------------------------------------
# aura do Despertar
# ---------------------------------------------------------------------------

## Instancia o disco de área do BinbunVFX, recolorido pela rampa neutra fixa.
## Devolve `null` só se a cena não carregar.
##
## Quem chama posiciona o retorno no ponto de apoio do próprio ator (a
## convenção de onde é o chão diverge entre `CreatureActor` e
## `CompanionActor` — regra 5 do CLAUDE.md) e o adiciona como filho.
static func attach_area_vfx(size_meters: float, _element_code: String = "", _creature_code: String = "") -> Node3D:
	var packed := load(AREA_VFX_SCENE) as PackedScene
	if packed == null:
		return null
	var vfx := packed.instantiate() as VFXElementalAreaBB
	if vfx == null:
		return null
	# O Despertar pode ligar em duelo, e duelo pausa a árvore inteira
	# (`EncounterDirector.engage_wild/engage_arena`). Sem isto o efeito nasce
	# e trava no primeiro quadro — herdaria `PROCESS_MODE_INHERIT` de um
	# ator que só marca o PRÓPRIO `AnimationPlayer` como `ALWAYS`
	# (`staged_animating`/`animate_while_paused`), nunca os filhos que
	# nascem depois dele. Ver a mesma nota em `play_battle_effect`.
	vfx.process_mode = Node.PROCESS_MODE_ALWAYS
	vfx.primary_color = NEUTRAL_AURA
	vfx.secondary_color = NEUTRAL_MID
	vfx.tertiary_color = NEUTRAL_SHADOW
	vfx.area_radius = clampf(size_meters * AREA_RADIUS_RATIO, AREA_RADIUS_MIN, AREA_RADIUS_MAX)
	return vfx


static func detach_area_vfx(vfx: Node3D) -> void:
	if is_instance_valid(vfx):
		vfx.queue_free()


## Estouro de uma vez só no instante em que o Despertar liga — a cena de
## "cast" do BinbunVFX, virada de lado (ver `CAST_SCALE_RATIO`) e plugada
## direto na árvore, já tocando. Ela se apaga sozinha: `finished` (emitido
## pela própria `VFXControllerBB` do pack ao fim da animação `main`) está
## ligado a `queue_free`, e `one_shot = true` (setado ANTES do `add_child`,
## porque `VFXControllerBB._enter_tree` já dispara `play()` se a cena entrar
## com `autoplay` ligado) impede o replay automático que a cena faz por
## padrão.
static func play_awakening_cast(parent: Node3D, ground_offset_y: float, size_meters: float) -> void:
	var packed := load(CAST_VFX_SCENE) as PackedScene
	if packed == null or parent == null:
		return
	var vfx := packed.instantiate() as VFXElementalCastBB
	if vfx == null:
		return
	vfx.process_mode = Node.PROCESS_MODE_ALWAYS
	vfx.primary_color = NEUTRAL_AURA
	vfx.secondary_color = NEUTRAL_MID
	vfx.one_shot = true
	# Os 3 flares da cena recuam ao longo do X local (cena pensada para uma
	# conjuração mirando um alvo); girado 90° em Z, esse eixo aponta para
	# cima e lê como lufada subindo pelo corpo.
	vfx.rotation.z = PI * 0.5
	var scale_factor := clampf(size_meters * CAST_SCALE_RATIO, CAST_SCALE_MIN, CAST_SCALE_MAX)
	vfx.scale = Vector3.ONE * scale_factor
	vfx.position.y = ground_offset_y + size_meters * 0.5
	parent.add_child(vfx)
	vfx.finished.connect(vfx.queue_free)
	vfx.play()


# ---------------------------------------------------------------------------
# efeito de golpe/status
# ---------------------------------------------------------------------------

## Golpe (`kind == "damage"`) ou status (`"buff"`/`"debuff"`/`"heal"`/
## `"charge"`), plugado em `parent`. `variant_seed` só importa pra
## `"damage"` (o código da habilidade, que decide swing vs. claw); ignorado
## nos demais. `element_code` só importa pra quem sai na cor do elemento (ver
## o comentário de topo): `"buff"` e o par do golpe elementar —
## `"damage_elemental"` (o mesmo corte de `"damage"`, tingido) e `"impact"`
## (o estouro). O resto é rampa neutra fixa.
##
## Sem retorno: ninguém guarda este nó — `_life_for` já decide quanto tempo
## ele vive, e o `Timer` de uma tacada no fim desta função cuida de apagar.
static func play_battle_effect(
	parent: Node3D,
	ground_offset_y: float,
	size_meters: float,
	kind: String,
	variant_seed: String = "",
	element_code: String = "",
) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var scene_path := _battle_effect_scene(kind, variant_seed)
	if scene_path == "":
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var vfx := packed.instantiate() as Node3D
	if vfx == null:
		return

	# Golpe/status acontece SEMPRE em duelo, e duelo pausa a árvore inteira
	# (`EncounterDirector.engage_wild/engage_arena: _parent.get_tree().paused
	# = true`, só solto em `_on_duel_closed`). `PROCESS_MODE_INHERIT` (o
	# padrão) faria este nó nascer e travar no primeiro quadro — o ator só
	# marca o PRÓPRIO `AnimationPlayer` como `ALWAYS` durante a encenação
	# (`staged_animating`/`animate_while_paused`, ver `battle_staging.gd`),
	# nunca um filho novo que nasce depois dele.
	vfx.process_mode = Node.PROCESS_MODE_ALWAYS

	if kind == "buff":
		_tint_buff(vfx, element_ramp(parent, element_code))
	elif kind == "impact":
		_tint_impact(vfx, element_ramp(parent, element_code))
	elif kind == "damage_elemental":
		_tint_slash(vfx, element_ramp(parent, element_code))
	else:
		vfx.set("primary_color", NEUTRAL_HIGHLIGHT)
		vfx.set("secondary_color", NEUTRAL_MID)
		vfx.set("tertiary_color", NEUTRAL_SHADOW)

	var scale_factor := clampf(
		size_meters * BATTLE_EFFECT_SCALE_RATIO, BATTLE_EFFECT_SCALE_MIN, BATTLE_EFFECT_SCALE_MAX)
	vfx.scale = Vector3.ONE * scale_factor
	vfx.position.y = ground_offset_y + size_meters * 0.5
	parent.add_child(vfx)

	# As duas famílias do pack pedem gatilho diferente: `VFXControllerBB`
	# (swing/claw/charge) só anima quando `play()` é chamado; `VFXEmitterBB`
	# (shield) abre com `open()`. Nenhuma delas se apaga sozinha aqui — ao
	# contrário do burst do Despertar, este efeito não conecta `finished`,
	# porque o `Timer` abaixo já cobre os dois tipos de uma vez só, sem
	# precisar saber qual é qual pra limpar depois.
	if vfx is VFXControllerBB:
		(vfx as VFXControllerBB).one_shot = true
		(vfx as VFXControllerBB).play()
	elif vfx is VFXEmitterBB:
		(vfx as VFXEmitterBB).open()

	var timer := parent.get_tree().create_timer(_battle_effect_lifetime(kind))
	# Ligado direto ao método do nó, não a uma lambda que o captura: se o
	# corpo (e o efeito junto) morrer antes do prazo, o motor desfaz a conexão
	# sozinho. A lambda sobrevivia ao nó e acusava "Lambda capture was freed"
	# a cada efeito órfão — ruído que escondia erro de verdade no log.
	timer.timeout.connect(vfx.queue_free)


## Feixe de energia do golpe do Despertar, de `source` até `target`, na cor do
## elemento. `*_height` é a altura do peito de cada corpo no espaço LOCAL dele
## (quem sabe é o ator — `battle_effect_height`, que já conta apoio no chão e
## flutuação de nado); `source_radius` é o raio do corpo que dispara.
## `duration` é a vida inteira do feixe, abertura e fechamento incluídos.
##
## Devolve o nó (ou `null`) só pra suíte inspecionar — ninguém precisa
## guardar: o próprio `Tween` apaga o feixe e a âncora no fim.
##
## Três coisas aqui são exigência do script do pack, não gosto:
## - cor e `open_amount` só DEPOIS do `add_child`: ele monta a lista de
##   materiais (e as referências dos nós) em `_enter_tree`, e antes disso os
##   setters escrevem em lista vazia ou estouram em nó nulo;
## - materiais duplicados ANTES do `add_child`, pelo mesmo motivo de
##   `_tint_buff` — é em `_enter_tree` que ele guarda os que vai tingir;
## - `beam_length` igual à distância real antes de apontar o `end_point`: o
##   script escala o feixe por dois caminhos (`_set_open_amount` usa
##   `beam_length`, `follow_node` usa a distância medida), e com números
##   diferentes o comprimento pisca entre os dois a cada quadro da abertura.
static func play_battle_beam(
	source: Node3D,
	source_height: float,
	source_radius: float,
	target: Node3D,
	target_height: float,
	element_code: String,
	duration: float,
) -> Node3D:
	if source == null or not is_instance_valid(source) or not source.is_inside_tree():
		return null
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return null
	var packed := load(BATTLE_BEAM_SCENE) as PackedScene
	if packed == null:
		return null
	var vfx := packed.instantiate() as Node3D
	if vfx == null:
		return null

	# Duelo pausa a árvore — ver `play_battle_effect`. Aqui pesa em dobro: o
	# feixe segue o alvo em `_physics_process`, que também para com a pausa.
	vfx.process_mode = Node.PROCESS_MODE_ALWAYS
	for mesh in vfx.find_children("*", "GeometryInstance3D", true, false):
		var geometry := mesh as GeometryInstance3D
		if geometry.material_override != null:
			geometry.material_override = geometry.material_override.duplicate()

	# Âncora no peito do alvo. Filha DELE, pra acompanhar um `HitReact` que
	# desloque o corpo; o feixe a segue por posição global.
	var anchor := Marker3D.new()
	anchor.name = "BeamAnchor"
	anchor.position = Vector3(0.0, target_height, 0.0)
	target.add_child(anchor)

	# A frente de um nó é -Z (regra 4 do CLAUDE.md).
	vfx.position = Vector3(0.0, source_height, -source_radius * BATTLE_BEAM_REACH_RATIO)
	source.add_child(vfx)

	_tint_beam(vfx, element_ramp(source, element_code))
	vfx.set("beam_length", vfx.global_position.distance_to(anchor.global_position))
	vfx.set("open_amount", 0.0)
	vfx.set("end_point", anchor)
	if vfx.has_method("follow_node"):
		vfx.call("follow_node")

	var hold := maxf(duration - BATTLE_BEAM_OPEN_TIME - BATTLE_BEAM_CLOSE_TIME, 0.0)
	var tween := vfx.create_tween()
	tween.tween_property(vfx, "open_amount", 1.0, BATTLE_BEAM_OPEN_TIME)
	tween.tween_interval(hold)
	tween.tween_property(vfx, "open_amount", 0.0, BATTLE_BEAM_CLOSE_TIME)
	tween.tween_callback(vfx.queue_free)
	# A âncora mora em OUTRO corpo: sai junto com o feixe por qualquer caminho
	# (fim do tween, ou o atacante liberado no meio do disparo).
	vfx.tree_exiting.connect(func() -> void:
		if is_instance_valid(anchor):
			anchor.queue_free()
	)
	return vfx


## Estouro de impacto do golpe elementar. Mesma duplicação de material de
## `_tint_buff`, e pelo mesmo motivo (os dois lados podem golpear com
## elementos diferentes na mesma rodada). A luz da cena (`VFXOmniLightBB`)
## entra na cor também: é ela que tinge o chão e o corpo do alvo no instante
## do golpe, e branca desmentiria a partícula.
static func _tint_impact(vfx: Node3D, ramp: Dictionary) -> void:
	for child in vfx.get_children():
		var geometry := child as GeometryInstance3D
		if geometry == null or geometry.material_override == null:
			continue
		var material := geometry.material_override.duplicate() as ShaderMaterial
		geometry.material_override = material
		if material != null and material.get_shader_parameter("emission") != null:
			material.set_shader_parameter("emission",
				BATTLE_IMPACT_SPHERE_EMISSION if child.name == &"ImpactSphere" else BATTLE_IMPACT_EMISSION)
	var aura: Color = ramp["aura"]
	var highlight: Color = ramp["highlight"]
	vfx.set("primary_color", highlight.lerp(aura, BATTLE_IMPACT_CORE_BLEND))
	vfx.set("secondary_color", aura)
	vfx.set("light_color", aura)
	vfx.set("light_energy", BATTLE_IMPACT_LIGHT_ENERGY)


## O corte (swing/claw) do golpe elementar, na cor do elemento — o do golpe
## básico segue neutro. Cinza ao lado de um estouro colorido leria como dois
## golpes diferentes acertando ao mesmo tempo.
static func _tint_slash(vfx: Node3D, ramp: Dictionary) -> void:
	for child in vfx.get_children():
		var geometry := child as GeometryInstance3D
		if geometry != null and geometry.material_override != null:
			geometry.material_override = geometry.material_override.duplicate()
	vfx.set("primary_color", ramp["highlight"])
	vfx.set("secondary_color", ramp["aura"])
	vfx.set("tertiary_color", ramp["aura"])


## Cor do feixe. As três cores do pack têm papel fixo nos shaders: primária é
## o miolo, secundária a casca que ondula em volta, terciária as bolas das
## pontas, os cones de saída e as faíscas. Aqui as três ficam na família da
## `aura` — a `mid`/`shadow` da rampa são escuras e apagariam as pontas.
##
## Os freios por peça vão direto no material (já duplicado por instância),
## porque o script do pack só sabe escrever o MESMO `emission` em todos.
static func _tint_beam(vfx: Node3D, ramp: Dictionary) -> void:
	var aura: Color = ramp["aura"]
	var highlight: Color = ramp["highlight"]
	vfx.set("primary_color", highlight.lerp(aura, BATTLE_BEAM_CORE_BLEND))
	vfx.set("secondary_color", aura)
	vfx.set("tertiary_color", aura)
	vfx.set("emission", BATTLE_BEAM_EMISSION)
	# As faíscas do IMPACTO usam o shader da bola (com clarão), não o das
	# faíscas da origem — na cena os dois nós da ponta dividem o material.
	for path: String in ["BeamStart", "BeamEndPivot/BeamEnd", "BeamEndPivot/BeamEndParticles"]:
		_set_beam_param(vfx, path, "flash_emission", BATTLE_BEAM_FLASH_EMISSION)
	_set_beam_param(vfx, "BeamPivot/BeamParticles", "emission", BATTLE_BEAM_SPARK_EMISSION)


static func _set_beam_param(vfx: Node3D, path: String, key: String, value: Variant) -> void:
	var node := vfx.get_node_or_null(path) as GeometryInstance3D
	if node != null and node.material_override is ShaderMaterial:
		(node.material_override as ShaderMaterial).set_shader_parameter(key, value)


## Os `ShaderMaterial` da cena são sub-recurso do `PackedScene` — toda
## instância aponta pro MESMO material, e tingir uma tinge todas. Com os dois
## lados usando buff na mesma rodada (elementos diferentes), o segundo
## recoloriria o primeiro enquanto ele ainda está na tela. Duplicar ANTES de
## tingir é o que dá a cada instância a própria cor; tem de ser antes porque
## o script do pack guarda a lista de materiais na primeira vez que a lê.
##
## Primária no `highlight` e terciária na `aura`: no shader a terciária é a
## cor da massa rala da chama e a primária só aparece no miolo denso, então
## é a terciária que decide de que cor o efeito "é". A `shadow` da rampa é
## escura demais pra isso — a chama sumiria contra o fundo do mar.
static func _tint_buff(vfx: Node3D, ramp: Dictionary) -> void:
	for child in vfx.get_children():
		if child is GeometryInstance3D and (child as GeometryInstance3D).material_override != null:
			(child as GeometryInstance3D).material_override = (child as GeometryInstance3D).material_override.duplicate()
		# A cena é um STATUS contínuo no pack: as partículas nascem aos poucos
		# e só enchem depois de uns 2 s — mais que a vida inteira do buff aqui
		# (`BATTLE_STATUS_LIFETIME`). Pré-processada, a chama já abre cheia.
		if child is GPUParticles3D:
			(child as GPUParticles3D).preprocess = BATTLE_BUFF_PREPROCESS
	vfx.set("primary_color", ramp["highlight"])
	vfx.set("secondary_color", ramp["aura"])
	vfx.set("tertiary_color", ramp["aura"])
	vfx.set("emission", BATTLE_BUFF_EMISSION)


static func _battle_effect_scene(kind: String, variant_seed: String) -> String:
	match kind:
		"damage", "damage_elemental":
			var i := absi(variant_seed.hash()) % BATTLE_ATTACK_SCENES.size()
			return BATTLE_ATTACK_SCENES[i]
		"impact":
			var j := absi(variant_seed.hash()) % BATTLE_IMPACT_SCENES.size()
			return BATTLE_IMPACT_SCENES[j]
		"buff":
			return BATTLE_BUFF_SCENE
		"debuff", "heal":
			return BATTLE_SHIELD_SCENE
		"charge":
			return BATTLE_CHARGE_SCENE
		_:
			return ""


static func _battle_effect_lifetime(kind: String) -> float:
	match kind:
		"charge":
			return BATTLE_CHARGE_LIFETIME
		"impact":
			return BATTLE_IMPACT_LIFETIME
		"buff", "debuff", "heal":
			return BATTLE_STATUS_LIFETIME
		_:
			return BATTLE_ATTACK_LIFETIME


## Luz que a criatura desperta joga no chão. Quem chama é dono do nó — some
## junto com a aura.
static func build_aura_light(size_meters: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "AwakeningLight"
	light.light_color = NEUTRAL_AURA
	light.light_energy = AURA_LIGHT_ENERGY
	light.omni_range = maxf(size_meters * AURA_LIGHT_RANGE_RATIO, 1.5)
	# Sombra desligada: a luz existe para BANHAR o chão em volta, e uma omni
	# com sombra dentro do próprio corpo da criatura gasta um mapa de sombra
	# para escurecer exatamente a região que ela deveria acender.
	light.shadow_enabled = false
	return light
