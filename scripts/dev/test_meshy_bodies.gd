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
##     godot --headless --script res://scripts/dev/test_meshy_bodies.gd

const CODE := "CRT-002"
const EXPECTED_CANONICAL_CLIPS := [
	"Idle", "Walk", "Run", "Attack", "Attack2", "Attack3", "HitReact", "Death", "Swim", "Swim_Idle", "Dodge",
]

var _failures := 0
var _checks := 0


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
	db.free()

	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


func _check_true(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
