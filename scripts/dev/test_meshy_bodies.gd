extends SceneTree

## Valida o piloto do pipeline Meshy AI (multi-arquivo, um clipe por `.glb`,
## fundido por `avyron-bestiary/scripts/convert-meshy.mjs`) como corpo
## DEFINITIVO de criatura: chega com esqueleto e clipes PRÓPRIOS (não UAL),
## então o caminho normal de `CreatureActor._find_animation_player` já basta,
## sem retarget — mesmo contrato de "Easy Animated Pack".
##
## Diferente de um placeholder N:1, este é 1:1 com CRT-002 (Anomalocaris) via
## `modelUrl` no bundle (convenção `<CODE>.glb` solto em `models/`,
## sincronizada pelo `syncModels` do bestiário — ver
## `docs/MODEL_OPTIMIZATION.md`).
##
## A segunda metade (`_test_swim_ladder`) monta um `CreatureActor` de verdade
## no leito do mar e prende a escada de marcha E meio: submersa, a criatura
## boia parada e nada em movimento; seca, anda e corre. Depende de `_ready()`,
## que só dispara depois que a árvore roda um quadro — mesma pegadinha de
## `test_dungeon_bodies.gd` —, por isso a suíte espera 2 quadros em `_process`.
##
##     godot --headless --script res://scripts/dev/test_meshy_bodies.gd

const CODE := "CRT-002"

## Deriva horizontal tolerada num ciclo inteiro, em metros — o mesmo número de
## `test_characters.gd`. Um clipe in-place fecha onde abriu; os de criatura
## chegavam andando até 1,7 m.
const DRIFT_TOLERANCE := 0.05
const EXPECTED_CANONICAL_CLIPS := [
	"Idle", "Walk", "Run", "Attack", "Attack2", "Attack3", "HitReact", "Death", "Swim", "Swim_Idle", "Dodge",
]

var _failures := 0
var _checks := 0
var _frames := 0
var _actor: CreatureActor
var _terrain: MapTerrain


func _initialize() -> void:
	var db := BestiaryData.new()
	var err := db.load_bundle()
	if err != "":
		printerr("bundle nao carregou: ", err)
		quit(1)
		return

	var data := db.creature(CODE)
	_check_true("%s: existe no bundle" % CODE, not data.is_empty())
	if data.is_empty():
		db.free()
		quit(1)
		return

	var model_url := str(data.get("modelUrl", ""))
	_check_true("%s: modelUrl aponta pro .glb definitivo" % CODE, model_url == "/models/%s.glb" % CODE)

	var size_meters: float = data["stats"]["sizeMeters"]
	var element_code: String = data["element"]
	var visual := CreatureActor.build_visual(size_meters, element_code, CODE, model_url)

	var meshes: Array[MeshInstance3D] = visual.get("mesh_instances", [])
	_check_true("trouxe malha", not meshes.is_empty())

	var anim: AnimationPlayer = visual.get("anim")
	_check_true("tem AnimationPlayer proprio (sem retarget)", anim != null)
	if anim != null:
		for clip in EXPECTED_CANONICAL_CLIPS:
			_check_true("tem clipe canonico %s" % clip, anim.has_animation(clip))
		_check_true("Idle em loop", anim.has_animation("Idle")
			and anim.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR)
		_check_true("Swim em loop", anim.has_animation("Swim")
			and anim.get_animation("Swim").loop_mode == Animation.LOOP_LINEAR)
		_check_true("Swim_Idle em loop", anim.has_animation("Swim_Idle")
			and anim.get_animation("Swim_Idle").loop_mode == Animation.LOOP_LINEAR)
		_check_true("Death sem loop", anim.has_animation("Death")
			and anim.get_animation("Death").loop_mode == Animation.LOOP_NONE)
		_check_true("Dodge sem loop", anim.has_animation("Dodge")
			and anim.get_animation("Dodge").loop_mode == Animation.LOOP_NONE)
		print("\nclipes no arquivo: ", anim.get_animation_list())

	var height: float = visual.get("height", -1.0)
	var radius: float = visual.get("radius", -1.0)
	_check_true("altura de colisao > 0", height > 0.0)
	_check_true("raio de colisao > 0", radius > 0.0)

	(visual["mesh"] as Node3D).free()

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
	print("\n-- escada de marcha e meio (%s no leito do mar)" % CODE)
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

	# Corpo com `Swim` mas sem `Swim_Idle` dá braçada no lugar — é o caso de
	# qualquer criatura reconvertida só com o nado para a frente. Tirado da
	# biblioteca desta instância, não do arquivo.
	_actor.terrain = _terrain
	anim.get_animation_library("").remove_animation("Swim_Idle")
	_actor.staged_gait(0.0)
	_check_true("sem Swim_Idle, parada submersa cai para Swim (%s)" % anim.current_animation,
		anim.current_animation == "Swim")


## Nenhum clipe de nenhum corpo do elenco pode ANDAR sozinho — mesma regra que
## `test_characters.gd` prende no corpo do jogador, agora para TODA criatura
## com `modelUrl`. Quem move a criatura é o ator; um clipe com root motion faz
## a malha viajar em dobro e voltar de um salto a cada volta do ciclo — foi o
## "nada mais rápido e depois reseta" da companheira em 2026-09-08: `Swim`,
## `Attack2` e `Death` chegaram do Meshy andando 1,0–1,7 m por ciclo nos
## catorze corpos, convertidos antes de `convert-meshy.mjs` remover root
## motion, e o transplante do CRT-005 espalhou o defeito. Corrigido por
## `pnpm models:strip` no bestiário; isto impede a regressão.
##
## Mede o quadril em espaço do modelo (`_mesh` já está na árvore, então o
## `global_transform` do esqueleto aplica a escala cm→m do `Armature`).
func _test_clips_in_place() -> void:
	print("\n-- clipes in-place (sem root motion) em todo o elenco")
	var db := BestiaryData.new()
	db.load_bundle()
	var bodies := 0
	for c in db.creatures_in_map("PZ-01"):
		var url: Variant = c.get("modelUrl")
		if not url is String or url == "":
			continue
		var code := str(c["code"])
		var visual := CreatureActor.build_visual(float(c["stats"]["sizeMeters"]), str(c["element"]), code, url)
		var mesh: Node3D = visual["mesh"]
		var anim: AnimationPlayer = visual["anim"]
		root.add_child(mesh)
		var skel := GaitRig.find_skeleton(mesh)
		if anim == null or skel == null or skel.find_bone("Hips") < 0:
			_check_true("%s: AnimationPlayer, Skeleton3D e osso Hips" % code, false)
			mesh.free()
			continue
		bodies += 1
		var hips := skel.find_bone("Hips")
		var worst := 0.0
		var worst_clip := ""
		for clip in anim.get_animation_list():
			var start := _hips_at(mesh, anim, skel, hips, String(clip), 0.0)
			var finish := _hips_at(mesh, anim, skel, hips, String(clip), 1.0)
			var drift := Vector2(finish.x - start.x, finish.z - start.z).length()
			if drift > worst:
				worst = drift
				worst_clip = String(clip)
		_check_true("%s: todo clipe fecha onde abriu (pior: %s, %.3f m)" % [code, worst_clip, worst],
			worst < DRIFT_TOLERANCE)
		mesh.free()
	_check_true("%d corpos medidos (esperado 14)" % bodies, bodies == 14)
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
