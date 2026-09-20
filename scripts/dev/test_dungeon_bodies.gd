extends SceneTree

## Valida o corpo genérico único (`CreatureActor.PLACEHOLDER_PATH`, o "Imp" do
## kit "Bestiary - Dungeon Monsters", Quaternius CC0): chega sem clipe
## embutido porque roda no MESMO esqueleto da Universal Animation Library que
## o `CharacterRig` já usa para os humanos — este corpo espera ser montado
## por retarget, não por animação bakeada.
## `CreatureActor._build_retargeted_animation` é o que faz essa ponte; esta
## suíte prende o contrato pra ele não quebrar em silêncio se um dia o pack
## de personagens mudar de forma.
##
##     godot --headless --script res://scripts/dev/test_dungeon_bodies.gd
##
## Cobertura de clipe completa é o ponto: por vir da MESMA biblioteca dos
## humanos, este corpo tem o vocabulário INTEIRO do jogo — o que importa
## porque ele agora é o corpo de TODA criatura sem modelo definitivo, não
## mais um entre ~30 (ver o comentário de topo de `element_palette.gd` sobre
## a limpeza de 2026-09: Imp sobrou, Puglin e os outros três packs saíram).

const IMP := "/models/placeholders/dungeon/Imp.glb"

## Vocabulário completo esperado — o ganho real do retarget sobre os
## placeholders bakeados, que nunca têm os golpes de combate completos.
## `Dodge`/`Cast_Enter`/`Cast`/`Cast_Exit` entraram em 2026-09 (miss, captura
## falha e a encenação de `Attack3`, ver `EncounterDirector`).
const EXPECTED_CLIPS := [
	"Idle", "Walk", "Run", "Attack", "Attack2", "HitReact", "Death", "Swim",
	"Dodge", "Cast_Enter", "Cast", "Cast_Exit",
]

var _failures := 0
var _checks := 0
var _frames := 0


func _initialize() -> void:
	_test_body("Imp", IMP, "CRT-TEST-IMP", "ELE-001")


## `_test_real_bundle_fallback` monta `CreatureActor` de verdade e depende de
## `_ready()` — que só dispara depois que a árvore roda pelo menos um quadro.
## Nó adicionado à raiz dentro de `_initialize()` não conta como "na árvore"
## ainda (mesma pegadinha documentada no `CLAUDE.md` pra medição de posição em
## teste); por isso esta suíte, diferente de `_test_body` (chamada direta a
## `build_visual`, sem ator, sem árvore), espera 2 quadros antes de continuar.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	_test_real_bundle_fallback()

	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)
	return true


func _test_body(label: String, model_url: String, creature_code: String, element_code: String) -> void:
	print("\n-- %s" % label)
	var visual := CreatureActor.build_visual(2.0, element_code, creature_code, model_url)
	var meshes: Array[MeshInstance3D] = visual.get("mesh_instances", [])
	_check_true("%s: trouxe malha" % label, not meshes.is_empty())
	if meshes.is_empty():
		return

	var anim: AnimationPlayer = visual.get("anim")
	_check_true("%s: ganhou AnimationPlayer por retarget" % label, anim != null)
	if anim != null:
		for clip in EXPECTED_CLIPS:
			_check_true("%s: clipe %s disponivel" % [label, clip], anim.has_animation(clip))
		_check_true("%s: Idle em loop" % label,
			anim.has_animation("Idle")
			and anim.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR)
		_check_true("%s: Death sem loop" % label,
			anim.has_animation("Death")
			and anim.get_animation("Death").loop_mode == Animation.LOOP_NONE)

	var mi: MeshInstance3D = meshes[0]
	_check_true("%s: NAO recolorido por elemento (recoloracao saiu em 2026-09)" % label,
		not (mi.get_surface_override_material(0) is ShaderMaterial))

	(visual["mesh"] as Node3D).free()


## Ponta a ponta pelo bundle DE VERDADE: uma criatura sem `modelUrl`
## resolvível (a maioria do elenco hoje, depois da limpeza dos placeholders
## por família) cai no corpo genérico único — não por caminho hardcoded, mas
## pelo mesmo `CreatureActor.create` + `model_path` que qualquer criatura usa.
func _test_real_bundle_fallback() -> void:
	print("\n-- fallback real pelo bundle")
	var db := BestiaryData.new()
	var err := db.load_bundle()
	if err != "":
		printerr("bundle nao carregou: ", err)
		db.free()
		return

	# CRT-068 (Arthropleura, CRT-008 até a renumeração de 2026-09) perdeu o vínculo com dungeon/Puglin na mesma limpeza (o pack
	# inteiro saiu, não só o Imp sobrevive) — hoje é um exemplo real de
	# "sem modelo definitivo", o mesmo caso da maioria do elenco.
	var code := "CRT-068"
	var data := db.creature(code)
	_check_true("%s: existe no bundle" % code, not data.is_empty())
	if data.is_empty():
		db.free()
		return
	# `data.get("modelUrl")` devolve `null` (chave presente com valor null),
	# não a string vazia — `str(null)` viraria "<null>", que passaria
	# despretensiosamente por qualquer checagem de string.
	var model_url: Variant = data.get("modelUrl")
	_check_true("%s: sem modelUrl (caiu no placeholder unico)" % code,
		model_url == null or model_url == "")

	var actor := CreatureActor.create(data, Vector3.ZERO, 1)
	root.add_child(actor)
	var resolved := CreatureActor.model_path(actor.creature_code, actor.model_url)
	_check_true("%s: model_path resolve pro placeholder unico" % code, resolved == CreatureActor.PLACEHOLDER_PATH)
	_check_true("%s: tem AnimationPlayer (retarget rodou de verdade)" % code,
		actor.get_node_or_null("Model") != null
		and not actor.find_children("*", "AnimationPlayer", true, false).is_empty())
	actor.free()

	db.free()


func _check_true(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
