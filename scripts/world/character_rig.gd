class_name CharacterRig
extends Node3D

## Corpo humano montado em runtime a partir de uma receita de aparência.
##
## Player e NPCs são o MESMO sistema visual: o kit de personagens
## (`models/characters/`, espelhado pelo bestiário) traz corpos, cabelos e
## peças de outfit todos rigados no mesmo esqueleto de 65 ossos. Uma receita
## é um dicionário de nomes de peça — a do NPC vem do bundle
## (`appearance` em merchants/duelists), a do jogador é hardcoded hoje e
## virá de tela de criação amanhã. Montar é: instanciar o corpo, pendurar as
## malhas das peças no esqueleto dele, e dar um AnimationPlayer com as
## bibliotecas UAL re-endereçadas para esse esqueleto.
##
## Duas decisões herdadas do pack, documentadas no conversor do bestiário
## (`scripts/convert-characters.mjs`):
##
## - **Vestido, o corpo é só a cabeça.** As peças de roupa SUBSTITUEM tronco,
##   braços, pernas e pés (trazem a própria pele exposta); o corpo inteiro por
##   baixo vazaria pela roupa durante a animação. Por isso existe a variante
##   `Head_*`, com a malha de pele cortada pelos pesos de skinning — usada
##   sempre que a receita veste os quatro slots de roupa.
## - **Clipes já chegam no vocabulário do jogo** (`Idle`, `Walk`, `Run`,
##   `Attack`, `Throw`…), como os placeholders de criatura. As duas
##   bibliotecas (UAL1/UAL2) não colidem em nome de clipe — o conversor
##   aborta se colidirem — então podem se fundir numa biblioteca única.
##
## O rig nasce com os pés em y=0 local; quem o adiciona à cena decide o
## offset (atores de cápsula colocam em `-altura/2`, ver MerchantActor).

## Mesmo contrato de loop do CreatureActor: só clipes contínuos, nunca
## `Death`/`Attack`/`Throw` — o importador de glTF não marca loop em nada.
const LOOPED_CLIPS := [
	"Idle", "Walk", "Run", "Sprint", "Talk", "Sit", "Sit_Talk",
	"Crouch", "Crouch_Walk", "Swim", "Swim_Idle", "Jump_Idle",
	"Cast_Idle", "Push", "Walk_Carry", "Dance",
]

## Marcha a partir da qual o corpo corre em vez de andar, em m/s. Constante de
## apresentação — é a transição andar/correr de um humano real (~2 m/s), não um
## número que um designer ajuste no bestiário.
const RUN_THRESHOLD := 2.2

## Quanto o corpo do nadador sobe em relação aos próprios pés, em metros.
##
## O clipe `Swim` DEITA o corpo (medido: 2,31 m de comprimento por 0,22 m de
## altura) em torno da origem do rig — que são os pés. Tocado cru, o nadador
## fica arrastando a barriga no leito. Esta constante o põe pairando acima
## dele, que é onde um mergulhador sobre o fundo se lê.
##
## Constante e não medida da pose viva: o ponto mais baixo do esqueleto oscila
## ao longo da braçada, e amarrar a altura a ele faria o corpo quicar ao
## contrário do movimento dos membros — o mesmo defeito que impede usar essa
## medida num ciclo de caminhada.
const SWIM_LIFT := 0.9

## Tempo de entrar e sair da flutuação. Casado com o crossfade de clipe (0,2 s)
## e um pouco maior: o corpo tem de acabar de deitar antes de estar todo no
## alto, senão ele sobe de pé e depois deita, que lê como elevador.
const SWIM_BLEND_TIME := 0.35



const KIT_DIR := "res://models/characters"
const MANIFEST_PATH := KIT_DIR + "/manifest.json"
const ANIM_LIBRARIES := ["UAL1", "UAL2"]

## Slots de roupa da receita, na ordem de vestir. `body`..`feet` são os que
## escondem o corpo base; `head`/`accessory` são opcionais por natureza.
const OUTFIT_SLOTS := ["body", "arms", "legs", "feet", "head", "accessory"]
const COVERING_SLOTS := ["body", "arms", "legs", "feet"]

## Índices do manifest, montados uma vez por sessão: nome de peça → url.
static var _kit: Dictionary = {}

## Bibliotecas de animação já re-endereçadas, por caminho de esqueleto.
## Compartilhadas entre todos os rigs — Animation é recurso, não nó.
static var _anim_libs: Dictionary = {}

var _anim: AnimationPlayer
var _skeleton: Skeleton3D
## O nó do corpo, que sobe quando ele nada (ver SWIM_CLEARANCE).
var _body: Node3D
var _swimming := false
var _float_blend := 0.0


## Monta um rig a partir da receita. Devolve `null` para receita vazia ou
## kit ausente — quem chama cai para a cápsula, mesmo contrato do
## `CreatureActor.build_visual` com modelo faltando.
static func create(recipe: Dictionary) -> CharacterRig:
	if recipe.is_empty():
		return null
	var kit := _load_kit()
	if kit.is_empty():
		return null

	var gender := str(recipe.get("gender", "male"))
	var body: Dictionary = kit.get("bodies", {}).get(gender, {})
	if body.is_empty():
		push_warning("CharacterRig: corpo para gênero '%s' não está no manifest" % gender)
		return null

	# Vestido por completo, o corpo entra só como cabeça (ver docstring).
	var covered := true
	for slot in COVERING_SLOTS:
		if _slot(recipe, slot) == "":
			covered = false
			break
	var body_url := str(body.get("headUrl", body.get("url", ""))) if covered else str(body.get("url", ""))

	var packed := load(_res_path(body_url)) as PackedScene
	if packed == null:
		push_warning("CharacterRig: corpo '%s' não carregou" % body_url)
		return null

	var rig := CharacterRig.new()
	rig.name = "CharacterRig"
	var body_instance := packed.instantiate() as Node3D
	body_instance.name = "Body"
	# Os modelos do kit olham para +Z, como os placeholders de criatura; a
	# frente de um nó no jogo é -Z (regra 4 do CLAUDE.md). Mesmo giro que o
	# CreatureActor aplica.
	body_instance.rotation.y = PI
	rig.add_child(body_instance)
	# Guardado porque é ELE que sobe quando o corpo nada — não o rig. O rig é
	# o nó cuja posição o dono define ("os pés em y=0 local"), e mexer nela
	# aqui brigaria com quem o montou.
	rig._body = body_instance


	rig._skeleton = _find_skeleton(body_instance)
	if rig._skeleton == null:
		push_warning("CharacterRig: corpo '%s' sem Skeleton3D" % body_url)
		rig.free()
		return null

	# Sobrancelha da receita substitui a que o corpo base já traz.
	if _slot(recipe, "eyebrows") != "":
		var builtin := body_instance.find_children("Eyebrows", "MeshInstance3D", true, false)
		for node in builtin:
			(node as MeshInstance3D).visible = false

	for slot in ["hair", "eyebrows", "beard"]:
		rig._attach(kit.get("hair", {}), _slot(recipe, slot))
	for slot in OUTFIT_SLOTS:
		rig._attach(kit.get("parts", {}), _slot(recipe, slot))

	rig._build_animation()
	return rig


## Troca de clipe com o mesmo contrato do CreatureActor: silencia quando o
## clipe não existe, não reinicia o que já toca.
func play_clip(clip: String) -> void:
	if _anim == null:
		return
	if _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.2)


func has_clip(clip: String) -> bool:
	return _anim != null and _anim.has_animation(clip)


## Escolhe o clipe pela marcha real e pelo meio: parado, andando, correndo ou
## nadando — mesmo limiar de repouso do CompanionActor.
##
## Era binário (`Idle`/`Walk`) e por isso o jogador deslizava: ele se move a
## `PlayerController.WALK_SPEED` = 5,2 m/s, que é marcha de CORRIDA (humano
## andando faz ~1,4 m/s), e o ciclo de `Walk` foi calibrado a 4,0 antes de a
## velocidade subir 30%. Nenhum blend cobre uma defasagem dessa ordem — o que
## faltava era o clipe certo, não um ajuste de mistura.
##
## A escada fica aqui, e não no chamador, porque humano é UM sistema visual:
## um NPC que um dia passear a 1,5 m/s ganha o `Walk` pela mesma chamada que
## dá `Run` ao jogador. Trocar o literal por "Run" teria tirado o andar do
## sistema inteiro para consertar um corpo só.
##
## `swimming` vem de fora porque quem sabe onde a água está é o mundo, não o
## corpo: no PZ-01 é `MapTerrain.submerged`, e é o estado NORMAL da exploração
## — o mapa é o leito de um mar, e só o platô da costa é seco.
func update_motion(speed: float, swimming: bool = false, idle_threshold: float = 0.05) -> void:
	# Guardado antes de qualquer saída: é `_process` quem faz o corpo subir, e
	# ele precisa saber do meio mesmo que o clipe de nado não exista.
	_swimming = swimming

	if swimming and has_clip("Swim"):
		# `Swim` também parado, de propósito. O kit traz um `Swim_Idle`, mas ele
		# é pose de boiar na SUPERFÍCIE: o corpo inteiro pendura 1,41 m abaixo
		# da origem do rig, contra 0,19 m do `Swim`. Alternar entre os dois
		# obrigaria o corpo a subir e descer 1,2 m a cada parada — e, aqui, os
		# pés do boiador entrariam no leito, porque a coluna d'água do PZ-01 não
		# tem 1,65 m de folga. Quem paraliza embaixo d'água continua dando
		# braçada para ficar no lugar, o que é o que um corpo submerso faz.
		play_clip("Swim")
		return

	if speed < idle_threshold:
		play_clip("Idle")
		return
	# `has_clip` antes de pedir `Run`: `play_clip` silencia no clipe ausente,
	# e silenciar aqui deixaria o corpo preso no clipe anterior em vez de cair
	# para o `Walk`, que todo rig do kit tem.
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


## Sobe o corpo quando ele nada, e o devolve ao chão quando ele sai da água.
##
## Só a BORDA é interpolada — entrar e sair d'água. Dentro do nado a altura é
## fixa de propósito: um único clipe de locomoção submersa, uma única cota, e
## nenhum salto vertical no meio da exploração.
func _advance_float(delta: float) -> void:
	if _body == null:
		return
	_float_blend = move_toward(_float_blend, 1.0 if _swimming else 0.0, delta / SWIM_BLEND_TIME)
	_body.position.y = SWIM_LIFT * _float_blend




# ---------------------------------------------------------------------------
# montagem
# ---------------------------------------------------------------------------

## Instancia a cena da peça e transplanta as malhas para o esqueleto do
## corpo. Funciona porque toda peça é rigada no MESMO esqueleto (mesmos
## nomes, mesma ordem de ossos) — o Skin importado resolve os binds contra o
## Skeleton3D novo sem retarget.
func _attach(index: Dictionary, part_name: String) -> void:
	if part_name == "":
		return
	var entry: Dictionary = index.get(part_name, {})
	if entry.is_empty():
		push_warning("CharacterRig: peça '%s' não está no manifest" % part_name)
		return
	var packed := load(_res_path(str(entry.get("url", "")))) as PackedScene
	if packed == null:
		push_warning("CharacterRig: peça '%s' não carregou" % part_name)
		return
	var instance := packed.instantiate()
	for mesh in _collect_meshes(instance):
		# owner precisa cair ANTES do reparent — depois, o Godot reclama de
		# dono inconsistente (o dono antigo é a cena da peça, que será freed).
		mesh.owner = null
		mesh.get_parent().remove_child(mesh)
		_skeleton.add_child(mesh)
		mesh.skeleton = NodePath("..")
	instance.free()


## Funde UAL1+UAL2 numa biblioteca única com os caminhos das trilhas
## apontando para o esqueleto deste rig. A biblioteca é construída uma vez
## por caminho de esqueleto e compartilhada entre rigs — o que cada rig tem
## de próprio é só o AnimationPlayer.
func _build_animation() -> void:
	var skeleton_path := String(get_path_to(_skeleton))
	if not _anim_libs.has(skeleton_path):
		_anim_libs[skeleton_path] = _build_library(skeleton_path)
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	add_child(_anim)
	_anim.add_animation_library("", _anim_libs[skeleton_path])
	if _anim.has_animation("Idle"):
		_anim.play("Idle")


static func _build_library(skeleton_path: String) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for lib_name in ANIM_LIBRARIES:
		var packed := load("%s/animations/%s.glb" % [KIT_DIR, lib_name]) as PackedScene
		if packed == null:
			push_warning("CharacterRig: biblioteca %s não carregou" % lib_name)
			continue
		var instance := packed.instantiate()
		var source := _find_animation_player(instance)
		if source == null:
			instance.free()
			continue
		for clip_name in source.get_animation_list():
			# Duplicado porque o recurso importado é compartilhado com a cena
			# de origem, e as trilhas serão reescritas.
			var anim: Animation = source.get_animation(clip_name).duplicate(true)
			for track in range(anim.get_track_count() - 1, -1, -1):
				var path := anim.track_get_path(track)
				if path.get_subname_count() == 0:
					# Trilha sem osso (transform do nó raiz) não tem alvo no
					# rig montado — as bibliotecas são a versão sem root
					# motion, então isso é defensivo, não esperado.
					anim.remove_track(track)
					continue
				anim.track_set_path(
					track,
					NodePath("%s:%s" % [skeleton_path, path.get_concatenated_subnames()]),
				)
			if String(clip_name) in LOOPED_CLIPS:
				anim.loop_mode = Animation.LOOP_LINEAR
			library.add_animation(clip_name, anim)
		instance.free()
	return library


# ---------------------------------------------------------------------------
# manifest
# ---------------------------------------------------------------------------

static func _load_kit() -> Dictionary:
	if not _kit.is_empty():
		return _kit
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("CharacterRig: manifest do kit ausente em %s" % MANIFEST_PATH)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not raw is Dictionary:
		push_warning("CharacterRig: manifest do kit ilegível")
		return {}
	var bodies := {}
	for body in raw.get("bodies", []):
		bodies[str(body.get("gender", ""))] = body
	var hair := {}
	for entry in raw.get("hair", []):
		hair[str(entry.get("name", ""))] = entry
	var parts := {}
	for entry in raw.get("outfitParts", []):
		parts[str(entry.get("name", ""))] = entry
	_kit = {"bodies": bodies, "hair": hair, "parts": parts}
	return _kit


static func _res_path(url: String) -> String:
	return "res://" + url.trim_prefix("/")


## Valor de um slot da receita como String, tratando o `null` que o JSON do
## bundle carrega nos slots opcionais (`str(null)` viraria "<null>").
static func _slot(recipe: Dictionary, key: String) -> String:
	var value: Variant = recipe.get(key)
	return str(value) if value != null else ""


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


static func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_meshes(child))
	return out
