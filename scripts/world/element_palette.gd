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

const BODY_SHADER := "res://shaders/element_palette.gdshader"
const AURA_SHADER := "res://shaders/awakening_aura.gdshader"

## Prefixo dos corpos que aceitam recoloração. Ver "Em quais corpos a paleta
## entra".
const PLACEHOLDER_PREFIX := "res://models/placeholders/"

## Cinza de engenharia, para elemento sem paleta no bundle (ou sem bundle
## nenhum — bancada solta). Não é escolha de arte: é o "não sei de que cor
## isto é" visível, e o export já avisa alto quando um elemento chega assim.
const NEUTRAL_MID := Color("#6B7280")
const NEUTRAL_HIGHLIGHT := Color("#F2EDE0")

## Espessura da casca da aura como fração do maior eixo do AABB da malha —
## relativa, para o halo de um trilobita e o de um Arthropleura terem a mesma
## leitura. Ver `awakening_aura.gdshader`.
const AURA_GROW_RATIO := 0.035

## A luz é o que faz a aura ler na câmera isométrica com névoa: a criatura
## desperta ILUMINA o chão em volta, e isso se vê de longe mesmo quando o halo
## é fino. Alcance deriva do tamanho do corpo, pelo mesmo motivo da espessura.
const AURA_LIGHT_RANGE_RATIO := 3.5
const AURA_LIGHT_ENERGY := 1.6
const AURA_ENERGY := 1.0

const AURA_SHELL_PREFIX := "AwakeningAura_"

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


## Cor do meio da rampa. É a cor "da criatura" quando só cabe uma — cápsula de
## fallback, realce de seleção, qualquer lugar que antes lia `ELEMENT_COLORS`.
static func mid_color(element_code: String) -> Color:
	return _stop(element_code, "mid", NEUTRAL_MID)


static func shadow_color(element_code: String) -> Color:
	return _stop(element_code, "shadow", NEUTRAL_MID.darkened(0.6))


static func highlight_color(element_code: String) -> Color:
	return _stop(element_code, "highlight", NEUTRAL_HIGHLIGHT)


## Cor da aura do Despertar. Cai para o highlight quando o elemento não a
## autora — o export garante que `aura` chega preenchida, mas a queda existe
## para bundle antigo não apagar a aura em silêncio.
static func aura_color(element_code: String) -> Color:
	var p := palette(element_code)
	if p.has("aura"):
		return Color(str(p["aura"]))
	return highlight_color(element_code)


## Deslocamento desta criatura dentro da família, em [-spread, +spread].
##
## Derivado do CÓDIGO, não sorteado: a mesma criatura tem de sair da mesma cor
## em toda partida, em todo save e nos dois corpos que a representam (selvagem
## no mapa e companheira ao lado do jogador). Um `RandomNumberGenerator` daria
## variedade e quebraria as três coisas.
static func creature_bias(creature_code: String, element_code: String) -> float:
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
	if palette(element_code).is_empty():
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
			mi.set_surface_override_material(surface, _body_material(element_code, atlas))
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

## Cria a casca da aura como IRMÃ de cada malha do corpo e devolve as cascas.
##
## Irmã, e não filha, porque o `skeleton` de um `MeshInstance3D` rigado é um
## NodePath relativo: mantida a vizinhança, ele continua resolvendo para o
## mesmo `Skeleton3D` e a casca acompanha a animação sem código de sincronia.
## Ver `awakening_aura.gdshader`.
##
## Lista vazia = corpo sem malha importada (cápsula). Quem chama trata esse
## caso acendendo a emissão da própria cápsula.
static func attach_aura(
	mesh_instances: Array[MeshInstance3D],
	element_code: String,
) -> Array[MeshInstance3D]:
	var shells: Array[MeshInstance3D] = []
	var color := aura_color(element_code)
	for mi in mesh_instances:
		var parent := mi.get_parent()
		if mi.mesh == null or parent == null:
			continue
		var shell := mi.duplicate(0) as MeshInstance3D
		if shell == null:
			continue
		shell.name = AURA_SHELL_PREFIX + mi.name
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# `material_override` e não override por superfície: a casca é uma
		# camada inteira, e o corpo por baixo continua com a paleta dele.
		shell.material_override = _aura_material(color, _mesh_extent(mi))
		parent.add_child(shell)
		# O `skeleton` vem copiado pela duplicação, mas só resolve depois de o
		# nó entrar na árvore — reatribuir aqui é o que garante que a casca
		# rigada não fique parada na pose de repouso.
		shell.skeleton = mi.skeleton
		shell.set_instance_shader_parameter("aura_energy", AURA_ENERGY)
		shells.append(shell)
	return shells


static func detach_aura(shells: Array[MeshInstance3D]) -> void:
	for shell in shells:
		if is_instance_valid(shell):
			shell.queue_free()


## Luz que a criatura desperta joga no chão. Quem chama é dono do nó — some
## junto com a aura.
static func build_aura_light(element_code: String, size_meters: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "AwakeningLight"
	light.light_color = aura_color(element_code)
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

static func _stop(element_code: String, key: String, fallback: Color) -> Color:
	var p := palette(element_code)
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


static func _body_material(element_code: String, atlas: Texture2D) -> ShaderMaterial:
	var key := "%s|%s" % [element_code, _texture_key(atlas)]
	var cached: Variant = _body_materials.get(key)
	if cached is ShaderMaterial:
		return cached

	var material := ShaderMaterial.new()
	material.shader = load(BODY_SHADER) as Shader
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("ramp", _ramp_texture(element_code))
	_body_materials[key] = material
	return material


## Rampa como `GradientTexture1D`: três paradas, sombra em 0, meio em 0.5,
## brilho em 1. O shader amostra por luminância, então a posição de cada
## parada É o significado dela.
static func _ramp_texture(element_code: String) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		shadow_color(element_code),
		mid_color(element_code),
		highlight_color(element_code),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func _aura_material(color: Color, extent: float) -> ShaderMaterial:
	# Sem cache, ao contrário do material de corpo: `grow` depende do AABB da
	# malha, que muda por criatura, e no máximo dois corpos estão despertos ao
	# mesmo tempo num duelo 1v1.
	var material := ShaderMaterial.new()
	material.shader = load(AURA_SHADER) as Shader
	# `Color`, não `Vector3`: o uniform é `vec3 : source_color`, e o hint só
	# converte o espaço de cor quando o valor chega como cor. Mandando vetor,
	# o uniform fica no default e a aura sai branca — que foi exatamente o
	# primeiro screenshot desta função.
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("grow", extent * AURA_GROW_RATIO)
	return material


## Maior eixo do AABB da malha, em espaço de MODELO — que é onde o shader
## infla o vértice. Usar o tamanho de jogo aqui daria espessura errada: entre
## os dois há o fator de escala que `CreatureActor` aplica ao wrapper.
static func _mesh_extent(mi: MeshInstance3D) -> float:
	var size := mi.get_aabb().size
	return maxf(size.x, maxf(size.y, size.z))


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
