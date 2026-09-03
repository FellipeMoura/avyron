class_name ElementPalette
extends RefCounted

## Identidade visual do elemento: recolore o corpo e acende a aura do
## Despertar Ancestral.
##
## ## De onde vêm as cores
##
## Do bestiário, nunca daqui. Cada elemento traz no bundle um bloco `palette`
## com `shadow`/`mid`/`highlight` (uma RAMPA lida por luminância), `aura` e
## `spread`. Antes disso existia um `ELEMENT_COLORS` codificado em
## `CreatureActor` — honesto como placeholder e errado como permanente: "de
## que cor é Fogo" é decisão de conteúdo, e conteúdo mora no catálogo
## (CLAUDE.md, regra 1). O que sobrou em código são as constantes de
## APRESENTAÇÃO: espessura da casca da aura, alcance da luz, razão de `spread`
## para gama. Essas um designer não ajusta.
##
## ## Em quais corpos a paleta entra
##
## Só nos placeholders compartilhados (`res://models/placeholders/`). Eles são
## paleta chapada com uma textura só — remapear é o que os torna
## distinguíveis por elemento. Os `.glb` legados do Meshy na raiz do projeto
## têm base color assada com normal e metallic-roughness próprios: remapear
## ali embaralharia sombreado pintado junto com a cor, e o resultado sai sujo.
## Corpo autoral futuro entra pelo mesmo critério — quem tem arte própria não
## é recolorido.
##
## ## Por que a mesma criatura não fica idêntica à vizinha
##
## 27 dos 30 placeholders dividem 2 atlas, e o elemento dá a mesma rampa para
## toda a família. Sem mais nada, duas criaturas de Fogo com o mesmo corpo
## sairiam a mesma criatura. `creature_bias` deriva do CÓDIGO da criatura um
## deslocamento dentro da faixa que o elemento permite (`spread`), aplicado
## como gama sobre a posição na rampa — ver o comentário do shader sobre por
## que gama e não soma.
##
## ## A aura do Despertar não é mais casca de malha
##
## Era uma cópia inflada de cada `MeshInstance3D` do corpo (`AwakeningAura_*`),
## com um shader próprio de espessura. Virou o efeito de área do pack
## BinbunVFX "Elemental Magic FX" (CC0, `assets/BinbunVFX_Vol2/`) — um disco de
## chão + coluna de glow em ruído + partículas subindo, TODO paramétrico por
## cor (`primary_color`/`secondary_color`/`tertiary_color`). A cena veio
## batizada de "Fire", mas nada nela é fogo: é ruído e gradiente, recolorido
## pelas MESMAS quatro cores que a rampa do corpo já lê do catálogo
## (`aura`/`mid`/`shadow`). Nenhum elemento novo foi criado, nenhuma pasta
## "DarkMagic" foi usada — aquele pack tem linguagem de movimento própria
## (fumaça/miasma "maligno") que só serve um elemento de Sombra/Trevas, que o
## catálogo não tem hoje.
##
## A `OmniLight3D` continua existindo e continua parte separada — ela ilumina
## o CHÃO ao redor na câmera isométrica com névoa, e o efeito de área (alfa,
## sem luz própria) não faz esse trabalho sozinho. As duas nascem e morrem
## juntas em `CreatureActor`/`CompanionActor`, mas são coisas diferentes.
##
## O disco de área é ANCORADO NO CHÃO (a cena assume seus próprios nós
## crescendo a partir de y=0), não na malha do corpo — diferente da casca
## antiga, que inflava cada malha. Por isso quem chama posiciona o retorno de
## `attach_area_vfx` no ponto de apoio (a convenção de "onde é o chão" já
## diverge entre os dois atores — ver regra 5 do CLAUDE.md — então o offset é
## responsabilidade de quem já sabe qual é o seu).
##
## ## Golpe e status também são BinbunVFX — pack "Battle FX"
##
## Antes de 2026-09 nada acontecia visualmente ao usar golpe ou status em
## duelo — os corpos ficavam em `Idle`, e só o texto do log mudava.
## `play_battle_effect` cobre as duas categorias com só 4 cenas
## (`assets/BinbunVFX_Vol2/BattleFX/`): `swing`/`claw` para dano (a forma
## sorteia ESTÁVEL pelo código da habilidade — nunca custom por golpe, só
## menos repetitivo que usar sempre a mesma), `shield` para buff/debuff/cura,
## `charge` para ganho de carga. Mesmas três cores da rampa do corpo
## (`highlight`/`mid`/`shadow`), nunca `aura` — aqui o efeito precisa ler
## contra qualquer fundo, e é isso que a rampa do corpo já prova; `aura` é a
## cor que identifica especificamente o Despertar, papel diferente.
##
## Efeito de status (buff/debuff/heal/charge) não tem elemento próprio no
## catálogo (`element: null` em toda habilidade que não é dano) — usa sempre
## o elemento de quem usou. Efeito de dano usa o elemento da HABILIDADE, que
## pode divergir de quem a usa (um golpe utilitário sem elemento cai no
## elemento de quem usou, pelo mesmo motivo do golpe sem multiplicador em
## `Battle._apply_damage`: mais informativo que cinza de engenharia).
##
## Nasce e morre sozinho — nenhum chamador guarda o nó de volta, ao contrário
## da aura do Despertar (que dura o duelo inteiro e por isso tem
## `detach_area_vfx`): aqui a vida é sempre curta e sempre a mesma por
## categoria, então um `Timer` de uma tacada resolve.
##
## ## A carta manda quando existe — `cardPalette`
##
## Desde 2026-09, cada criatura pode trazer `cardPalette` no bundle:
## shadow/mid/highlight extraídos (k-means sobre os pixels opacos, no
## bestiário) do próprio card em `apps/web/public/crt-cards/CRT-XXX.png`, no
## MESMO formato que a paleta de elemento já usa. `_effective_palette` decide
## a fonte — card se a criatura tiver um, elemento senão — e todo getter de
## cor (`mid_color`, `shadow_color`, `highlight_color`, `aura_color`) passa
## por ali agora, com `creature_code` como parâmetro OPCIONAL no fim: quem
## não passa continua lendo puro elemento, exatamente como antes.
##
## Cobertura de card é parcial de propósito (documento equivalente no
## bestiário) — a maioria do elenco ainda cai no elemento, e é assim que
## deve ser: sem `cardPalette`, nada aqui muda de comportamento.
##
## Duas exceções guardam por quê a cor existe, não só de onde ela vem:
##
## - **`creature_bias` não se aplica a quem tem card.** O deslocamento existe
##   pra duas criaturas do MESMO elemento não saírem idênticas — uma criatura
##   com paleta própria já não divide rampa com ninguém, então "dentro da
##   família" deixa de significar algo pra ela.
## - **Dano em duelo NUNCA usa o card de quem apanha.** A cor do golpe é da
##   HABILIDADE (um golpe de Fogo lê laranja não importa quem o sofre) — só
##   status (buff/debuff/cura/carga) herda a cor de quem usou, e aí sim o
##   card dela entra se existir. Ver `play_battle_effect`.
##
## O material de corpo (`_body_material`) também muda de chave de cache pra
## quem tem card: por CRIATURA em vez de por elemento, porque a rampa dela é
## única — compartilhar com o resto da família sairia errado. É a única
## fatia do elenco que perde o batching por elemento; o resto (a maioria)
## continua exatamente como sempre foi.

const BODY_SHADER := "res://shaders/element_palette.gdshader"

## Prefixo dos corpos que aceitam recoloração. Ver "Em quais corpos a paleta
## entra".
const PLACEHOLDER_PREFIX := "res://models/placeholders/"

## Cinza de engenharia, para elemento sem paleta no bundle (ou sem bundle
## nenhum — bancada solta). Não é escolha de arte: é o "não sei de que cor
## isto é" visível, e o export já avisa alto quando um elemento chega assim.
const NEUTRAL_MID := Color("#6B7280")
const NEUTRAL_HIGHLIGHT := Color("#F2EDE0")

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
## de `creature_bias`).
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

## Materiais de corpo por (elemento, atlas). Seis elementos sobre dois atlas
## dominantes = um punhado de materiais para o elenco inteiro, e material
## compartilhado por elemento é o que preserva o batching — o que varia por
## criatura viaja como instance uniform, não como cópia de material.
static var _body_materials: Dictionary = {}

## Bundle próprio, criado só quando o autoload `Bestiary` não existe (modo
## `--script`, bancada solta, gerador de cena). Mesmo motivo do fallback de
## `DuelScreen._db`, com a diferença de que aqui não há nó onde pendurar um
## filho.
static var _fallback_db: BestiaryData = null


# ---------------------------------------------------------------------------
# leitura da paleta
# ---------------------------------------------------------------------------

## Bloco `palette` do elemento, ou `{}` quando o elemento não tem paleta.
static func palette(element_code: String) -> Dictionary:
	var db := _db()
	if db == null:
		return {}
	var element := db.element(element_code)
	var raw: Variant = element.get("palette")
	return raw if raw is Dictionary else {}


## Bloco `cardPalette` da criatura, ou `{}` quando ela não tem card (a maioria
## do elenco hoje) ou não veio código nenhum. Mesmo formato do bloco
## `palette` do elemento (shadow/mid/highlight), computado no export a partir
## do PNG da carta — ver a seção "A carta manda quando existe" no topo do
## arquivo.
static func card_palette(creature_code: String) -> Dictionary:
	if creature_code == "":
		return {}
	var db := _db()
	if db == null:
		return {}
	var creature := db.creature(creature_code)
	var raw: Variant = creature.get("cardPalette")
	return raw if raw is Dictionary else {}


## A paleta que de fato vale pra esta criatura: a do card se ela tiver um,
## a do elemento senão. `creature_code == ""` pula direto pro elemento — é o
## caso de quem chama sem saber (ou sem se importar com) qual criatura é,
## como a cápsula de bancada solta.
static func _effective_palette(element_code: String, creature_code: String) -> Dictionary:
	if creature_code != "":
		var card := card_palette(creature_code)
		if not card.is_empty():
			return card
	return palette(element_code)


## Cor do meio da rampa. É a cor "da criatura" quando só cabe uma — cápsula de
## fallback, realce de seleção, qualquer lugar que antes lia `ELEMENT_COLORS`.
## `creature_code` é opcional: sem ele, sempre a rampa pura do elemento.
static func mid_color(element_code: String, creature_code: String = "") -> Color:
	return _stop(element_code, creature_code, "mid", NEUTRAL_MID)


static func shadow_color(element_code: String, creature_code: String = "") -> Color:
	return _stop(element_code, creature_code, "shadow", NEUTRAL_MID.darkened(0.6))


static func highlight_color(element_code: String, creature_code: String = "") -> Color:
	return _stop(element_code, creature_code, "highlight", NEUTRAL_HIGHLIGHT)


## Cor da aura do Despertar. Cai para o highlight quando a paleta efetiva não
## a autora — o export garante que `aura` chega preenchida na paleta de
## elemento, mas a queda existe para bundle antigo (ou card, que nunca traz
## `aura` — ver export) não apagar a aura em silêncio.
static func aura_color(element_code: String, creature_code: String = "") -> Color:
	var p := _effective_palette(element_code, creature_code)
	if p.has("aura"):
		return Color(str(p["aura"]))
	return highlight_color(element_code, creature_code)


## Deslocamento desta criatura dentro da família, em [-spread, +spread].
##
## Derivado do CÓDIGO, não sorteado: a mesma criatura tem de sair da mesma cor
## em toda partida, em todo save e nos dois corpos que a representam (selvagem
## no mapa e companheira ao lado do jogador). Um `RandomNumberGenerator` daria
## variedade e quebraria as três coisas.
##
## Criatura com card não desloca NADA: ela já não divide rampa com o resto da
## família (a rampa dela É a própria, não a do elemento), então não há
## "dentro de que faixa" pra caber.
static func creature_bias(creature_code: String, element_code: String) -> float:
	if not card_palette(creature_code).is_empty():
		return 0.0
	var p := palette(element_code)
	var spread := float(p.get("spread", 0.0))
	if spread <= 0.0 or creature_code == "":
		return 0.0
	var unit := float(absi(creature_code.hash()) % 1000) / 999.0
	return (unit * 2.0 - 1.0) * spread


# ---------------------------------------------------------------------------
# corpo
# ---------------------------------------------------------------------------

## Aplica a paleta do elemento às malhas de um corpo placeholder.
##
## Devolve `true` quando recoloriu. `false` — corpo fora de
## `res://models/placeholders/`, elemento sem paleta, malha sem atlas — deixa
## o corpo exatamente como veio do `.glb`, que é a degradação certa: melhor a
## criatura sair com a cor original do que sair cinza porque um dado faltou.
static func apply_body(
	mesh_instances: Array[MeshInstance3D],
	element_code: String,
	creature_code: String,
	model_path: String,
) -> bool:
	if not model_path.begins_with(PLACEHOLDER_PREFIX):
		return false
	if _effective_palette(element_code, creature_code).is_empty():
		return false

	var bias := creature_bias(creature_code, element_code)
	var applied := false
	for mi in mesh_instances:
		var mesh := mi.mesh
		if mesh == null:
			continue
		var touched := false
		for surface in mesh.get_surface_count():
			var atlas := _surface_albedo(mi, surface)
			if atlas == null:
				continue
			mi.set_surface_override_material(surface, _body_material(element_code, creature_code, atlas))
			touched = true
		if touched:
			# Por instância, não por material: é o que deixa um material por
			# elemento servir todas as criaturas dele.
			mi.set_instance_shader_parameter("ramp_bias", bias)
			applied = true
	return applied


# ---------------------------------------------------------------------------
# aura do Despertar
# ---------------------------------------------------------------------------

## Instancia o disco de área do BinbunVFX e o recolore pela paleta do
## elemento. Devolve `null` só se a cena não carregar — diferença proposital
## do antigo `attach_aura`, que devolvia lista vazia para "corpo sem malha":
## o efeito de área não depende de malha nenhuma, então TODO corpo (inclusive
## a cápsula) ganha aura visível agora, o que a casca antiga não conseguia.
##
## `primary`/`secondary`/`tertiary` mapeiam para `aura`/`mid`/`shadow` do
## bloco `palette` — as MESMAS quatro cores que já alimentam a rampa do corpo,
## nenhuma nova. `tertiary_color` é onde o efeito esmaece nas bordas (ver o
## script do pack), e é aí que `shadow` — o extremo escuro da rampa — encaixa
## sem forçar leitura.
##
## Quem chama posiciona o retorno no ponto de apoio do próprio ator (a
## convenção de onde é o chão diverge entre `CreatureActor` e
## `CompanionActor` — regra 5 do CLAUDE.md) e o adiciona como filho.
static func attach_area_vfx(element_code: String, size_meters: float, creature_code: String = "") -> Node3D:
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
	vfx.primary_color = aura_color(element_code, creature_code)
	vfx.secondary_color = mid_color(element_code, creature_code)
	vfx.tertiary_color = shadow_color(element_code, creature_code)
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
##
## Diferente de `attach_area_vfx`, esta função não devolve nada para guardar
## — é a mesma razão de `build_aura_light` não ter "detach": o efeito é dono
## do próprio ciclo de vida.
static func play_awakening_cast(
	parent: Node3D,
	ground_offset_y: float,
	element_code: String,
	size_meters: float,
	creature_code: String = "",
) -> void:
	var packed := load(CAST_VFX_SCENE) as PackedScene
	if packed == null or parent == null:
		return
	var vfx := packed.instantiate() as VFXElementalCastBB
	if vfx == null:
		return
	vfx.process_mode = Node.PROCESS_MODE_ALWAYS
	vfx.primary_color = aura_color(element_code, creature_code)
	vfx.secondary_color = mid_color(element_code, creature_code)
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
## `"charge"`) recolorido pelo elemento e plugado em `parent`. Ver o
## comentário de topo da seção "Golpe e status também são BinbunVFX" sobre a
## escolha de forma e cor. `variant_seed` só importa pra `"damage"` (o código
## da habilidade, que decide swing vs. claw); ignorado nos demais.
##
## Sem retorno: ninguém guarda este nó — `_life_for` já decide quanto tempo
## ele vive, e o `Timer` de uma tacada no fim desta função cuida de apagar.
static func play_battle_effect(
	parent: Node3D,
	ground_offset_y: float,
	size_meters: float,
	kind: String,
	element_code: String,
	variant_seed: String = "",
	creature_code: String = "",
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

	# Dano é a cor da HABILIDADE, nunca de quem apanha — um golpe de Fogo lê
	# laranja não importa a cor de card de quem tomou. Status (buff/debuff/
	# cura/carga) é sempre de quem USOU, e aí o card dela entra se existir —
	# ver "A carta manda quando existe" no topo do arquivo.
	var color_creature := "" if kind == "damage" else creature_code

	# Golpe/status acontece SEMPRE em duelo, e duelo pausa a árvore inteira
	# (`EncounterDirector.engage_wild/engage_arena: _parent.get_tree().paused
	# = true`, só solto em `_on_duel_closed`). `PROCESS_MODE_INHERIT` (o
	# padrão) faria este nó nascer e travar no primeiro quadro — o ator só
	# marca o PRÓPRIO `AnimationPlayer` como `ALWAYS` durante a encenação
	# (`staged_animating`/`animate_while_paused`, ver `battle_staging.gd`),
	# nunca um filho novo que nasce depois dele. Foi exatamente isto que fez
	# o golpe (swing/claw, cuja forma INTEIRA depende da animação abrir)
	# nascer e ficar parado no quadro zero — invisível — enquanto o shield
	# ainda lia como "algo aconteceu" por sobrar partícula/geometria do
	# primeiro quadro antes de travar.
	vfx.process_mode = Node.PROCESS_MODE_ALWAYS

	vfx.set("primary_color", highlight_color(element_code, color_creature))
	vfx.set("secondary_color", mid_color(element_code, color_creature))
	vfx.set("tertiary_color", shadow_color(element_code, color_creature))

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
static func build_aura_light(element_code: String, size_meters: float, creature_code: String = "") -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "AwakeningLight"
	light.light_color = aura_color(element_code, creature_code)
	light.light_energy = AURA_LIGHT_ENERGY
	light.omni_range = maxf(size_meters * AURA_LIGHT_RANGE_RATIO, 1.5)
	# Sombra desligada: a luz existe para BANHAR o chão em volta, e uma omni
	# com sombra dentro do próprio corpo da criatura gasta um mapa de sombra
	# para escurecer exatamente a região que ela deveria acender.
	light.shadow_enabled = false
	return light


# ---------------------------------------------------------------------------
# internals
# ---------------------------------------------------------------------------

static func _stop(element_code: String, creature_code: String, key: String, fallback: Color) -> Color:
	var p := _effective_palette(element_code, creature_code)
	return Color(str(p[key])) if p.has(key) else fallback


## O `.glb` importado guarda o material na superfície da malha. Um override já
## posto (rebuild do corpo, por exemplo) tem precedência, senão a segunda
## passagem leria o atlas do próprio shader de paleta e se realimentaria.
static func _surface_albedo(mi: MeshInstance3D, surface: int) -> Texture2D:
	var existing := mi.get_surface_override_material(surface)
	if existing is ShaderMaterial:
		var current: Variant = (existing as ShaderMaterial).get_shader_parameter("atlas")
		return current as Texture2D
	var material := mi.mesh.surface_get_material(surface)
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).albedo_texture
	return null


## Chave de cache por CRIATURA quando ela tem card (a rampa é única — dividir
## com o resto da família sairia errado, cada uma tem a própria), por
## ELEMENTO quando não (o caso comum, e o que preserva o batching pro grosso
## do elenco). Ver "A carta manda quando existe" no topo do arquivo.
static func _body_material(element_code: String, creature_code: String, atlas: Texture2D) -> ShaderMaterial:
	var has_card := not card_palette(creature_code).is_empty()
	var palette_key := ("card:" + creature_code) if has_card else ("elem:" + element_code)
	var key := "%s|%s" % [palette_key, _texture_key(atlas)]
	var cached: Variant = _body_materials.get(key)
	if cached is ShaderMaterial:
		return cached

	var material := ShaderMaterial.new()
	material.shader = load(BODY_SHADER) as Shader
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("ramp", _ramp_texture(element_code, creature_code))
	_body_materials[key] = material
	return material


## Rampa como `GradientTexture1D`: três paradas, sombra em 0, meio em 0.5,
## brilho em 1. O shader amostra por luminância, então a posição de cada
## parada É o significado dela.
static func _ramp_texture(element_code: String, creature_code: String) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		shadow_color(element_code, creature_code),
		mid_color(element_code, creature_code),
		highlight_color(element_code, creature_code),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func _texture_key(atlas: Texture2D) -> String:
	if atlas.resource_path != "":
		return atlas.resource_path
	return str(atlas.get_instance_id())


## Busca RELATIVA a partir da raiz (`"Bestiary"`), não absoluta
## (`"/root/Bestiary"`) como no resto do repo.
##
## Os dois endereçam o mesmo nó, mas caminho absoluto exige a árvore viva:
## chamado de um `_initialize()` de bancada — que é exatamente onde um corpo é
## montado antes de a árvore existir — o absoluto derruba
## `Can't use get_node() with absolute paths from outside the active scene
## tree`. É a mesma armadilha que o CLAUDE.md documenta para medição de
## posição em teste, aparecendo aqui pelo mesmo motivo. O resto do repo pode
## usar o absoluto porque só consulta de dentro de um `_ready()`.
static func _db() -> BestiaryData:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var root := (loop as SceneTree).root
		if root != null:
			var autoload := root.get_node_or_null("Bestiary") as BestiaryData
			if autoload != null:
				# O autoload pode existir e ainda não ter carregado: ele carrega
				# no `_ready()`, e um corpo montado de dentro de um
				# `_initialize()` chega aqui antes disso. Sem esta carga o nó
				# responde a tudo e responde VAZIO — a criatura sai neutra e
				# nada acusa erro, que é o pior desfecho possível. `load_bundle`
				# é idempotente, então cobrar aqui não custa nada.
				if autoload.data_version == "":
					autoload.load_bundle()
				return autoload
	if _fallback_db == null:
		_fallback_db = BestiaryData.new()
		# `load_bundle` explícito: `BestiaryData` carrega no `_ready()`, e este
		# nó nunca entra na árvore. Sem esta linha o fallback existe, responde
		# a tudo e responde VAZIO — e a criatura sai sem paleta com todo mundo
		# achando que consultou o catálogo.
		_fallback_db.load_bundle()
	return _fallback_db
