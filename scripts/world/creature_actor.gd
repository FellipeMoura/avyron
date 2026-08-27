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
## O corpo usa `.glb` quando `res://<código>.glb` existe (`CRT-006`, `CRT-010`
## hoje) e cai para a cápsula escalada pelo tamanho de jogo e colorida pelo
## elemento quando não. O que é definitivo independe de qual dos dois: escala
## real em unidades Godot, máquina de estados de navegação, colisão — só a
## malha visual muda de fonte.
##
## Especificação: `movimento-e-controles`, seção "IA no mapa".

enum State { IDLE, PATROL }

const PATROL_SPEED := 1.2

## Marcha da encenação de duelo a partir da qual o corpo corre em vez de andar,
## e abaixo da qual conta como parado. Só valem lá: a patrulha anda sempre, a
## `PATROL_SPEED`, e por isso nunca chega perto do limiar de corrida.
const RUN_THRESHOLD := 2.0
const STAGED_IDLE_SPEED := 0.05

const IDLE_MIN := 1.5
const IDLE_MAX := 4.0
const PATROL_RADIUS := 6.0

## Coleira até `_home`. Quando a criatura ultrapassa esta distância, o próximo
## alvo de patrulha vem enviesado de volta em vez de sorteio livre — sem isso
## ela pode vagar indefinidamente para fora do bioma.
const HOME_LEASH := 8.0

## Multiplicador de energia da emissão quando a criatura está selecionada.
## Um valor baixo evita "queimar" a cor do elemento — o realce tem de ser lido
## como "esta é a selecionada", não como um efeito de luz forte.
const SELECT_EMISSION_ENERGY := 0.55

signal engaged(actor: CreatureActor)

var creature_code := ""
var display_name := ""
var element_code := ""
var size_meters := 1.8
var model_url := ""

var state: State = State.IDLE
var _home := Vector3.ZERO
var _patrol_target := Vector3.ZERO
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _engaged_once := false

var _mesh: Node3D
var _collision: CollisionShape3D
var _material: StandardMaterial3D
var _mesh_instances: Array[MeshInstance3D] = []
var _highlight_material: StandardMaterial3D
var _selected := false
var _anim: AnimationPlayer

## Aura do Despertar Ancestral: cascas irmãs das malhas do corpo, mais a luz
## que a criatura joga no chão. Vazio/`null` fora do Despertar — a aura não
## existe como nó desligado, ela nasce e morre com a transformação. Ver
## `set_awakening_aura`.
var _awakened := false
var _aura_shells: Array[MeshInstance3D] = []
var _aura_light: OmniLight3D

## Localização do modelo, em ordem de prioridade:
##
## 1. O `modelUrl` do bundle (`/models/...`), espelhado pelo `pnpm game:export`
##    em `res://models/...`. É assim que os placeholders compartilhados chegam:
##    várias criaturas podem apontar o mesmo `.glb`, e é o bestiário — não uma
##    convenção de nome — que decide qual corpo cada uma usa.
## 2. Legado: `CRT-XXX.glb` na raiz do projeto (os modelos do Meshy, sem
##    animação). Só vale quando a criatura não tem `modelUrl` resolvível.
##
## Sem arquivo em nenhum dos dois, `build_visual` cai para a cápsula.
const MODEL_PATH_FORMAT := "res://%s.glb"
const MODEL_URL_PREFIX := "/models/"
const MODEL_DIR := "res://models/"

## Clipes que devem rodar em loop. O importador de glTF não marca loop em
## nada, então um `Idle` tocado cru congela no último quadro; e marcar TODOS
## seria pior — `Death` em loop é uma criatura morrendo para sempre. A lista
## segue o vocabulário normalizado dos placeholders (ver
## `convert-placeholders.mjs` no bestiário).
const LOOPED_CLIPS := ["Idle", "Idle2", "IdleLow", "Walk", "Run", "Eating", "Jump_Idle"]


## Resolve o caminho do `.glb` de uma criatura, ou "" quando não há arquivo.
static func model_path(creature_code_value: String, model_url_value: String) -> String:
	if model_url_value.begins_with(MODEL_URL_PREFIX):
		var bundled := MODEL_DIR + model_url_value.trim_prefix(MODEL_URL_PREFIX)
		if ResourceLoader.exists(bundled):
			return bundled
	if creature_code_value != "":
		var legacy := MODEL_PATH_FORMAT % creature_code_value
		if ResourceLoader.exists(legacy):
			return legacy
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
		_highlight_material = _build_highlight_material(element_code)


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


## Constrói o visual de uma criatura: `.glb` em `res://<código>.glb` quando
## existe, cápsula colorida pelo elemento quando não. Devolve um dicionário
## com os nós e as medidas — o CompanionActor consome o mesmo layout, pra
## manter a leitura consistente entre selvagem e domesticada.
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
		# A recoloração entra AQUI, e não dentro de `_build_model_visual`,
		# porque ela é decisão de ELEMENTO e não de arquivo: esta função monta
		# tanto o corpo da selvagem quanto o da companheira, e as duas têm de
		# sair da mesma cor. `ElementPalette` decide sozinha quando recusar —
		# corpo fora dos placeholders, elemento sem paleta — e nesse caso o
		# `.glb` fica exatamente como veio.
		var meshes: Array[MeshInstance3D] = model["mesh_instances"]
		ElementPalette.apply_body(meshes, element_code, creature_code, path)
		return model
	return build_capsule_visual(size_meters, element_code)


## Tenta montar o visual a partir do caminho resolvido por `model_path`.
## Devolve dicionário vazio quando não há caminho ou o arquivo não traz
## nenhuma malha — quem chama cai para a cápsula nesse caso.
##
## A escala do arquivo é desconhecida a priori (o pipeline de exportação não
## garante 1 unidade = 1 metro), então esta função mede o AABB combinado das
## malhas e escala pelo MAIOR eixo até bater com `size_meters` — é esse eixo,
## não a altura, que carrega o "tamanho" de um artrópode comprido e baixo como
## Eurypterus. Depois recentra em X/Z e apoia a base em Y no mesmo ponto onde a
## cápsula apoiaria, para colisão e visual concordarem sobre onde é o chão.
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
	var extent := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if extent <= 0.0:
		instance.queue_free()
		return {}

	var factor: float = size_meters / extent
	var center := aabb.get_center()
	var height: float = dims["height"]

	# Os `.glb` de CRT-006 e CRT-010 saem da exportação com a cabeça em +Z, não
	# -Z — confirmado visualmente com marcadores em `shot_model_swap.gd` (a
	# cauda ficava no lado marcado como frente pela convenção do código). Sem
	# este giro, `_face()` viraria a criatura para o rumo do movimento e ela
	# andaria de costas, a cauda na frente — a mesma classe de bug da regra 4
	# do CLAUDE.md, só que na malha em vez do cálculo de ângulo.
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

	# Os placeholders chegam rigados com o vocabulário normalizado de clipes
	# (Idle/Walk/Run/Attack/...). O corpo já nasce em `Idle`; quem move a
	# criatura troca de clipe via `_play_clip`. Modelo sem AnimationPlayer
	# (os .glb legados do Meshy) fica parado, como sempre ficou.
	var anim := _find_animation_player(instance)
	if anim != null:
		_prepare_animations(anim)
		if anim.has_animation("Idle"):
			anim.play("Idle")

	return {
		"mesh": wrapper,
		"material": null,
		"mesh_instances": mesh_instances,
		"anim": anim,
		"height": height,
		"radius": dims["radius"],
	}


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


## Marca loop nos clipes contínuos — ver `LOOPED_CLIPS` sobre por que não são
## todos. Mexe no recurso Animation da instância importada, não no arquivo.
static func _prepare_animations(player: AnimationPlayer) -> void:
	for anim_name in player.get_animation_list():
		if String(anim_name) in LOOPED_CLIPS:
			player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


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
		var world: AABB = _transform_relative_to(mi, root) * mi.get_aabb()
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
## O realce usa o HIGHLIGHT da rampa, não o meio dela: desde que o corpo passou
## a ser recolorido pelo próprio elemento, um realce na cor do meio seria a cor
## que a criatura já tem — a seleção não apareceria justamente onde deveria.
static func _build_highlight_material(element_code: String) -> StandardMaterial3D:
	var color := ElementPalette.highlight_color(element_code)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.35)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = SELECT_EMISSION_ENERGY
	return material


## Constrói o visual placeholder: cápsula colorida pelo elemento.
##
## O material com emissão preparada (desligada) já sai daqui, então quem quiser
## acender o realce depois só precisa de `emission_enabled = true`.
static func build_capsule_visual(size_meters: float, element_code: String) -> Dictionary:
	var dims := capsule_dimensions(size_meters)
	var radius: float = dims["radius"]
	var height: float = dims["height"]

	var mesh := CapsuleMesh.new()
	mesh.height = height
	mesh.radius = radius

	var material := StandardMaterial3D.new()
	material.albedo_color = ElementPalette.mid_color(element_code)
	material.roughness = 0.9
	material.emission = ElementPalette.highlight_color(element_code)
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


func _enter_idle() -> void:
	state = State.IDLE
	_timer = _rng.randf_range(IDLE_MIN, IDLE_MAX)
	velocity = Vector3.ZERO
	_play_clip("Idle")


func _enter_patrol() -> void:
	state = State.PATROL
	_play_clip("Walk")
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


# ---------------------------------------------------------------------------
# contrato de encenação (BattleStaging)
# ---------------------------------------------------------------------------
#
# Durante o duelo o mundo está pausado e o `_physics_process` daqui não roda:
# quem move e anima este corpo é a `BattleStaging`. Estes dois métodos são tudo
# o que ela precisa saber dele, e são chamados por NOME (`Node.call`), não por
# tipo — a bancada da suíte de encenação monta a geometria com `Node3D` solto e
# não deve ser obrigada a implementar contrato nenhum.

## Quanto a origem do corpo fica acima do chão: meia cápsula, a mesma soma que
## `_build_body` aplica ao nascer. Derivada de `capsule_dimensions`, não
## guardada num campo, para não haver duas medidas do mesmo corpo.
func staged_ground_offset() -> float:
	return float(capsule_dimensions(size_meters)["height"]) * 0.5


## A marcha imposta pela encenação, na mesma escada da exploração. `Run` só
## quando o corpo tem o clipe: os placeholders variam, e `_play_clip` silencia
## no clipe ausente — pedir `Run` a quem não tem deixaria a criatura atravessar
## a cena parada.
func staged_gait(speed: float) -> void:
	if speed < STAGED_IDLE_SPEED:
		_play_clip("Idle")
	elif speed >= RUN_THRESHOLD and _anim != null and _anim.has_animation("Run"):
		_play_clip("Run")
	else:
		_play_clip("Walk")


## Deixa o corpo animar com a árvore pausada, enquanto a encenação o move.
##
## `AnimationPlayer` é pausável como qualquer nó: sem isto o clipe escolhido
## acima fica **selecionado e congelado no quadro zero**, e a criatura
## atravessa a cena numa pose estática — o deslize que a encenação existe para
## acabar, de volta por outra porta. Ligado só enquanto a encenação é dona do
## corpo: ligado sempre, uma criatura pega no meio do `Walk` por uma tela de
## loja andaria no lugar em vez de ficar parada.
func staged_animating(enabled: bool) -> void:
	if _anim != null:
		_anim.process_mode = Node.PROCESS_MODE_ALWAYS if enabled else Node.PROCESS_MODE_INHERIT




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
## São duas coisas de uma vez, e as duas importam: a casca aditiva desenha o
## halo colado na silhueta, e a `OmniLight3D` faz a criatura ILUMINAR o chão
## em volta. Na câmera isométrica com névoa, é a luz que se lê de longe — o
## halo sozinho some no meio do cenário.
##
## Corpo de cápsula (criatura sem `.glb`) não tem malha para inflar, e cai na
## emissão do próprio material, que é o mesmo canal do realce de seleção. Por
## isso o estado dos dois passa por `_update_capsule_emission` em vez de cada
## um escrever direto: quem desliga a seleção não pode apagar um Despertar
## que continua ativo.
func set_awakening_aura(active: bool) -> void:
	if _awakened == active:
		return
	_awakened = active

	if active:
		_aura_shells = ElementPalette.attach_aura(_mesh_instances, element_code)
		_aura_light = ElementPalette.build_aura_light(element_code, size_meters)
		add_child(_aura_light)
	else:
		ElementPalette.detach_aura(_aura_shells)
		_aura_shells.clear()
		if _aura_light != null:
			_aura_light.queue_free()
			_aura_light = null

	_update_capsule_emission()


func is_awakened() -> bool:
	return _awakened


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
