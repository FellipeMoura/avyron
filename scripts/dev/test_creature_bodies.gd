extends SceneTree

## O contrato de TODO corpo de criatura com `modelUrl` (fluxo base + casca do
## bestiário, `../avyron-bestiary/scripts/convert-tripo.mjs`): chega sem clipe,
## num esqueleto com os nomes da UAL, e `CreatureActor` lhe dá a biblioteca
## inteira do jogo por retarget — o mesmo caminho do placeholder Imp.
##
## Três coisas presas aqui, sobre o elenco inteiro do PZ-01:
##
## 1. `_test_contract` — o primeiro corpo do mapa monta com esqueleto, ganha o
##    vocabulário do jogo por retarget e os loops certos (contínuos em loop,
##    `Death` não).
## 2. `_test_swim_ladder` — um `CreatureActor` de verdade no leito do mar
##    prende a escada de marcha E meio: submersa, boia parada e nada em
##    movimento; seca, anda e corre. Depende de `_ready()`, que só dispara
##    depois que a árvore roda um quadro, por isso a suíte espera 2 quadros.
## 3. `_test_clips_in_place` — nenhum clipe de nenhum corpo anda sozinho.
##
## Até 2026-09-17 esta suíte era `test_meshy_bodies.gd` e prendia o contrato
## do corpo Meshy (esqueleto próprio de 24 ossos com `Hips`, clipes bakeados
## no arquivo, `Dodge` obrigatório). Esse contrato acabou com o elenco.
##
##     godot --headless --script res://scripts/dev/test_creature_bodies.gd

const MAP := "PZ-01"

## Vocabulário que o jogo toca em criatura — `_gait`, `play_battle_clip` e o
## `EncounterDirector`. `Dodge` não está: nenhum script o toca e a UAL não o
## tem. `Death` está: `EncounterDirector` o toca no falecimento.
const EXPECTED_CLIPS := ["Idle", "Walk", "Run", "Swim", "Swim_Idle", "Attack", "Attack2", "Attack3", "HitReact", "Death"]

## Deriva horizontal tolerada num ciclo inteiro, em metros — o mesmo número de
## `test_characters.gd`. Um clipe in-place fecha onde abriu.
const DRIFT_TOLERANCE := 0.05
## Clipes medidos pela regra "fecha onde abriu": os loops de marcha e nado e
## os golpes que voltam ao Idle. `Death` fica de fora porque termina deitado.
const DRIFT_CHECKED_CLIPS := ["Idle", "Walk", "Run", "Swim", "Swim_Idle", "Attack", "Attack2", "Attack3", "HitReact"]

var _failures := 0
var _checks := 0
var _frames := 0
var _code := ""
var _actor: CreatureActor
var _terrain: MapTerrain


func _initialize() -> void:
	var db := BestiaryData.new()
	var err := db.load_bundle()
	if err != "":
		printerr("bundle nao carregou: ", err)
		quit(1)
		return

	var data := {}
	for c in db.creatures_in_map(MAP):
		var url: Variant = c.get("modelUrl")
		if url is String and url != "":
			data = c
			break
	_check_true("%s tem ao menos uma criatura com modelUrl" % MAP, not data.is_empty())
	if data.is_empty():
		db.free()
		quit(1)
		return
	_code = str(data["code"])

	_test_contract(data)

	# A criatura de verdade, nascida no leito do mar aberto — o mesmo ponto que
	# `test_companion.gd` e `test_playable.gd` usam como sonda de "mar aberto".
	# O terreno entra ANTES da árvore, como o spawner faz: `_ready` já escolhe o
	# primeiro clipe, e sem relevo ali ela nasceria andando.
	_terrain = MapTerrain.create({})
	_terrain.water_line = MapDressing.PZ01_WATER_LINE
	var half := float(MapTerrain.SIZE) * 0.5
	var spot := Vector3(half * 0.5, 0.0, half * 0.67)
	spot.y = _terrain.height_at(spot)
	_actor = CreatureActor.create(data, spot, 1)
	_actor.terrain = _terrain
	root.add_child(_actor)
	db.free()


func _test_contract(data: Dictionary) -> void:
	print("\n-- contrato do corpo (%s)" % _code)
	var model_url := str(data.get("modelUrl", ""))
	_check_true("%s: modelUrl no padrao /models/<CODE>.glb" % _code, model_url == "/models/%s.glb" % _code)

	var visual := CreatureActor.build_visual(float(data["stats"]["sizeMeters"]), str(data["element"]), _code, model_url)
	var meshes: Array[MeshInstance3D] = visual.get("mesh_instances", [])
	_check_true("trouxe malha", not meshes.is_empty())
	if not meshes.is_empty():
		var mi: MeshInstance3D = meshes[0]
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		_check_true("malha skinada num Skeleton3D", skel != null)
		if skel != null:
			_check_true("esqueleto com os nomes da UAL (pelvis, hand_l)", skel.find_bone("pelvis") != -1 and skel.find_bone("hand_l") != -1)
			_check_true("sem osso Hips (contrato Meshy encerrado)", skel.find_bone("Hips") == -1)

	var anim: AnimationPlayer = visual.get("anim")
	_check_true("ganhou AnimationPlayer por retarget", anim != null)
	if anim != null:
		for clip in EXPECTED_CLIPS:
			_check_true("clipe %s disponivel" % clip, anim.has_animation(clip))
		for clip in ["Idle", "Walk", "Swim", "Swim_Idle"]:
			_check_true("%s em loop" % clip, anim.has_animation(clip)
				and anim.get_animation(clip).loop_mode == Animation.LOOP_LINEAR)
		_check_true("Death sem loop", anim.has_animation("Death")
			and anim.get_animation("Death").loop_mode == Animation.LOOP_NONE)

	_check_true("altura de colisao > 0", float(visual.get("height", -1.0)) > 0.0)
	_check_true("raio de colisao > 0", float(visual.get("radius", -1.0)) > 0.0)
	(visual["mesh"] as Node3D).free()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	_test_swim_ladder()
	_test_clips_in_place()

	_actor.free()
	_terrain.free()
	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)
	return true


## A escada de marcha e meio de `CreatureActor._gait`, pela porta da encenação
## (`staged_gait`), que é a mesma da patrulha. As pontas que importam: nascer
## submersa já boiando, e trocar `Swim_Idle`/`Swim` por `Idle`/`Walk`/`Run` no
## seco sem mudar nada além do meio.
func _test_swim_ladder() -> void:
	print("\n-- escada de marcha e meio (%s no leito do mar)" % _code)
	var anim: AnimationPlayer = _actor.get("_anim")
	_check_true("ator montou com AnimationPlayer", anim != null)
	if anim == null:
		return
	_check_true("nasceu submersa", _actor.submerged())
	_check_true("nasce boiando (Swim_Idle), nao em Idle: %s" % anim.current_animation,
		anim.current_animation == "Swim_Idle")

	var wet_cases := [[CreatureActor.PATROL_SPEED, "Swim"], [0.0, "Swim_Idle"], [3.0, "Swim"]]
	for c in wet_cases:
		_actor.staged_gait(float(c[0]))
		_check_true("submersa a %.1f m/s -> %s (%s)" % [c[0], c[1], anim.current_animation],
			anim.current_animation == c[1])

	# Seca: o mesmo corpo, a mesma escada, sem o meio.
	_actor.terrain = null
	var dry_cases := [[0.0, "Idle"], [CreatureActor.PATROL_SPEED, "Walk"], [3.0, "Run"]]
	for c in dry_cases:
		_actor.staged_gait(float(c[0]))
		_check_true("seca a %.1f m/s -> %s (%s)" % [c[0], c[1], anim.current_animation],
			anim.current_animation == c[1])

	# Corpo com `Swim` mas sem `Swim_Idle` dá braçada no lugar. Tirado da
	# biblioteca desta instância, não do arquivo — e como a biblioteca é
	# compartilhada por esqueleto, é devolvido no fim.
	_actor.terrain = _terrain
	var library := anim.get_animation_library("")
	var swim_idle := library.get_animation("Swim_Idle")
	library.remove_animation("Swim_Idle")
	_actor.staged_gait(0.0)
	_check_true("sem Swim_Idle, parada submersa cai para Swim (%s)" % anim.current_animation,
		anim.current_animation == "Swim")
	library.add_animation("Swim_Idle", swim_idle)


## Nenhum clipe de nenhum corpo do elenco pode ANDAR sozinho — mesma regra que
## `test_characters.gd` prende no corpo do jogador. Quem move a criatura é o
## ator; um clipe com root motion faz a malha viajar em dobro e voltar de um
## salto a cada volta do ciclo. Para os corpos retargetados quem remove a
## viagem é `CharacterRig._build_library`, na montagem — o `Attack3` da UAL
## chegava andando 15 cm em escala chibi (medido em 2026-09-16).
##
## Mede o quadril em espaço do modelo (`_mesh` já está na árvore, então o
## `global_transform` do esqueleto aplica a escala do corpo).
func _test_clips_in_place() -> void:
	print("\n-- clipes in-place (sem root motion) em todo o elenco")
	var db := BestiaryData.new()
	db.load_bundle()
	var bodies := 0
	var expected := 0
	for c in db.creatures_in_map(MAP):
		var url: Variant = c.get("modelUrl")
		if not url is String or url == "":
			continue
		expected += 1
		var code := str(c["code"])
		var visual := CreatureActor.build_visual(float(c["stats"]["sizeMeters"]), str(c["element"]), code, url)
		var mesh: Node3D = visual["mesh"]
		var anim: AnimationPlayer = visual["anim"]
		root.add_child(mesh)
		var skel := GaitRig.find_skeleton(mesh)
		var hips := -1 if skel == null else skel.find_bone("pelvis")
		if anim == null or skel == null or hips < 0:
			_check_true("%s: AnimationPlayer, Skeleton3D e osso pelvis" % code, false)
			mesh.free()
			continue
		bodies += 1
		var worst := 0.0
		var worst_clip := ""
		for clip in anim.get_animation_list():
			if not (String(clip) in DRIFT_CHECKED_CLIPS):
				continue
			var start := _hips_at(mesh, anim, skel, hips, String(clip), 0.0)
			var finish := _hips_at(mesh, anim, skel, hips, String(clip), 1.0)
			var drift := Vector2(finish.x - start.x, finish.z - start.z).length()
			if drift > worst:
				worst = drift
				worst_clip = String(clip)
		_check_true("%s: todo clipe fecha onde abriu (pior: %s, %.3f m)" % [code, worst_clip, worst],
			worst < DRIFT_TOLERANCE)
		mesh.free()
	_check_true("%d corpos medidos (esperado %d, todo corpo do %s com modelUrl)" % [bodies, expected, MAP], bodies == expected)
	db.free()


## Posição do quadril em METROS no espaço do modelo, no instante `ratio` do
## clipe. `force_update_all_bone_transforms` porque `seek` com update não
## propaga para o esqueleto até o próximo quadro.
func _hips_at(mesh: Node3D, anim: AnimationPlayer, skel: Skeleton3D, bone: int, clip: String, ratio: float) -> Vector3:
	anim.play(clip)
	anim.seek(anim.get_animation(clip).length * ratio, true)
	skel.force_update_all_bone_transforms()
	var world: Transform3D = skel.global_transform * skel.get_bone_global_pose(bone)
	return mesh.global_transform.affine_inverse() * world.origin


func _check_true(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
