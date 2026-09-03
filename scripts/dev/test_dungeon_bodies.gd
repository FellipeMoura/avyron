extends SceneTree

## Valida o corpo do kit "Bestiary - Dungeon Monsters" (Quaternius, CC0) como
## placeholder de criatura: Imp e Puglin chegam sem clipe embutido porque
## rodam no MESMO esqueleto da Universal Animation Library que o
## `CharacterRig` já usa para os humanos — este corpo espera ser montado por
## retarget, não por animação bakeada. `CreatureActor._build_retargeted_animation`
## é o que faz essa ponte; esta suíte prende o contrato pra ele não quebrar em
## silêncio se um dia o pack de personagens mudar de forma.
##
##     godot --headless --script res://scripts/dev/test_dungeon_bodies.gd
##
## Cobertura de clipe pensada pro que falta nos placeholders antigos: eles
## variam o que têm (voadores não têm `Walk`, por exemplo); este corpo, por
## vir da MESMA biblioteca dos humanos, tem o vocabulário inteiro do jogo.

const IMP := "/models/placeholders/dungeon/Imp.glb"
const PUGLIN := "/models/placeholders/dungeon/Puglin.glb"

## Vocabulário completo esperado — o ganho real do retarget sobre os
## placeholders bakeados, que nunca têm os golpes de combate completos.
const EXPECTED_CLIPS := ["Idle", "Walk", "Run", "Attack", "Attack2", "HitReact", "Death", "Swim"]

var _failures := 0
var _checks := 0
var _frames := 0


func _initialize() -> void:
	_test_body("Imp", IMP, "CRT-TEST-IMP", "ELE-001")
	_test_body("Puglin", PUGLIN, "CRT-TEST-PUGLIN", "ELE-004")


## `_test_real_bundle_links` monta `CreatureActor` de verdade e depende de
## `_ready()` — que só dispara depois que a árvore roda pelo menos um quadro.
## Nó adicionado à raiz dentro de `_initialize()` não conta como "na árvore"
## ainda (mesma pegadinha documentada no `CLAUDE.md` pra medição de posição em
## teste); por isso esta suíte, diferente de `_test_body` (chamada direta a
## `build_visual`, sem ator, sem árvore), espera 2 quadros antes de continuar.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	_test_real_bundle_links()

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
	_check_true("%s: superficie recolorida pelo elemento" % label,
		mi.get_surface_override_material(0) is ShaderMaterial)

	(visual["mesh"] as Node3D).free()


## Ponta a ponta pelo bundle DE VERDADE (não caminho hardcoded): CRT-010 e
## CRT-008 foram vinculadas ao Imp/Puglin via PATCH real na API do bestiário
## (mesmo botão "vincular modelo" da ficha), passaram por `pnpm game:export`,
## e chegam aqui como qualquer outra criatura chegaria — via
## `CreatureActor.create` + `model_path`, sem atalho de teste.
func _test_real_bundle_links() -> void:
	print("\n-- vinculo real pelo bundle")
	var db := BestiaryData.new()
	var err := db.load_bundle()
	if err != "":
		printerr("bundle nao carregou: ", err)
		db.free()
		return

	for expect in [{"code": "CRT-010", "url_part": "dungeon/Imp"}, {"code": "CRT-008", "url_part": "dungeon/Puglin"}]:
		var code: String = expect["code"]
		var data := db.creature(code)
		_check_true("%s: existe no bundle" % code, not data.is_empty())
		if data.is_empty():
			continue
		var model_url := str(data.get("modelUrl", ""))
		_check_true("%s: modelUrl aponta pro corpo esperado (%s)" % [code, model_url],
			model_url.contains(str(expect["url_part"])))

		var actor := CreatureActor.create(data, Vector3.ZERO, 1)
		root.add_child(actor)
		var resolved := CreatureActor.model_path(actor.creature_code, actor.model_url)
		_check_true("%s: model_path resolve pro .glb espelhado" % code, resolved != "")
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
