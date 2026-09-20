class_name CreatureActor
extends CharacterBody3D

## Uma criatura no mapa.
##
## Ignora o jogador por completo — sem raio de detecção, sem perseguição. Só
## vaga entre `IDLE` e `PATROL` no próprio ritmo. A batalha nunca nasce de
## proximidade; é sempre o segundo clique do jogador que chama `request_engage`
## (ver `WorldRoot`). Antes havia um terceiro e quarto estado (`ALERT`,
## `ENGAGE`) que faziam a criatura notar e perseguir quem chegasse perto —
## removidos porque o disparo por clique já bastava, e reagir à aproximação
## além disso só competia com a decisão do jogador de quando entrar em luta.
##
## O corpo vem do `modelUrl` do bundle quando a criatura tem um definitivo
## (Meshy AI animado, ver `model_path`), do placeholder único
## (`PLACEHOLDER_PATH`) quando não, e só cai pra cápsula escalada pelo tamanho
## de jogo se nem esse arquivo carregar. Sem cor por elemento em nenhum dos
## três — ver o comentário de topo de `element_palette.gd`. O que é definitivo
## independe de qual dos três: escala real em unidades Godot, máquina de
## estados de navegação, colisão — só a malha visual muda de fonte.
##
## Especificação: `movimento-e-controles`, seção "IA no mapa".

enum State { IDLE, PATROL }

const PATROL_SPEED := 1.2

## Marcha a partir da qual o corpo corre em vez de andar, e abaixo da qual
## conta como parado. A patrulha anda sempre a `PATROL_SPEED` e nunca chega
## perto do limiar de corrida — `Run` só aparece na encenação do duelo, que
## impõe a marcha por fora (`staged_gait`). Os dois passam pela MESMA escada
## (`_gait`), que é também quem decide entre andar e nadar.
const RUN_THRESHOLD := 2.0
const IDLE_SPEED := 0.05

## Degrau de cima da escada seca: a partir daqui o corpo dispara (`Sprint`) em
## vez de correr. Só a investida do duelo chega lá
## (`BattleStaging.CHARGE_SPEED`) — o posicionamento da encenação tem teto em
## 4 m/s e a patrulha anda a 1,2. Apresentação, como os outros dois limiares.
## `CompanionActor` usa ESTE valor em vez de repetir o número: os dois lados
## do duelo têm de trocar de clipe na mesma marcha.
const SPRINT_THRESHOLD := 6.0

const IDLE_MIN := 1.5
const IDLE_MAX := 4.0
const PATROL_RADIUS := 6.0

## Coleira até `_home`. Quando a criatura ultrapassa esta distância, o próximo
## alvo de patrulha vem enviesado de volta em vez de sorteio livre — sem isso
## ela pode vagar indefinidamente para fora do bioma.
const HOME_LEASH := 8.0

## Multiplicador de energia da emissão quando a criatura está selecionada.
## Um valor baixo evita "queimar" a cor do corpo — o realce tem de ser lido
## como "esta é a selecionada", não como um efeito de luz forte.
const SELECT_EMISSION_ENERGY := 0.55

signal engaged(actor: CreatureActor)

var creature_code := ""
var display_name := ""
var element_code := ""
var size_meters := 1.8
var model_url := ""
## Quem responde "estou na água?" — injetado pelo `CreatureSpawner`, que o
## recebe do `WorldRoot` como todo mundo que precisa do relevo. Nulo (bancadas
## de teste sem terreno) = sempre seco, e a escada de marcha fica em
## `Idle`/`Walk`/`Run` como antes de existir nado.
var terrain: MapTerrain

var state: State = State.IDLE
## Último meio visto por `_gait`, para `_physics_process` reavaliar o clipe só
## quando o corpo troca de meio — nunca a cada quadro, que pisaria num clipe
## de combate tocado por nome (`play_battle_clip`).
var _submerged := false
var _home := Vector3.ZERO
var _patrol_target := Vector3.ZERO
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _engaged_once := false

## Quanto levantar a malha visual enquanto `Swim`/`Swim_Idle` tocam — mesma
## medida de `CompanionActor.SWIM_LIFT`/`SWIM_IDLE_LIFT`, e não uma segunda
## constante, porque os dois consomem o MESMO `build_visual()` (mesmo
## esqueleto UAL, mesma normalização de `sizeMeters`): remedir aqui duplicaria
## a mesma medida do mesmo corpo e as duas divergiriam no dia em que uma
## mudasse. Sem levantamento nenhum a criatura selvagem ficava "enterrada" —
## a malha nunca tinha ganho a compensação que `GaitRig`/`CompanionActor`
## sempre tiveram, porque `submerged()` nunca respondia sim antes do spawner
## injetar `terrain` (ver o comentário de `terrain` acima): o nado só passou a
## realmente tocar em criatura selvagem quando esse fio foi ligado, e foi aí
## que a falta desta compensação virou visível.
var _swim_offset := 0.0
## Último "está se deslocando?" visto por `_gait`, para `_advance_swim_lift`
## separar Swim (nadando) do resto por INTENÇÃO de marcha, não pelo nome do
## clipe corrente — `Attack`/`HitReact`/`Death` tocam por fora da escada
## (`play_battle_clip`, com a marcha TRAVADA por `BattleStaging._gait_locked`)
## e não são `Swim`/`Swim_Idle`. `_swim_moving` continua correto durante o
## travamento porque é `_gait` (chamado por `staged_gait`) quem o grava, e ele
## só para de ser chamado depois de a dupla já estar parada nos postos.
var _swim_moving := false
## Corpo emprestado à `BattleStaging` — ver o contrato de encenação mais
## abaixo. Só existe para `_physics_process` saber que a própria máquina de
## estados e `move_and_slide` não são donos do corpo agora; a altura de nado
## continua sendo assunto deste script, e por isso continua rodando.
var _staged := false

var _mesh: Node3D
var _collision: CollisionShape3D
var _material: StandardMaterial3D
var _mesh_instances: Array[MeshInstance3D] = []
var _highlight_material: StandardMaterial3D
var _selected := false
var _anim: AnimationPlayer

## Aura do Despertar Ancestral: o efeito de área do BinbunVFX ancorado no
## chão, mais a luz que a criatura joga em volta. `null` fora do Despertar —
## a aura não existe como nó desligado, ela nasce e morre com a
## transformação. Ver `set_awakening_aura`.
var _awakened := false
var _aura_vfx: Node3D
var _aura_light: OmniLight3D

## Localização do modelo, em ordem de prioridade:
##
## 1. O `modelUrl` do bundle (`/models/...`), espelhado pelo `pnpm game:export`
##    em `res://models/...` — o corpo Meshy DEFINITIVO da criatura (piloto:
##    CRT-002, ver `../avyron-bestiary/scripts/convert-meshy.mjs`), quando ela
##    tem um.
## 2. `PLACEHOLDER_PATH`: o único corpo genérico que sobrevive à limpeza de
##    2026-09 (antes eram ~30, um por família de elemento — ver o comentário
##    de topo de `element_palette.gd`). Toda criatura sem corpo definitivo cai
##    aqui, sem distinção nenhuma entre elas.
##
## Só cai pra cápsula se nem o placeholder único carregar — praticamente nunca,
## já que ele é commitado e sempre deve existir.
const MODEL_URL_PREFIX := "/models/"
const MODEL_DIR := "res://models/"

## Corpo genérico único de toda criatura sem `modelUrl` resolvível. É o
## "Bestiary - Dungeon Monsters" (Quaternius, CC0) — escolhido entre os
## packs que existiam porque roda por RETARGET no mesmo esqueleto (UAL) do
## `CharacterRig`, o que dá de graça o vocabulário INTEIRO de clipes do jogo
## (`Attack2`, `HitReact`, `Death`, `Swim`...), e o PZ-01 é 87,3% submerso —
## um corpo sem `Swim` ficaria parado boa parte do tempo.
const PLACEHOLDER_PATH := "res://models/placeholders/dungeon/Imp.glb"

## Quais clipes rodam em loop é decisão de `GaitRig.LOOPED_CLIPS`, aplicada
## na montagem da biblioteca UAL (`CharacterRig._build_library`) — criatura,
## NPC e placeholder recebem a mesma biblioteca, então uma lista própria
## aqui (que existiu até 2026-09-17, com nomes dos placeholders de 2026-08)
## só podia divergir dela.


## Resolve o caminho do `.glb` de uma criatura, ou "" quando não há arquivo.
static func model_path(_creature_code_value: String, model_url_value: String) -> String:
	if model_url_value.begins_with(MODEL_URL_PREFIX):
		var bundled := MODEL_DIR + model_url_value.trim_prefix(MODEL_URL_PREFIX)
		if ResourceLoader.exists(bundled):
			return bundled
	if ResourceLoader.exists(PLACEHOLDER_PATH):
		return PLACEHOLDER_PATH
	return ""


static func create(data: Dictionary, at: Vector3, seed_value: int) -> CreatureActor:
	var a := CreatureActor.new()
	a.creature_code = str(data["code"])
	a.display_name = str(data["name"])
	a.element_code = str(data["element"])
	a.size_meters = float(data["stats"]["sizeMeters"])
	# `modelUrl` é null no bundle quando a criatura não tem modelo — e
	# `str(null)` viraria a string "<null>", que passaria no begins_with.
	var url: Variant = data.get("modelUrl")
	a.model_url = url if url is String else ""
	a._home = at
	a.position = at
	a._rng.seed = seed_value
	return a


func _ready() -> void:
	_build_body()
	_enter_idle()


func _build_body() -> void:
	var visual := build_visual(size_meters, element_code, creature_code, model_url)
	_mesh = visual["mesh"]
	_material = visual["material"]
	_mesh_instances = visual["mesh_instances"]
	_anim = visual["anim"]
	add_child(_mesh)

	var height: float = visual["height"]
	var radius: float = visual["radius"]

	var shape := CapsuleShape3D.new()
	shape.height = height
	shape.radius = radius
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	_collision.shape = shape
	add_child(_collision)

	# Soma, não atribuição: o spawner entrega `at` já na altura do terreno, e
	# o corpo sobe meia cápsula A PARTIR dali. Atribuir zeraria o relevo e a
	# criatura nasceria enterrada em qualquer colina.
	position.y += height * 0.5

	if not _mesh_instances.is_empty():
		_highlight_material = _build_highlight_material(element_code, creature_code)


## Raio do corpo, derivado do tamanho de jogo.
##
## A cápsula usa o tamanho como ALTURA e tira o raio dele, para o volume crescer
## junto e um Arthropleura não virar um poste fino.
##
## Está separado do resto porque o afastamento de duelo precisa saber onde a
## **borda** de cada corpo está, e não só desenhá-lo: dois bichos de 2,5 m
## parados à mesma distância central que dois trilobitas ficariam encostados.
## Duas derivações do raio em lugares diferentes discordariam no dia em que uma
## delas mudasse. Vale também com `.glb`: colisão e afastamento de duelo usam
## sempre esta medida, nunca o tamanho do arquivo importado.
static func capsule_radius(size_meters: float) -> float:
	return clampf(size_meters * 0.28, 0.15, 1.2)


## Altura e raio da cápsula de colisão — únicos para o corpo, venha ele de
## `.glb` ou da cápsula visual. Ver `capsule_radius` sobre por que isto não se
## deriva duas vezes.
static func capsule_dimensions(size_meters: float) -> Dictionary:
	var radius := capsule_radius(size_meters)
	var height := maxf(size_meters, radius * 2.0 + 0.01)
	return {"height": height, "radius": radius}


## Constrói o visual de uma criatura: `.glb` definitivo ou placeholder único
## quando `model_path` resolve algum, cápsula cinza quando nem isso carrega.
## Devolve um dicionário com os nós e as medidas — o CompanionActor consome o
## mesmo layout, pra manter a leitura consistente entre selvagem e
## domesticada.
##
## O nó em `"mesh"` sempre representa, na própria origem local, o CENTRO
## vertical da cápsula de colisão — é o que permite `CompanionActor` posicionar
## os dois tipos de corpo com o mesmo `position.y = height * 0.5`, sem saber
## qual dos dois recebeu.
static func build_visual(size_meters: float, element_code: String, creature_code: String, model_url_value: String = "") -> Dictionary:
	var dims := capsule_dimensions(size_meters)
	var path := model_path(creature_code, model_url_value)
	var model := _build_model_visual(path, size_meters, dims)
	if not model.is_empty():
		# Sem recoloração por elemento desde 2026-09 (ver o comentário de topo
		# de `element_palette.gd`): todo corpo — placeholder único ou Meshy
		# definitivo — mostra a própria arte, sem remapeamento de atlas.
		return model
	return build_capsule_visual(size_meters, element_code, creature_code)


## Tenta montar o visual a partir do caminho resolvido por `model_path`.
## Devolve dicionário vazio quando não há caminho ou o arquivo não traz
## nenhuma malha — quem chama cai para a cápsula nesse caso.
##
## A escala do arquivo é desconhecida a priori (o pipeline de exportação não
## garante 1 unidade = 1 metro), então esta função mede o AABB combinado das
## malhas e escala até bater com `size_meters`: pela ALTURA quando o corpo é
## skinado (todo corpo rigado nasce em T-pose, e lá o maior eixo é a
## envergadura, não o corpo), e pelo MAIOR eixo quando é malha estática — é
## esse eixo, não a altura, que carrega o "tamanho" de um artrópode comprido e
## baixo como Eurypterus. Depois recentra em X/Z e apoia a base em Y no mesmo
## ponto onde a cápsula apoiaria, para colisão e visual concordarem sobre onde
## é o chão.
static func _build_model_visual(path: String, size_meters: float, dims: Dictionary) -> Dictionary:
	if path == "":
		return {}
	var packed := load(path) as PackedScene
	if packed == null:
		return {}
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return {}

	var mesh_instances := _collect_mesh_instances(instance)
	if mesh_instances.is_empty():
		instance.queue_free()
		return {}

	var aabb := _local_aabb(instance, mesh_instances)
	# Corpo SKINADO (esqueleto): o "tamanho" é a ALTURA. Todo corpo rigado do
	# jogo nasce em T-pose (a mestre do fluxo base + casca, o placeholder
	# Imp, o kit de personagens), e em T-pose o maior eixo é a envergadura,
	# não o corpo: um chibi de 0,93 m com braços de 1,47 m escalado pelo
	# maior eixo virava um corpo de 0,89 m para `sizeMeters` 1,4 (medido em
	# 2026-09-15). Malha estática segue pelo maior eixo — é ela que carrega o
	# caso do artrópode comprido e baixo da docstring.
	var skinned := false
	for mi in mesh_instances:
		if mi.skeleton != NodePath():
			skinned = true
			break
	var extent := aabb.size.y if skinned else maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if extent <= 0.0:
		instance.queue_free()
		return {}

	var factor: float = size_meters / extent
	var center := aabb.get_center()
	var height: float = dims["height"]

	# Regra: todo corpo de criatura olha para +Z no arquivo (a mestre do fluxo
	# base + casca, o placeholder Imp e o kit da UAL nascem assim, e o Tripo
	# exporta assim). A frente do jogo é -Z (`_face()` vira o corpo para o
	# rumo do movimento), então o giro de meia-volta é o contrato, não uma
	# exceção — sem ele a criatura anda de costas, a cauda na frente, a mesma
	# classe de bug da regra 4 do CLAUDE.md, só que na malha.
	instance.rotation.y = PI
	instance.scale = Vector3.ONE * factor
	# X/Z: recentra a malha na origem do wrapper — os sinais são POSITIVOS
	# porque o giro de 180° acima já inverteu X e Z. Y: a malha apoia em
	# `-height/2`, o mesmo ponto onde a cápsula apoiaria — ver docstring sobre
	# por que "mesh" representa o centro vertical da cápsula, não o chão. O
	# giro em Y não muda a componente Y de nenhum ponto, então esta parte não
	# leva o mesmo ajuste de sinal.
	instance.position = Vector3(
		center.x * factor,
		-height * 0.5 - aabb.position.y * factor,
		center.z * factor,
	)

	var wrapper := Node3D.new()
	wrapper.name = "Model"
	wrapper.add_child(instance)

	# Todo corpo de criatura chega SEM clipe e é animado por retarget: o
	# esqueleto tem os nomes da UAL (a mestre do fluxo base + casca e o
	# placeholder Imp são o mesmo esqueleto), e `_build_retargeted_animation`
	# lhe dá a biblioteca inteira do jogo, já com loop marcado e root motion
	# removido na montagem (`CharacterRig._build_library`). Até 2026-09-17
	# havia um segundo caminho, o de clipe embutido dos corpos Meshy, e dois
	# caminhos é o que produz bug silencioso (um corpo com clipes de nome
	# errado tocava nada, sem aviso). Corpo sem Skeleton3D fica parado.
	var anim := _build_retargeted_animation(instance)
	if anim != null and anim.has_animation("Idle"):
		anim.play("Idle")

	return {
		"mesh": wrapper,
		"material": null,
		"mesh_instances": mesh_instances,
		"anim": anim,
		"height": height,
		"radius": dims["radius"],
	}


## Constrói um `AnimationPlayer` retargeted para o `Skeleton3D` de `instance`,
## ou `null` se ele não tiver esqueleto nenhum (corpo verdadeiramente estático).
## `CharacterRig._build_library` já faz o trabalho pesado — funde UAL1+UAL2 e
## reescreve as trilhas para apontar o esqueleto certo — e cacheia por STRING
## de caminho relativo, não por instância; corpos de estrutura idêntica (Imp e
## Puglin repetem `Armature/Skeleton3D` sob a raiz importada) dividem a mesma
## biblioteca sem saber um do outro, do mesmo jeito que todo `CharacterRig`
## já divide.
static func _build_retargeted_animation(instance: Node) -> AnimationPlayer:
	var skeleton := GaitRig.find_skeleton(instance)
	if skeleton == null:
		return null
	# As trilhas de ROTAÇÃO da UAL valem para qualquer corpo com estes nomes
	# de osso, e o importador já descarta as trilhas de posição constantes
	# (comprimento de osso fica o do corpo). Mas a posição do `pelvis` varia
	# (balanço da passada) e é ABSOLUTA, em metros da UAL: o quadril de todo
	# corpo ia parar a 0,87–0,92 m do chão, fosse qual fosse a altura de
	# repouso dele. Medido em 2026-09-15: o Imp (quadril 0,81) andava com o
	# pé 10 cm no ar; uma mestre chibi (quadril 0,39) flutuaria meio metro.
	# `motion_scale` multiplica as trilhas de posição do esqueleto — é o
	# mecanismo do próprio Godot para retarget entre alturas —, então a
	# razão entre a altura de repouso do quadril deste corpo e a da UAL
	# devolve o balanço na escala certa. Mesma ideia do `Hips` escalado por
	# razão de alturas em `transfer-clips.mjs` do bestiário.
	var pelvis := skeleton.find_bone("pelvis")
	if pelvis != -1:
		var rest_height := skeleton.get_bone_global_rest(pelvis).origin.y
		if rest_height > 0.0:
			skeleton.motion_scale = rest_height / UAL_PELVIS_REST_HEIGHT
	var anim := AnimationPlayer.new()
	anim.name = "Anim"
	instance.add_child(anim)
	var skeleton_path := String(instance.get_path_to(skeleton))
	anim.add_animation_library("", CharacterRig._build_library(skeleton_path))
	return anim


## Altura de repouso do `pelvis` no esqueleto da UAL, em metros — medida em
## `characters/animations/UAL1.glb` (2026-09-15). É a referência contra a qual
## `motion_scale` escala as trilhas de posição de um corpo retargetado.
const UAL_PELVIS_REST_HEIGHT := 0.9167


static func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_mesh_instances(child))
	return out


## Transform de `node` relativo a `ancestor`, compondo `transform` (local, por
## nó) subindo a hierarquia. `global_transform` exigiria o nó dentro da
## árvore — o mesmo problema que o `CLAUDE.md` documenta para testes que medem
## posição no `_initialize` — e isto roda no `_ready()` da criatura, antes de
## qualquer garantia de estar na árvore.
static func _transform_relative_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var current := node
	while current != null and current != ancestor:
		t = current.transform * t
		current = current.get_parent() as Node3D
	return t


## AABB combinado das malhas em espaço local de `root`.
static func _local_aabb(root: Node3D, mesh_instances: Array[MeshInstance3D]) -> AABB:
	var result := AABB()
	var found := false
	for mi in mesh_instances:
		# Malha com skin (esqueleto): `get_aabb()` já sai correta sozinha. O
		# import bakeia a escala real do arquivo nas poses dos ossos
		# (`apply_root_scale`, ligado por padrão), e o Godot posiciona a malha
		# skinada pelas poses do `Skeleton3D` — não pela cadeia de nós comuns.
		# Compor a transformação de um ancestral acima do esqueleto (como o
		# "Armature" que o Mixamo/Blender deixa com escala 0,01 de correção
		# cm→m) conta essa escala DUAS vezes: uma já embutida nos ossos, outra
		# aqui. Confirmado visualmente com o piloto Meshy AI (hoje CRT-002): a malha
		# saía ~100x maior que o alvo até este ramo existir. Malha sem skin
		# (`.glb` estático legado do Meshy, placeholders sem retarget) não tem
		# esse embutimento — para ela a composição é a medida certa.
		var world: AABB
		if mi.skeleton != NodePath():
			world = mi.get_aabb()
		else:
			world = _transform_relative_to(mi, root) * mi.get_aabb()
		if not found:
			result = world
			found = true
		else:
			result = result.merge(world)
	return result


## Material translúcido usado como `material_overlay` das malhas de `.glb`
## quando selecionadas. A cápsula acende emissão no próprio material; um
## modelo importado tem materiais e texturas que não devem ser mexidos, então
## o realce aqui é uma camada extra por cima, não uma troca de propriedade.
## Cor fixa (`ElementPalette.highlight_color`, sem elemento nem carta desde
## 2026-09) — nenhum corpo é recolorido pelo próprio elemento hoje, então não
## há risco de o realce cair na mesma cor que a criatura já tem.
static func _build_highlight_material(_element_code: String, _creature_code: String = "") -> StandardMaterial3D:
	var color := ElementPalette.highlight_color()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.35)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = SELECT_EMISSION_ENERGY
	return material


## Constrói o visual de ÚLTIMO recurso: uma cápsula cinza. Só é alcançado se
## nem `PLACEHOLDER_PATH` (o corpo genérico único) carregar — na prática,
## nunca, já que esse arquivo é commitado e sempre deve existir.
##
## O material com emissão preparada (desligada) já sai daqui, então quem quiser
## acender o realce depois só precisa de `emission_enabled = true`.
static func build_capsule_visual(size_meters: float, _element_code: String = "", _creature_code: String = "") -> Dictionary:
	var dims := capsule_dimensions(size_meters)
	var radius: float = dims["radius"]
	var height: float = dims["height"]

	var mesh := CapsuleMesh.new()
	mesh.height = height
	mesh.radius = radius

	var material := StandardMaterial3D.new()
	material.albedo_color = ElementPalette.mid_color()
	material.roughness = 0.9
	material.emission = ElementPalette.highlight_color()
	material.emission_energy_multiplier = SELECT_EMISSION_ENERGY
	material.emission_enabled = false
	mesh.material = material

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = mesh

	return {
		"mesh": mesh_node,
		"material": material,
		"mesh_instances": [] as Array[MeshInstance3D],
		"anim": null,
		"height": height,
		"radius": radius,
	}


func _physics_process(delta: float) -> void:
	# Emprestado à `BattleStaging`: ela é dona de posição, rotação e marcha
	# agora (ver o contrato de encenação abaixo), mas a altura de nado
	# continua sendo assunto deste script — só ela some do `_physics_process`
	# comum, o resto do método inteiro é dela.
	if _staged:
		_advance_swim_lift(delta)
		return

	match state:
		State.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_enter_patrol()
			# Zerar X/Z aqui não é redundante: `move_and_slide` devolve a
			# velocidade AJUSTADA pela resolução de colisão com o chão, e sem
			# reescrever a cada quadro esse resíduo (~10⁻³) se acumula e vira
			# a "tremedeira" visível em criaturas em repouso. `PATROL` não
			# sofre porque sobrescreve `velocity` a cada quadro via
			# `_move_towards`.
			velocity.x = 0.0
			velocity.z = 0.0
		State.PATROL:
			_move_towards(_patrol_target, PATROL_SPEED, delta)
			if global_position.distance_to(_patrol_target) < 0.6:
				_enter_idle()

	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	# O meio pode mudar no meio de um estado — a coleira leva a patrulha até a
	# beira da rampa da costa. Só a TROCA de meio reavalia o clipe; ver
	# `_submerged` sobre por que não é a cada quadro.
	if submerged() != _submerged:
		_gait(Vector2(velocity.x, velocity.z).length())

	_advance_swim_lift(delta)


## Sobe a malha (nunca a cápsula de colisão, que continua apoiada no chão)
## enquanto o corpo nada, e devolve para a origem local fora d'água — mesma
## ideia de `GaitRig._advance_float`/`CompanionActor._advance_swim_lift`,
## repetida aqui porque este corpo não estende nenhum dos dois. A altura
## persegue a cota do clipe corrente (`Swim_Idle` boia mais alto que `Swim`
## nada) à velocidade que cruza a maior das duas em `SWIM_BLEND_TIME`, casada
## com o crossfade de clipe (0,2 s).
## Parada e submersa, ainda falta separar DUAS formas de "parada": boiando
## (`Swim_Idle`, esqueleto agachado) ou tocando um golpe de duelo (`Attack`,
## `HitReact`, `Death`, esqueleto DE PÉ — ver
## `CompanionActor.SUBMERGED_STANDING_LIFT`). Essa segunda escolha É por nome
## do clipe, porque é sobre a FORMA do esqueleto corrente, não sobre
## intenção de movimento — confundir as duas (decidir a forma pela
## intenção, como a primeira versão fazia) produziu o "levanta ao atacar"
## relatado em 2026-09-18.
##
## `_staged` força SEMPRE a altura "de pé", mesmo enquanto o clipe corrente
## ainda é `Swim_Idle` (a dupla assentada no posto, antes do primeiro golpe).
## As duas alturas foram calibradas para o TOPO do esqueleto bater igual —
## `SUBMERGED_STANDING_LIFT = SWIM_IDLE_LIFT - SUBMERGED_STANDING_DELTA` —, mas
## os pés continuam em cotas ligeiramente diferentes nas duas poses (agachada
## vs. de pé), e por isso alternar entre elas ainda lia como um levantar
## pequeno a cada golpe (relatado de novo em 2026-09-18, depois da primeira
## correção). Duelo inteiro numa altura só elimina a alternância em vez de só
## encolhê-la; fora do duelo `Swim_Idle` continua na própria altura (mais alta
## de propósito, para só a cabeça ficar de fora — ver `SWIM_IDLE_LIFT`).
func _advance_swim_lift(delta: float) -> void:
	if _mesh == null or _anim == null:
		return
	var target := 0.0
	if _submerged:
		if _swim_moving:
			target = CompanionActor.SWIM_LIFT
		elif _staged:
			target = CompanionActor.SUBMERGED_STANDING_LIFT
		elif _anim.current_animation == "Swim_Idle":
			target = CompanionActor.SWIM_IDLE_LIFT
		else:
			target = CompanionActor.SUBMERGED_STANDING_LIFT
	var rate := maxf(CompanionActor.SWIM_LIFT, CompanionActor.SWIM_IDLE_LIFT) / CompanionActor.SWIM_BLEND_TIME
	_swim_offset = move_toward(_swim_offset, target, rate * delta)
	_mesh.position.y = _swim_offset


func _enter_idle() -> void:
	state = State.IDLE
	_timer = _rng.randf_range(IDLE_MIN, IDLE_MAX)
	velocity = Vector3.ZERO
	_gait(0.0)


func _enter_patrol() -> void:
	state = State.PATROL
	_gait(PATROL_SPEED)
	# Ancora o alvo na POSIÇÃO ATUAL, não em `_home`. O esquema antigo pegava
	# alvo em `_home + offset`, e uma criatura que tivesse drifted para o
	# extremo oeste do seu círculo podia receber o próximo alvo no extremo
	# leste — 12 m de distância no lado oposto. Como a criatura já estava
	# perto do limite de 0.6 m que encerra a patrulha, ela oscilava entre os
	# dois pontos, o que o usuário via como "presa no mesmo eixo com o bico
	# variando entre duas direções". Ancorar no `global_position` faz cada
	# patrulha ser uma perna genuína de caminhada.
	var away := global_position - _home
	away.y = 0.0
	var angle: float
	if away.length() > HOME_LEASH:
		# Longe demais: aponta de volta para casa com folga de ±90° para
		# a direção não ser rígida — a criatura ainda parece explorar, mas
		# no rumo geral do bioma dela.
		var back_angle := atan2(-away.z, -away.x)
		angle = back_angle + _rng.randf_range(-PI * 0.5, PI * 0.5)
	else:
		angle = _rng.randf() * TAU
	var dist := _rng.randf_range(1.5, PATROL_RADIUS)
	_patrol_target = global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _move_towards(target: Vector3, speed: float, delta: float) -> void:
	var dir := target - global_position
	dir.y = 0.0
	var distance := dir.length()
	if distance < 0.05:
		# Chegou. Zerar explicitamente evita o ping-pong do modelo antigo:
		# ele apenas retornava, e a velocidade do quadro anterior seguia
		# aplicada por `move_and_slide`, fazendo a criatura passar reto do
		# alvo, virar 180° no quadro seguinte para voltar, passar reto de
		# novo, e assim por diante — o que o usuário via como "bico
		# alternando entre duas direções sem transição visual".
		velocity.x = 0.0
		velocity.z = 0.0
		return
	dir = dir / distance
	# Cap a velocidade para não estourar o alvo neste quadro. Sem isto, o
	# último passo até o alvo de patrulha sempre passa alguns centímetros
	# além dele, o que reintroduz o mesmo ping-pong descrito acima.
	var step_speed: float = minf(speed, distance / maxf(delta, 0.0001))
	velocity.x = dir.x * step_speed
	velocity.z = dir.z * step_speed
	_face(dir, delta)


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var d := direction.normalized()
	# -Z é a frente no Godot, como no controlador do jogador.
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), clampf(8.0 * delta, 0.0, 1.0))


## Troca o clipe corrente com um blend curto. Silencioso quando o corpo é
## cápsula (`_anim` nulo) ou o modelo não tem o clipe — voadores não têm
## `Walk`, por exemplo, e seguem no `Idle` de flutuação.
func _play_clip(clip: String) -> void:
	if _anim == null:
		return
	if _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.2)


func _has_clip(clip: String) -> bool:
	return _anim != null and _anim.has_animation(clip)


## A criatura está debaixo d'água?
##
## Medido nos PÉS (a origem fica meia cápsula acima do chão — regra 5 do
## `CLAUDE.md`), pelo mesmo `MapTerrain.submerged` e pela mesma razão do
## jogador: é o pé que decide se o corpo já subiu a rampa. Sem terreno, ou fora
## da árvore (ainda sem `global_position`), a resposta é seco.
func submerged() -> bool:
	if terrain == null or not is_inside_tree():
		return false
	return terrain.submerged(global_position - Vector3(0.0, staged_ground_offset(), 0.0))


## A escada de marcha e meio deste corpo — a única, usada pela patrulha, pela
## encenação do duelo (`staged_gait`) e pela troca de meio. Mesma forma da de
## `GaitRig.update_motion`, escrita aqui e não herdada porque este corpo não é
## humano nem monta rig: só o vocabulário de clipes é compartilhado.
##
## Submerso: parado boia (`Swim_Idle`), em movimento nada (`Swim`). Corpo com
## `Swim` mas sem `Swim_Idle` dá braçada no lugar, que é o que um submerso faz;
## corpo sem nado nenhum cai na escada seca, como todo corpo caía antes de
## 2026-09-07, e `_play_clip` silencia no clipe ausente em vez de prender o
## corpo num clipe que ele não tem. Hoje os catorze do PZ-01 trazem os dois:
## onze chegaram do Meshy só com `Walk`/`Run` e receberam o conjunto do
## CRT-005 por transplante (`pnpm models:transfer` no bestiário).
##
## `Run` só quando o corpo tem o clipe: os placeholders variam, e `_play_clip`
## silencia no clipe ausente — pedir `Run` a quem não tem deixaria a criatura
## atravessar a cena parada. `Sprint` (investida do duelo, desde 2026-09-18)
## segue a mesma regra e cai em `Run` quando falta. Submerso não há degrau
## novo: a investida debaixo d'água é `Swim`, que é o que 87% do PZ-01 vê.
func _gait(speed: float) -> void:
	_submerged = submerged()
	_swim_moving = speed >= IDLE_SPEED
	if _submerged:
		if speed < IDLE_SPEED and _has_clip("Swim_Idle"):
			_play_clip("Swim_Idle")
			return
		if _has_clip("Swim"):
			_play_clip("Swim")
			return
	if speed < IDLE_SPEED:
		_play_clip("Idle")
	elif speed >= SPRINT_THRESHOLD and _has_clip("Sprint"):
		_play_clip("Sprint")
	elif speed >= RUN_THRESHOLD and _has_clip("Run"):
		_play_clip("Run")
	else:
		_play_clip("Walk")


## Toca um clipe de combate por NOME (`Attack`/`HitReact`/`Death`) — chamado
## pelo `EncounterDirector` durante o turno, fora da escada de marcha (esses
## três não têm velocidade associada). Mesmo contrato por nome do resto da
## encenação; silencioso se o corpo não tiver o clipe.
func play_battle_clip(clip: String) -> void:
	_play_clip(clip)


# ---------------------------------------------------------------------------
# contrato de encenação (BattleStaging)
# ---------------------------------------------------------------------------
#
# Durante o duelo o mundo está pausado: quem move, gira e escolhe a marcha
# deste corpo é a `BattleStaging`, por isso `_physics_process` cede tudo
# exceto a altura de nado (`_advance_swim_lift`) enquanto `_staged` — ver o
# comentário do campo. Estes dois métodos são tudo o que a encenação precisa
# saber dele, e são chamados por NOME (`Node.call`), não por tipo — a bancada
# da suíte de encenação monta a geometria com `Node3D` solto e não deve ser
# obrigada a implementar contrato nenhum.

## Quanto a origem do corpo fica acima do chão: meia cápsula, a mesma soma que
## `_build_body` aplica ao nascer. Derivada de `capsule_dimensions`, não
## guardada num campo, para não haver duas medidas do mesmo corpo.
func staged_ground_offset() -> float:
	return float(capsule_dimensions(size_meters)["height"]) * 0.5


## A marcha imposta pela encenação, na mesma escada da exploração (`_gait`) —
## inclusive o meio: um duelo engatado no leito do mar é nadado, não andado.
func staged_gait(speed: float) -> void:
	_gait(speed)


## Deixa o corpo animar com a árvore pausada, enquanto a encenação o move.
##
## `AnimationPlayer` é pausável como qualquer nó: sem isto o clipe escolhido
## acima fica **selecionado e congelado no quadro zero**, e a criatura
## atravessa a cena numa pose estática — o deslize que a encenação existe para
## acabar, de volta por outra porta. Ligado só enquanto a encenação é dona do
## corpo: ligado sempre, uma criatura pega no meio do `Walk` por uma tela de
## loja andaria no lugar em vez de ficar parada.
##
## Também liga `_staged` e o `process_mode` do PRÓPRIO corpo (não só do
## `AnimationPlayer`): é o mesmo truque de `GaitRig.animate_while_paused`,
## necessário porque a altura de nado (`_advance_swim_lift`) mora no
## `_physics_process` deste script, e nó pausado não processa. Sem isto ela
## congelava no valor que tinha no instante em que o mundo pausou — às vezes
## a meio caminho de um `move_toward` — e ficava presa ali a luta inteira,
## enquanto o clipe de golpe (fora da escada) tocava por cima sem ninguém
## reconciliar a altura com ele.
func staged_animating(enabled: bool) -> void:
	if _anim != null:
		_anim.process_mode = Node.PROCESS_MODE_ALWAYS if enabled else Node.PROCESS_MODE_INHERIT
	_staged = enabled
	process_mode = Node.PROCESS_MODE_ALWAYS if enabled else Node.PROCESS_MODE_INHERIT




## Permite reengajar depois de uma batalha resolvida.
func reset_engagement() -> void:
	_engaged_once = false
	set_selected(false)
	# A aura é do duelo e morre com ele. Sem isto, uma criatura que despertou
	# e sobreviveu (fuga, captura falha) voltaria a vagar pelo mapa acesa —
	# um estado de batalha vazando para a exploração.
	set_awakening_aura(false)
	_enter_idle()


## Realce visual da criatura selecionada pelo clique. Cápsula: toggle de
## emissão no próprio material. Modelo `.glb`: `material_overlay` translúcido
## por cima das malhas, sem mexer no material importado. Nenhum dos dois
## spawna node novo por seleção; a cor foi armazenada quando o corpo foi
## construído.
func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	_update_capsule_emission()
	if not _mesh_instances.is_empty():
		var overlay := _highlight_material if selected else null
		for mi in _mesh_instances:
			mi.material_overlay = overlay


func is_selected() -> bool:
	return _selected


## Liga e desliga a aura do Despertar Ancestral neste corpo.
##
## Chamado por NOME (`Node.call`) por quem conhece o estado da batalha, pelo
## mesmo motivo do contrato de encenação: assim a bancada de `Node3D` solto
## das suítes não é obrigada a implementar isto para ser encenada.
##
## São três coisas de uma vez, e as três importam: o disco de área do BinbunVFX
## desenha o efeito sustentado no chão, a `OmniLight3D` faz a criatura ILUMINAR
## o chão em volta (na câmera isométrica com névoa é a luz que se lê de
## longe), e o burst de "cast" marca o instante exato em que liga.
##
## `self` é o centro vertical da cápsula (`_build_body` soma meia altura à
## posição), não o chão — por isso o disco de área e o burst recebem o offset
## negativo explícito. `CompanionActor` tem a convenção oposta (regra 5 do
## CLAUDE.md) e por isso usa `0.0` na chamada equivalente.
##
## Corpo de cápsula (criatura sem `.glb`) não tem malha própria, mas o disco de
## área e o burst não dependem de malha — só a emissão extra da cápsula cai no
## mesmo canal do realce de seleção, e por isso o estado dos dois passa por
## `_update_capsule_emission` em vez de cada um escrever direto: quem desliga a
## seleção não pode apagar um Despertar que continua ativo.
func set_awakening_aura(active: bool) -> void:
	if _awakened == active:
		return
	_awakened = active

	if active:
		var ground_offset := -float(capsule_dimensions(size_meters)["height"]) * 0.5
		_aura_vfx = ElementPalette.attach_area_vfx(size_meters)
		if _aura_vfx != null:
			add_child(_aura_vfx)
			_aura_vfx.position.y = ground_offset
		_aura_light = ElementPalette.build_aura_light(size_meters)
		add_child(_aura_light)
		ElementPalette.play_awakening_cast(self, ground_offset, size_meters)
	else:
		ElementPalette.detach_area_vfx(_aura_vfx)
		_aura_vfx = null
		if _aura_light != null:
			_aura_light.queue_free()
			_aura_light = null

	_update_capsule_emission()


func is_awakened() -> bool:
	return _awakened


## Efeito de golpe/status, chamado por NOME pelo `EncounterDirector` a cada
## evento novo do log da batalha — mesmo contrato de `set_awakening_aura` e
## `staged_gait`: a bancada de `Node3D` solto das suítes não precisa
## implementar isto para ser encenada. Mesmo offset de chão que a aura usa
## (`self` é o centro vertical da cápsula, não o chão). `effect_element` é o
## elemento de quem AGIU (decidido pelo `EncounterDirector`), não
## necessariamente o deste corpo — hoje só o buff o usa pra se colorir.
func play_battle_effect(kind: String, effect_element: String, variant_seed: String, _source_creature_code: String = "") -> void:
	var ground_offset := -float(capsule_dimensions(size_meters)["height"]) * 0.5
	ElementPalette.play_battle_effect(self, ground_offset, size_meters, kind, variant_seed, effect_element)


## Altura do peito no espaço LOCAL deste corpo — onde um efeito que liga dois
## corpos (o feixe do Despertar) nasce e acerta. Mesma conta de apoio de
## `play_battle_effect`, mais a flutuação de nado: submersa, a malha sobe
## `_swim_offset` acima do ator, e sem somar isso o feixe sairia da cintura.
func battle_effect_height() -> float:
	return -float(capsule_dimensions(size_meters)["height"]) * 0.5 + size_meters * 0.5 + _swim_offset


## Feixe do golpe do Despertar, deste corpo até `target` — por NOME, como o
## resto do contrato de combate. O alvo diz a própria altura de peito pelo
## mesmo contrato; bancada de `Node3D` solto cai na origem dele.
func play_battle_beam(target: Node3D, effect_element: String, duration: float) -> void:
	var target_height := 0.0
	if target != null and is_instance_valid(target) and target.has_method("battle_effect_height"):
		target_height = float(target.call("battle_effect_height"))
	ElementPalette.play_battle_beam(
		self, battle_effect_height(), capsule_radius(size_meters),
		target, target_height, effect_element, duration)


func _update_capsule_emission() -> void:
	if _material != null:
		_material.emission_enabled = _selected or _awakened


## Marca a criatura como já engajada e emite o sinal. Chamado pelo WorldRoot
## no segundo clique — mantém o contrato de "só uma batalha por criatura até
## `reset_engagement`".
func request_engage() -> void:
	if _engaged_once:
		return
	_engaged_once = true
	engaged.emit(self)
