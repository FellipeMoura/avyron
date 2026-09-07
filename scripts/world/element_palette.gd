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
## criatura), e com ela a dependência do bundle: esta classe não consulta
## mais `BestiaryData` — não há palette nem cardPalette pra ler.

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
## `"charge"`), recolorido pela rampa neutra fixa e plugado em `parent`.
## `variant_seed` só importa pra `"damage"` (o código da habilidade, que
## decide swing vs. claw); ignorado nos demais.
##
## Sem retorno: ninguém guarda este nó — `_life_for` já decide quanto tempo
## ele vive, e o `Timer` de uma tacada no fim desta função cuida de apagar.
static func play_battle_effect(
	parent: Node3D,
	ground_offset_y: float,
	size_meters: float,
	kind: String,
	variant_seed: String = "",
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
	timer.timeout.connect(func() -> void:
		if is_instance_valid(vfx):
			vfx.queue_free()
	)


static func _battle_effect_scene(kind: String, variant_seed: String) -> String:
	match kind:
		"damage":
			var i := absi(variant_seed.hash()) % BATTLE_ATTACK_SCENES.size()
			return BATTLE_ATTACK_SCENES[i]
		"buff", "debuff", "heal":
			return BATTLE_SHIELD_SCENE
		"charge":
			return BATTLE_CHARGE_SCENE
		_:
			return ""


static func _battle_effect_lifetime(kind: String) -> float:
	match kind:
		"charge":
			return BATTLE_CHARGE_LIFETIME
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
