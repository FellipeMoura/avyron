extends SceneTree

## Validação headless do kit de personagens e da montagem do CharacterRig.
##
##     godot --headless --script res://scripts/dev/test_characters.gd
##
## Guarda três contratos: o manifest do kit (toda peça listada precisa ter
## recurso importado atrás dela), a montagem por receita (player hardcoded e
## as receitas `appearance` que o bundle traz para os NPCs), e a fusão das
## bibliotecas de animação com as trilhas re-endereçadas para o esqueleto do
## rig. Se o bestiário exportar uma receita com peça inexistente, ou o kit
## mudar de estrutura, estoura aqui — não como um NPC invisível em runtime.

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_manifest()
	_test_player_rig()
	_test_gait_ladder()
	_test_npc_rigs()
	_test_animation_library()

	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


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
# rig do jogador (receita hardcoded da v1)
# ---------------------------------------------------------------------------

func _test_player_rig() -> void:
	print("rig do jogador:")
	var rig := CharacterRig.create(PlayerController.DEFAULT_RECIPE)
	_check("montou a partir de DEFAULT_RECIPE", rig != null)
	if rig == null:
		return

	var meshes := _skeleton_meshes(rig)
	# Corpo (cabeça + olhos + sobrancelha) = 3, mais cabelo e 4 peças de roupa.
	_check("%d malhas penduradas no esqueleto (esperado >= 8)" % meshes.size(), meshes.size() >= 8)

	for clip in ["Idle", "Walk", "Run", "Swim", "Attack", "Throw", "Consume", "Death"]:
		_check("clipe %s disponível" % clip, rig.has_clip(clip))
	_check("receita vazia devolve null (fallback de cápsula)", CharacterRig.create({}) == null)
	rig.free()


# ---------------------------------------------------------------------------
# a escada de marcha e o meio
# ---------------------------------------------------------------------------

## O corpo escolhe o clipe pela marcha E pelo meio. As duas asserções que
## importam são as pontas: correr a 5,2 m/s (a velocidade real do jogador —
## tocar `Walk` ali é o deslize que motivou a escada) e nadar submerso, que no
## PZ-01 é o estado NORMAL da exploração, porque o mapa é o leito de um mar.
func _test_gait_ladder() -> void:
	print("escada de marcha:")
	var rig := CharacterRig.create(PlayerController.DEFAULT_RECIPE)
	if rig == null:
		_check("montou o rig para medir a escada", false)
		return
	var anim := rig.get_node_or_null("Anim") as AnimationPlayer

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
	# pose de boiar na superfície (o corpo pendura 1,41 m abaixo da origem) e
	# alternar com `Swim` faria o corpo pular 1,2 m a cada parada.
	_check("o kit tem Swim_Idle, e ele fica de fora de propósito", rig.has_clip("Swim_Idle"))
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
	var rig := CharacterRig.create(PlayerController.DEFAULT_RECIPE)
	if rig == null:
		_check("rig para inspecionar a biblioteca", false)
		return
	var anim: AnimationPlayer = null
	for child in rig.find_children("*", "AnimationPlayer", true, false):
		anim = child
		break
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
