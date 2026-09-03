extends SceneTree

## Valida o corpo do "Easy Animated Pack" (Quaternius, CC0) como placeholder de
## criatura: ao contrário do Dungeon Monsters, estes chegam com clipe
## embutido (esqueleto e animação próprios, sem UAL) — o caminho normal de
## `CreatureActor._find_animation_player` já basta, sem retarget.
##
## Também prova que estes corpos NÃO são recoloridos pelo elemento — têm
## cor de espécie própria (verde da rã, preto-vermelho da aranha...), e
## `ElementPalette.apply_body` só entra em `res://models/placeholders/`
## quando o elemento tem paleta E a superfície tem atlas; aqui a superfície é
## `albedo_color` chapado, sem textura, então a recoloração é ignorada por
## design — mesmo portão que já protege os `.glb` legados do Meshy.
##
##     godot --headless --script res://scripts/dev/test_easy_pack_bodies.gd

## Só os corpos já VINCULADOS a uma criatura real (ver `REAL_LINKS`) — o
## export só espelha `.glb` que algum `modelUrl` referencia (deduplicado), e
## Rat/Snake_angry ainda não têm criatura nenhuma apontando pra eles. Eles
## existem em `avyron-bestiary/apps/web/public/models/placeholders/
## easyanimated/` (o lado de conteúdo já os tem prontos pro picker), só não
## chegam aqui — no repo do jogo — até serem vinculados. Ausência esperada,
## não falha de conversão.
const BODIES := {
	"Frog": "/models/placeholders/easyanimated/Frog.glb",
	"Spider": "/models/placeholders/easyanimated/Spider.glb",
	"Snake": "/models/placeholders/easyanimated/Snake.glb",
	"Wasp": "/models/placeholders/easyanimated/Wasp.glb",
}

## Uma criatura real vinculada por corpo, pra provar o vínculo ponta a ponta
## (bundle -> model_path -> retarget nao chamado -> clipe nativo).
const REAL_LINKS := {
	"CRT-062": "easyanimated/Spider",
	"CRT-009": "easyanimated/Wasp",
	"CRT-060": "easyanimated/Frog",
	"CRT-024": "easyanimated/Snake",
}

var _db: BestiaryData
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_db = BestiaryData.new()
	var err := _db.load_bundle()
	if err != "":
		printerr("FALHA ao carregar o bundle: ", err)
		quit(1)
		return

	for label in BODIES:
		_test_body(label, BODIES[label])
	_test_real_bundle_links()

	_db.free()
	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


func _test_body(label: String, model_url: String) -> void:
	print("\n-- %s" % label)
	var visual := CreatureActor.build_visual(1.0, "ELE-001", "CRT-TEST-%s" % label, model_url)
	var meshes: Array[MeshInstance3D] = visual.get("mesh_instances", [])
	_check_true("%s: trouxe malha" % label, not meshes.is_empty())
	if meshes.is_empty():
		return

	var anim: AnimationPlayer = visual.get("anim")
	_check_true("%s: tem AnimationPlayer proprio (sem retarget)" % label, anim != null)
	if anim != null:
		_check_true("%s: tem Idle" % label, anim.has_animation("Idle"))
		_check_true("%s: tem Attack" % label, anim.has_animation("Attack"))

	var mi: MeshInstance3D = meshes[0]
	var mat := mi.get_surface_override_material(0)
	_check_true("%s: NAO recolorido pelo elemento (cor propria da especie)" % label,
		not (mat is ShaderMaterial))

	(visual["mesh"] as Node3D).free()


func _test_real_bundle_links() -> void:
	print("\n-- vinculo real pelo bundle")
	for code in REAL_LINKS:
		var data := _db.creature(code)
		_check_true("%s: existe no bundle" % code, not data.is_empty())
		if data.is_empty():
			continue
		var model_url := str(data.get("modelUrl", ""))
		_check_true("%s: modelUrl aponta pro corpo esperado (%s, url=%s)" % [code, REAL_LINKS[code], model_url],
			model_url.contains(str(REAL_LINKS[code])))
		var resolved := CreatureActor.model_path(code, model_url)
		_check_true("%s: model_path resolve pro .glb espelhado" % code, resolved != "")


func _check_true(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
