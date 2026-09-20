extends SceneTree

## Validação headless do corpo humano do jogo — jogador e NPCs.
##
##     godot --headless --script res://scripts/dev/test_characters.gd
##
## Desde 2026-09-17 é um sistema só: todo humano, jogador incluído, é montado
## peça a peça pelo kit de personagens (`CharacterRig`) e animado pelas
## bibliotecas UAL por retarget. Entre 2026-09-07 e 17 o jogador teve um `.glb`
## fechado do Meshy (`PlayerRig`); voltou ao kit para não manter um segundo
## pipeline de asset por um corpo só. A suíte guarda cinco contratos: o
## manifest do kit (toda peça listada precisa ter recurso importado atrás
## dela), o corpo do jogador (a receita monta, os clipes que ele usa existem,
## loop e ausência de root motion), a escada de marcha (`GaitRig`), a montagem
## das receitas `appearance` que o bundle traz para os NPCs, e a fusão das
## bibliotecas de animação com as trilhas re-endereçadas.
## Se o bestiário exportar uma receita com peça inexistente, ou uma conversão
## nova devolver um clipe que anda sozinho, estoura aqui — não como um NPC
## invisível ou um corpo escapando da cápsula em runtime.

## Uma receita do kit para exercitar a montagem de NPC, como FIXTURE: o kit
## precisa de alguma receita completa para ser testado, e as do bundle variam
## com o catálogo. Não representa ninguém — a do jogador é
## `PlayerController.PLAYER_RECIPE`, testada à parte.
const KIT_RECIPE := {
	"gender": "male",
	"hair": "Hair_SimpleParted",
	"body": "Male_Ranger_Body",
	"arms": "Male_Ranger_Arms",
	"legs": "Male_Ranger_Legs",
	"feet": "Male_Ranger_Feet_Boots",
}

## Deriva horizontal tolerada num ciclo inteiro, em metros. Um clipe in-place
## fecha onde abriu; a montagem da biblioteca (`CharacterRig._build_library`)
## tira a viagem líquida do quadril de cada clipe da UAL.
const DRIFT_TOLERANCE := 0.05

var _failures := 0
var _checks := 0

## O corpo medido no `_process`: pose de osso exige a árvore viva, e no
## `_initialize` todo clipe mediria igual (o `AnimationPlayer` não aplica pose
## nenhuma antes de a árvore existir).
var _staged: CharacterRig


func _initialize() -> void:
	_test_manifest()
	_test_player_body()
	_test_gait_ladder()
	_test_kit_rig()
	_test_npc_rigs()
	_test_animation_library()

	_staged = CharacterRig.create(PlayerController.PLAYER_RECIPE)
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
# corpo do jogador (receita fixa do kit, `PlayerController.PLAYER_RECIPE`)
# ---------------------------------------------------------------------------

## O contrato do corpo do jogador é o VOCABULÁRIO, não a montagem: a receita
## precisa montar (toda peça existe no manifest) e a biblioteca UAL precisa
## trazer o que a escada de marcha e o `WorldRoot` pedem — `Harvest` para
## minerar e `Throw` para o arremesso de captura. Uma peça renomeada no kit ou
## um clipe que suma na conversão das bibliotecas cai aqui.
func _test_player_body() -> void:
	print("corpo do jogador:")
	var rig := CharacterRig.create(PlayerController.PLAYER_RECIPE)
	_check("montou a partir de PlayerController.PLAYER_RECIPE", rig != null)
	if rig == null:
		return
	_check("%d malhas penduradas no esqueleto (esperado >= 8)" % _skeleton_meshes(rig).size(), _skeleton_meshes(rig).size() >= 8)

	for clip in ["Idle", "Walk", "Run", "Swim", "Swim_Idle", "Harvest", "Throw"]:
		_check("clipe canônico %s disponível" % clip, rig.has_clip(clip))

	var anim := _anim_of(rig)
	_check("AnimationPlayer por retarget presente", anim != null)
	if anim != null:
		for clip in ["Idle", "Walk", "Run", "Swim", "Swim_Idle"]:
			_check("%s em loop" % clip,
				anim.get_animation(clip).loop_mode == Animation.LOOP_LINEAR)
		# Gesto único: quem quiser repetir relança. `Harvest` marcado em loop
		# tiraria de `_advance_mining_loop` a única razão de existir.
		for clip in ["Harvest", "Throw"]:
			_check("%s sem loop" % clip,
				anim.get_animation(clip).loop_mode == Animation.LOOP_NONE)

	# O `Swim` da UAL deita o nadador em torno da origem do rig: o kit o levanta
	# 0,9 m, e o jogador, sendo kit, também — ver `CharacterRig.SWIM_LIFT`.
	_check("levanta no nado (swim_lift do kit)", is_equal_approx(rig.swim_lift, CharacterRig.SWIM_LIFT))
	# Regra 4 do CLAUDE.md: o modelo olha para +Z e a frente de um nó é -Z.
	var body := rig.get_node_or_null("Body") as Node3D
	_check("corpo girado para encarar -Z",
		body != null and is_equal_approx(body.rotation.y, PI))
	rig.free()


## Nenhum clipe pode ANDAR sozinho: quem move este corpo é o `CharacterBody3D`,
## e um clipe com root motion o faria viajar em dobro — a malha escapando da
## cápsula durante o ciclo e voltando de um salto quando ele reinicia. O
## antigo `Attack3` da UAL (hoje `Sword_Dash`/`Attack2`) chegava assim (o
## quadril terminava 40 cm à frente num humano) e é corrigido na montagem da
## biblioteca; este teste é o que impede a correção de se perder.
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
	var hips := skel.find_bone("pelvis")
	_check("osso do quadril (pelvis) encontrado", hips >= 0)
	if hips < 0:
		return

	for clip in anim.get_animation_list():
		# `Death` termina deitado: o quadril sai do lugar de propósito, e a
		# montagem da biblioteca o deixa de fora da remoção de root motion.
		if String(clip) == "Death":
			continue
		var start := _hips_at(anim, skel, hips, String(clip), 0.0)
		var finish := _hips_at(anim, skel, hips, String(clip), 1.0)
		var drift := Vector2(finish.x - start.x, finish.z - start.z).length()
		_check("%s fecha onde abriu (%.3f m)" % [clip, drift], drift < DRIFT_TOLERANCE)


## Posição do quadril em METROS, no espaço do rig, pelo `global_transform` do
## esqueleto — a pose crua ignoraria qualquer escala que o import bakeie.
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
## importam são as pontas: correr a `PlayerController.WALK_SPEED` (3,12 m/s
## desde 2026-09-17, era 5,2 — tocar `Walk` ali é o deslize que motivou a
## escada) e nadar submerso, que no PZ-01 é o estado NORMAL da exploração,
## porque o mapa é o leito de um mar. Esta suíte mede a escada CRUA de
## `GaitRig` (`allow_run` no default `true`) — o jogador de verdade passa
## `allow_run = false` e nunca toca `Run` (ver `PlayerController`).
##
## Medida no corpo do JOGADOR, que é quem de fato anda, nada e minera. A escada
## mora em `GaitRig`, então vale igual para os NPCs.
func _test_gait_ladder() -> void:
	print("escada de marcha:")
	var rig := CharacterRig.create(PlayerController.PLAYER_RECIPE)
	if rig == null:
		_check("montou o corpo para medir a escada", false)
		return
	var anim := _anim_of(rig)

	var cases := [
		[0.0, false, "Idle"],
		[1.2, false, "Walk"],
		[PlayerController.WALK_SPEED, false, "Run"],
		[0.0, true, "Swim_Idle"],
		[PlayerController.WALK_SPEED, true, "Swim"],
		[0.0, true, "Swim_Idle"],
	]
	for c in cases:
		rig.update_motion(float(c[0]), bool(c[1]))
		_check("%4.1f m/s %s -> %s" % [c[0], "submerso" if c[1] else "seco  ", c[2]],
			anim.current_animation == c[2], anim.current_animation)

	# Corpo sem `Swim_Idle` continua dando braçada no lugar. Tirado da
	# biblioteca, que é compartilhada por esqueleto — e devolvido em seguida.
	var library := anim.get_animation_library("")
	var swim_idle := library.get_animation("Swim_Idle")
	library.remove_animation("Swim_Idle")
	rig.update_motion(0.0, true)
	_check("sem Swim_Idle, parado submerso cai para Swim", anim.current_animation == "Swim",
		anim.current_animation)
	library.add_animation("Swim_Idle", swim_idle)

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
	# O kit levanta o nadador — medida do clipe da UAL, ver `CharacterRig.SWIM_LIFT`.
	_check("kit levanta o nadador", is_equal_approx(rig.swim_lift, CharacterRig.SWIM_LIFT))
	# O boiador da UAL pende mais fundo que o nadador — cota própria, maior.
	_check("kit levanta o boiador ainda mais",
		is_equal_approx(rig.swim_idle_lift, CharacterRig.SWIM_IDLE_LIFT)
		and rig.swim_idle_lift > rig.swim_lift)
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

	# As duas receitas FIXAS do jogo (posto e bancada não são NPC de catálogo —
	# ver `RelicStationActor.NPC_RECIPE`). Montam do mesmo kit, pela mesma
	# porta; se uma peça sair do manifest, é aqui que aparece, não na vila.
	for fixed in [["posto", RelicStationActor.NPC_RECIPE], ["bancada", CraftingBenchActor.NPC_RECIPE]]:
		var fixed_rig := CharacterRig.create(fixed[1])
		_check("receita fixa do %s montou" % fixed[0], fixed_rig != null)
		if fixed_rig != null:
			_check("%s: malhas no esqueleto" % fixed[0], _skeleton_meshes(fixed_rig).size() >= 7)
			fixed_rig.free()


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
	# As poses dos NPCs da vila existem na biblioteca fundida e estão em loop —
	# fora de `LOOPED_CLIPS` o clipe congela no último quadro (ver o comentário
	# da constante).
	for pose in [MerchantActor.NPC_CLIP, RelicStationActor.NPC_CLIP, CraftingBenchActor.NPC_CLIP]:
		_check("%s existe e esta em loop" % pose,
			anim.has_animation(pose) and anim.get_animation(pose).loop_mode == Animation.LOOP_LINEAR)

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
