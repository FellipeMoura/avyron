extends SceneTree

## Um corpo do fluxo "base + casca": gerado no Tripo sobre a silhueta da
## mestre (`models/dev/manequim-mestre.glb`) e vestido com o esqueleto dela por
## transferência de pesos (`avyron-bestiary/scripts/convert-tripo.mjs`).
##
## O arquivo chega SEM clipe nenhum, de propósito — a aposta inteira é que
## ele entra pelo MESMO caminho do placeholder Imp
## (`CreatureActor._build_retargeted_animation`) e ganha a biblioteca UAL
## em runtime. Esta suíte prende exatamente isso:
##
## 1. o `.glb` traz malha skinada num Skeleton3D de 55 ossos;
## 2. o retarget dá o vocabulário completo de clipes;
## 3. tocar `Walk` e avançar o tempo MOVE os ossos (a skin está ligada ao
##    esqueleto certo, não a um esqueleto órfão);
## 4. o corpo cabe na escala de jogo pelo mesmo `build_visual` de sempre.
##
##     godot --headless --script res://scripts/dev/test_tripo_shell.gd
##     godot --headless --script res://scripts/dev/test_tripo_shell.gd -- --shell /models/CRT-005.glb
##
## `--shell <modelUrl>` (depois do `--` que separa os argumentos do Godot
## dos do script) troca o corpo testado; sem ele, testa a própria mestre.

const DEFAULT_SHELL := "/models/dev/manequim-mestre.glb"
var SHELL := DEFAULT_SHELL
const EXPECTED_CLIPS := [
	"Idle", "Walk", "Run", "Attack", "Attack2", "HitReact", "Death", "Swim", "Swim_Idle",
	"Dodge", "Cast_Enter", "Cast", "Cast_Exit",
]
const EXPECTED_BONES := 55

var _failures := 0
var _checks := 0
var _frames := 0
var _visual: Dictionary


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shell")
	if i != -1 and i + 1 < args.size():
		SHELL = args[i + 1]
	print("\n-- casca Tripo vestida com o esqueleto da mestre: %s" % SHELL)
	_visual = CreatureActor.build_visual(1.4, "ELE-002", "CRT-PROVA", SHELL)
	var meshes: Array[MeshInstance3D] = _visual.get("mesh_instances", [])
	_check_true("trouxe malha", not meshes.is_empty())
	if meshes.is_empty():
		_finish()
		return

	var mi: MeshInstance3D = meshes[0]
	_check_true("malha e skinada (aponta pra um Skeleton3D)", mi.skeleton != NodePath())
	var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	_check_true("Skeleton3D encontrado", skeleton != null)
	if skeleton != null:
		_check_true("esqueleto tem %d ossos (tem %d)" % [EXPECTED_BONES, skeleton.get_bone_count()], skeleton.get_bone_count() == EXPECTED_BONES)
		_check_true("osso 'pelvis' existe", skeleton.find_bone("pelvis") != -1)
		_check_true("osso 'hand_l' existe", skeleton.find_bone("hand_l") != -1)

	var anim: AnimationPlayer = _visual.get("anim")
	_check_true("ganhou AnimationPlayer por retarget (sem clipe no arquivo)", anim != null)
	if anim != null:
		for clip in EXPECTED_CLIPS:
			_check_true("clipe %s disponivel" % clip, anim.has_animation(clip))

	# Escala de jogo: o wrapper "Model" deve caber em ~1,4 m de altura.
	var wrapper: Node3D = _visual["mesh"]
	root.add_child(wrapper)


## A skin só se prova em movimento: tocar `Walk` e avançar tem de mudar a
## pose global de um osso. Precisa da árvore rodando, por isso espera quadros.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var anim: AnimationPlayer = _visual.get("anim")
		if anim != null:
			anim.play("Walk")
	if _frames < 12:
		return false

	var meshes: Array[MeshInstance3D] = _visual.get("mesh_instances", [])
	if not meshes.is_empty():
		var mi: MeshInstance3D = meshes[0]
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if skeleton != null:
			var idx := skeleton.find_bone("calf_l")
			var rest := skeleton.get_bone_global_rest(idx)
			var now := skeleton.get_bone_global_pose(idx)
			var moved := rest.origin.distance_to(now.origin) > 0.005 or not rest.basis.is_equal_approx(now.basis)
			_check_true("Walk move o osso calf_l (skin ligada ao esqueleto certo)", moved)
			var aabb := mi.get_aabb()
			print("  info AABB da malha em movimento: %.2f x %.2f x %.2f" % [aabb.size.x, aabb.size.y, aabb.size.z])
		var wrapper: Node3D = _visual["mesh"]
		var world_aabb := _world_aabb(wrapper, meshes)
		print("  info altura do corpo em jogo: %.2f m (alvo 1,40)" % world_aabb.size.y)
		_check_true("altura em jogo entre 1,2 e 1,6 m", world_aabb.size.y > 1.2 and world_aabb.size.y < 1.6)

	_finish()
	return true


func _world_aabb(wrapper: Node3D, meshes: Array[MeshInstance3D]) -> AABB:
	var result := AABB()
	var first := true
	for mi in meshes:
		var t := wrapper.global_transform.affine_inverse() * mi.global_transform
		var box := t * mi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _finish() -> void:
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
