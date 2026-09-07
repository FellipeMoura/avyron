extends SceneTree

## Validação headless dos DOIS corpos humanos do jogo.
##
##     godot --headless --script res://scripts/dev/test_characters.gd
##
## Desde 2026-09-07 são dois, montados de formas incompatíveis: o jogador vem
## de um `.glb` fechado (`PlayerRig`, `models/player.glb`) e os NPCs continuam
## sendo montados peça a peça pelo kit de personagens (`CharacterRig`). A suíte
## guarda cinco contratos: o manifest do kit (toda peça listada precisa ter
## recurso importado atrás dela), o corpo do jogador (clipes canônicos, loop e
## ausência de root motion), a escada de marcha que os dois dividem
## (`GaitRig`), a montagem das receitas `appearance` que o bundle traz para os
## NPCs, e a fusão das bibliotecas de animação com as trilhas re-endereçadas.
## Se o bestiário exportar uma receita com peça inexistente, ou uma conversão
## nova devolver um clipe que anda sozinho, estoura aqui — não como um NPC
## invisível ou um corpo escapando da cápsula em runtime.

## Uma receita do kit para exercitar a montagem de NPC. Era a
## `PlayerController.DEFAULT_RECIPE` até o jogador ganhar corpo próprio; ficou
## aqui como FIXTURE porque o kit precisa de alguma receita completa para ser
## testado, e as do bundle variam com o catálogo. Não representa ninguém.
const KIT_RECIPE := {
	"gender": "male",
	"hair": "Hair_SimpleParted",
	"body": "Male_Ranger_Body",
	"arms": "Male_Ranger_Arms",
	"legs": "Male_Ranger_Legs",
	"feet": "Male_Ranger_Feet_Boots",
}

## Deriva horizontal tolerada num ciclo inteiro, em metros. Um clipe in-place
## fecha onde abriu; o `Swim_Forward` do Meshy chegava andando 2,21 m.
const DRIFT_TOLERANCE := 0.05

var _failures := 0
var _checks := 0

## O corpo medido no `_process`: pose de osso exige a árvore viva, e no
## `_initialize` todo clipe mediria igual (o `AnimationPlayer` não aplica pose
## nenhuma antes de a árvore existir).
var _staged: PlayerRig


func _initialize() -> void:
	_test_manifest()
	_test_player_body()
	_test_gait_ladder()
	_test_kit_rig()
	_test_npc_rigs()
	_test_animation_library()

	_staged = PlayerRig.create()
	if _staged != null:
		get_root().add_child(_staged)


func _process(_delta: float) -> bool:
	_test_clips_in_place()

	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)
	return true


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s%s" % [label, " — " + detail if detail != "" else ""])


func _skeleton_meshes(rig: CharacterRig) -> Array:
	var skeleton: Skeleton3D = null
	for child in rig.find_children("*", "Skeleton3D", true, false):
		skeleton = child
		break
	if skeleton == null:
		return []
	var meshes := []
	for child in skeleton.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).visible:
			meshes.append(child)
	return meshes


func _anim_of(rig: Node) -> AnimationPlayer:
	for child in rig.find_children("*", "AnimationPlayer", true, false):
		return child as AnimationPlayer
	return null


# ---------------------------------------------------------------------------
# manifest: toda peça listada resolve para recurso importado
# ---------------------------------------------------------------------------

func _test_manifest() -> void:
	print("manifest do kit:")
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CharacterRig.MANIFEST_PATH))
	_check("manifest.json presente e legível", raw is Dictionary)
	if not raw is Dictionary:
		return

	var entries: Array = []
	for body in raw.get("bodies", []):
		entries.append(body.get("url", ""))
		entries.append(body.get("headUrl", ""))
	for section in ["hair", "outfitParts", "animations"]:
		for entry in raw.get(section, []):
			entries.append(entry.get("url", ""))

	var missing := []
	for url in entries:
		if url == "" or not ResourceLoader.exists("res://" + str(url).trim_prefix("/")):
			missing.append(url)
	_check(
		"%d recursos do manifest importados" % entries.size(),
		missing.is_empty(),
		"faltando: %s" % str(missing),
	)
	_check("2 corpos com variante de cabeça", raw.get("bodies", []).size() == 2)


# ---------------------------------------------------------------------------
# corpo do jogador (models/player.glb, clipes próprios, sem retarget)
# ---------------------------------------------------------------------------

## O contrato do corpo do jogador é o VOCABULÁRIO, não a montagem: o `.glb`
## chega do Meshy com esqueleto e clipes próprios, e é a normalização de nome
## feita por `convert-meshy.mjs` que faz a escada de marcha encontrar o que
## pedir. Um export novo que perca o mapeamento de um clipe cai aqui.
func _test_player_body() -> void:
	print("corpo do jogador:")
	var rig := PlayerRig.create()
	_check("montou de %s" % PlayerRig.MODEL_PATH, rig != null)
	if rig == null:
		return

	for clip in ["Idle", "Walk", "Run", "Swim", "Swim_Idle", "Harvest", "Throw"]:
		_check("clipe canônico %s disponível" % clip, rig.has_clip(clip))

	var anim := _anim_of(rig)
	_check("AnimationPlayer próprio (sem retarget)", anim != null)
	if anim != null:
		for clip in ["Idle", "Walk", "Run", "Swim", "Swim_Idle"]:
			_check("%s em loop" % clip,
				anim.get_animation(clip).loop_mode == Animation.LOOP_LINEAR)
		# Gesto único: quem quiser repetir relança. `Harvest` marcado em loop
		# tiraria de `_advance_mining_loop` a única razão de existir.
		for clip in ["Harvest", "Throw"]:
			_check("%s sem loop" % clip,
				anim.get_animation(clip).loop_mode == Animation.LOOP_NONE)

	# O `Swim` deste corpo já nasce pairando acima da origem do rig — herdar o
	# levantamento de 0,9 m do corpo UAL o penduraria boiando (ver PlayerRig).
	_check("nao levanta no nado (swim_lift = 0)", is_zero_approx(rig.swim_lift))
	# Regra 4 do CLAUDE.md: o modelo olha para +Z e a frente de um nó é -Z.
	var body := rig.get_node_or_null("Body") as Node3D
	_check("corpo girado para encarar -Z",
		body != null and is_equal_approx(body.rotation.y, PlayerRig.MODEL_YAW))
	rig.free()


## Nenhum clipe pode ANDAR sozinho: quem move este corpo é o `CharacterBody3D`,
## e um clipe com root motion o faria viajar em dobro — a malha escapando da
## cápsula durante o ciclo e voltando de um salto quando ele reinicia. O
## `Swim_Forward` do Meshy chegou exatamente assim (2,21 m em 4,57 s) e é
## corrigido na conversão; este teste é o que impede a correção de se perder
## numa reconversão futura.
func _test_clips_in_place() -> void:
	print("clipes in-place (sem root motion):")
	if _staged == null:
		_check("corpo do jogador na árvore para medir", false)
		return
	var anim := _anim_of(_staged)
	var skel := GaitRig.find_skeleton(_staged)
	if anim == null or skel == null:
		_check("AnimationPlayer e Skeleton3D presentes", false)
		return
	var hips := skel.find_bone("Hips")
	_check("osso raiz Hips encontrado", hips >= 0)
	if hips < 0:
		return

	for clip in anim.get_animation_list():
		var start := _hips_at(anim, skel, hips, String(clip), 0.0)
		var finish := _hips_at(anim, skel, hips, String(clip), 1.0)
		var drift := Vector2(finish.x - start.x, finish.z - start.z).length()
		_check("%s fecha onde abriu (%.3f m)" % [clip, drift], drift < DRIFT_TOLERANCE)


## Posição do quadril em METROS, no espaço do rig. Passa pelo
## `global_transform` do esqueleto de propósito: o `.glb` do Meshy vem em
## centímetros com a escala no nó `Armature`, e ler a pose crua daria um número
## cem vezes maior sem nenhum sinal de que está errado.
func _hips_at(anim: AnimationPlayer, skel: Skeleton3D, bone: int, clip: String, ratio: float) -> Vector3:
	var a := anim.get_animation(clip)
	anim.play(clip)
	anim.seek(a.length * ratio, true)
	skel.force_update_all_bone_transforms()
	var world: Transform3D = skel.global_transform * skel.get_bone_global_pose(bone)
	return _staged.global_transform.affine_inverse() * world.origin


# ---------------------------------------------------------------------------
# a escada de marcha e o meio
# ---------------------------------------------------------------------------

## O corpo escolhe o clipe pela marcha E pelo meio. As duas asserções que
## importam são as pontas: correr a 5,2 m/s (a velocidade real do jogador —
## tocar `Walk` ali é o deslize que motivou a escada) e nadar submerso, que no
## PZ-01 é o estado NORMAL da exploração, porque o mapa é o leito de um mar.
##
## Medida no corpo do JOGADOR, que é quem de fato anda, nada e minera. A escada
## é a mesma para os NPCs porque mora em `GaitRig` e não em nenhum dos dois
## corpos — é justamente o que o segundo corpo obrigou a separar.
func _test_gait_ladder() -> void:
	print("escada de marcha:")
	var rig := PlayerRig.create()
	if rig == null:
		_check("montou o corpo para medir a escada", false)
		return
	var anim := _anim_of(rig)

	var cases := [
		[0.0, false, "Idle"],
		[1.2, false, "Walk"],
		[PlayerController.WALK_SPEED, false, "Run"],
		[0.0, true, "Swim"],
		[PlayerController.WALK_SPEED, true, "Swim"],
	]
	for c in cases:
		rig.update_motion(float(c[0]), bool(c[1]))
		_check("%4.1f m/s %s -> %s" % [c[0], "submerso" if c[1] else "seco  ", c[2]],
			anim.current_animation == c[2], anim.current_animation)

	# Parado embaixo d'água continua nadando, e não é descuido: `Swim_Idle` é
	# pose de boiar na superfície e alternar com `Swim` faria o corpo pular
	# quase um metro a cada parada.
	_check("o corpo tem Swim_Idle, e ele fica de fora de propósito", rig.has_clip("Swim_Idle"))

	# Mineração tem prioridade sobre a escada normal, mesmo parado (é assim
	# que WorldRoot sempre chama: só liga `mining` com o corpo já parado).
	rig.update_motion(0.0, false, true)
	_check("mining=true toca Harvest mesmo parado", anim.current_animation == "Harvest",
		anim.current_animation)
	# Fim da sessão: a escada normal assume de volta sozinha.
	rig.update_motion(0.0, false, false)
	_check("mining=false volta para Idle", anim.current_animation == "Idle",
		anim.current_animation)

	rig.free()


# ---------------------------------------------------------------------------
# montagem do kit (fixture): o sistema visual dos NPCs
# ---------------------------------------------------------------------------

func _test_kit_rig() -> void:
	print("montagem do kit:")
	var rig := CharacterRig.create(KIT_RECIPE)
	_check("montou a partir de uma receita completa", rig != null)
	if rig == null:
		return

	var meshes := _skeleton_meshes(rig)
	# Corpo (cabeça + olhos + sobrancelha) = 3, mais cabelo e 4 peças de roupa.
	_check("%d malhas penduradas no esqueleto (esperado >= 8)" % meshes.size(), meshes.size() >= 8)

	for clip in ["Idle", "Walk", "Run", "Swim", "Attack", "Throw", "Consume", "Death"]:
		_check("clipe %s disponível" % clip, rig.has_clip(clip))
	# O kit levanta o nadador; o corpo do jogador não. A diferença é medida do
	# clipe, não do sistema — ver `CharacterRig.SWIM_LIFT`.
	_check("kit levanta o nadador", is_equal_approx(rig.swim_lift, CharacterRig.SWIM_LIFT))
	_check("receita vazia devolve null (fallback de cápsula)", CharacterRig.create({}) == null)
	rig.free()


# ---------------------------------------------------------------------------
# rigs dos NPCs (receitas do bundle)
# ---------------------------------------------------------------------------

func _test_npc_rigs() -> void:
	print("rigs de NPC (bundle):")
	var db := BestiaryData.new()
	var err := db.load_bundle()
	_check("bundle carregou", err == "", err)
	if err != "":
		db.free()
		return

	var dressed := 0
	for code in db.merchant_codes() + db.duelist_codes():
		var data: Dictionary = db.merchant(code)
		if data.is_empty():
			data = db.duelist(code)
		var recipe: Variant = data.get("appearance")
		if not recipe is Dictionary or (recipe as Dictionary).is_empty():
			continue
		var rig := CharacterRig.create(recipe)
		_check("rig de %s montou" % code, rig != null)
		if rig != null:
			_check(
				"%s: malhas no esqueleto" % code,
				_skeleton_meshes(rig).size() >= 7,
			)
			rig.free()
			dressed += 1
	_check("ao menos um NPC vestido no bundle", dressed > 0)
	db.free()


# ---------------------------------------------------------------------------
# biblioteca de animação: fusão UAL1+UAL2, loop e re-endereçamento
# ---------------------------------------------------------------------------

func _test_animation_library() -> void:
	print("biblioteca de animação:")
	var rig := CharacterRig.create(KIT_RECIPE)
	if rig == null:
		_check("rig para inspecionar a biblioteca", false)
		return
	var anim := _anim_of(rig)
	_check("AnimationPlayer presente", anim != null)
	if anim == null:
		rig.free()
		return

	# UAL1 traz 35 clipes e UAL2 traz 38 — fundidos sem colisão de nome.
	_check(
		"%d clipes na biblioteca fundida (esperado 73)" % anim.get_animation_list().size(),
		anim.get_animation_list().size() == 73,
	)
	_check("Idle em loop", anim.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR)
	_check("Death sem loop", anim.get_animation("Death").loop_mode == Animation.LOOP_NONE)

	# Toda trilha precisa apontar para o esqueleto DESTE rig (osso via subname).
	var idle := anim.get_animation("Idle")
	var retargeted := true
	for track in idle.get_track_count():
		var path := idle.track_get_path(track)
		if path.get_subname_count() == 0 or not String(path).begins_with("Body/"):
			retargeted = false
			break
	_check("trilhas de Idle re-endereçadas para o esqueleto do rig", retargeted)
	rig.free()
