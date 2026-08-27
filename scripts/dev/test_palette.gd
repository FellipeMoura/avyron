extends SceneTree

## Prova a identidade visual por elemento: a paleta vem do catálogo, o corpo
## placeholder é recolorido por ela, e a aura do Despertar Ancestral nasce e
## morre com a transformação.
##
##     godot --headless --script res://scripts/dev/test_palette.gd
##
## O CONTRATO da paleta no bundle não é medido aqui: ele mora em
## `test_data.gd`, que é o guarda que espelha os critérios do
## `pnpm game:export`. Esta suíte mede COMPORTAMENTO, e existe para pegar os
## três defeitos que a implementação realmente cometeu:
##
## 1. **Paleta lida vazia.** `ElementPalette` cai para um cinza de engenharia
##    quando não acha a paleta — degradação certa, e silenciosa. Se a consulta
##    ao bundle quebrar, TODA criatura sai cinza e nenhuma suíte reprova. Foi
##    o que aconteceu de fato: o `BestiaryData` de fallback carregava no
##    `_ready()` e nunca entrava na árvore, então respondia a tudo e respondia
##    vazio. Por isso `_test_palette_comes_from_bundle` compara contra o VALOR
##    do bundle, e não contra "não é vazio".
## 2. **Recoloração aplicada no corpo errado.** Os `.glb` legados do Meshy têm
##    normal e metallic-roughness próprios, e remapear ali suja a imagem. O
##    portão é o prefixo do caminho, e portão é exatamente o tipo de coisa que
##    se afrouxa sem querer.
## 3. **Aura vazando do duelo para o mapa.** A casca é nó de verdade; esquecer
##    de removê-la deixa a criatura acesa vagando pelo bioma.

const PLACEHOLDER := "/models/placeholders/big/Dino.glb"

var _db: BestiaryData
var _failures := 0
var _checks := 0
var _frames := 0


func _initialize() -> void:
	_db = BestiaryData.new()
	var err := _db.load_bundle()
	if err != "":
		printerr("FALHA ao carregar o bundle: ", err)
		quit(1)


## Mesmo motivo das outras suítes: nó adicionado à raiz antes de a árvore
## estar viva não conta como dentro dela. Aqui pesa em dobro, porque a aura é
## medida por parentesco de nó.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_run()
	return true


func _run() -> void:
	_test_palette_comes_from_bundle()
	_test_creature_bias()
	_test_body_recolor()
	_test_legacy_body_untouched()
	_test_aura_lifecycle()
	_test_actor_aura()

	_db.free()

	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


# ---------------------------------------------------------------------------
# leitura
# ---------------------------------------------------------------------------

## Compara contra o BUNDLE, não contra "diferente de vazio". `ElementPalette`
## devolve `NEUTRAL_MID` quando não acha a paleta, e um teste que só exigisse
## "alguma cor" passaria com o catálogo inteiro desligado.
func _test_palette_comes_from_bundle() -> void:
	print("\n-- a cor vem do catalogo")
	var p: Dictionary = _db.element("ELE-001").get("palette", {})
	if p.is_empty():
		_warn("ELE-001 sem paleta no bundle; leitura nao pode ser verificada")
		return
	_check("mid de ELE-001", ElementPalette.mid_color("ELE-001"), Color(str(p["mid"])))
	_check("shadow de ELE-001", ElementPalette.shadow_color("ELE-001"), Color(str(p["shadow"])))
	_check("aura de ELE-001", ElementPalette.aura_color("ELE-001"), Color(str(p["aura"])))
	_check_true("elemento inexistente cai no neutro",
		ElementPalette.mid_color("ELE-999") == ElementPalette.NEUTRAL_MID)


## O deslocamento por criatura é o que impede duas criaturas do mesmo elemento
## com o mesmo corpo de saírem idênticas. Tem de ser estável (mesma cor em
## toda partida) e contido (nunca sai da família).
func _test_creature_bias() -> void:
	print("\n-- deslocamento por criatura")
	var spread := float(_db.element("ELE-001").get("palette", {}).get("spread", 0.0))
	var a := ElementPalette.creature_bias("CRT-001", "ELE-001")
	var b := ElementPalette.creature_bias("CRT-014", "ELE-001")

	_check_true("estavel entre chamadas", a == ElementPalette.creature_bias("CRT-001", "ELE-001"))
	_check_true("duas criaturas do mesmo elemento diferem", a != b,
		"%.4f vs %.4f" % [a, b])
	_check_true("dentro de [-spread, spread]", absf(a) <= spread and absf(b) <= spread,
		"spread=%.2f" % spread)
	_check("criatura sem codigo nao desloca",
		ElementPalette.creature_bias("", "ELE-001"), 0.0)


# ---------------------------------------------------------------------------
# corpo
# ---------------------------------------------------------------------------

func _test_body_recolor() -> void:
	print("\n-- recoloracao do corpo placeholder")
	var visual := CreatureActor.build_visual(2.0, "ELE-002", "CRT-002", PLACEHOLDER)
	var meshes: Array[MeshInstance3D] = visual["mesh_instances"]
	_check_true("o placeholder trouxe malha", not meshes.is_empty())
	if meshes.is_empty():
		visual["mesh"].free()
		return

	var mi: MeshInstance3D = meshes[0]
	var override := mi.get_surface_override_material(0)
	_check_true("superficie recebeu ShaderMaterial", override is ShaderMaterial)
	if override is ShaderMaterial:
		var sm: ShaderMaterial = override
		_check_true("o atlas original continua sendo a fonte",
			sm.get_shader_parameter("atlas") != null)
		_check_true("a rampa do elemento foi ligada",
			sm.get_shader_parameter("ramp") is GradientTexture1D)
		var ramp: GradientTexture1D = sm.get_shader_parameter("ramp")
		var p: Dictionary = _db.element("ELE-002").get("palette", {})
		if not p.is_empty():
			_check("primeira parada = shadow do elemento",
				ramp.gradient.colors[0], Color(str(p["shadow"])))
			_check("ultima parada = highlight do elemento",
				ramp.gradient.colors[2], Color(str(p["highlight"])))

	# Dois corpos do MESMO elemento têm de dividir o material — é o que
	# preserva o batching. O que os distingue viaja na instância.
	var other := CreatureActor.build_visual(2.0, "ELE-002", "CRT-005", PLACEHOLDER)
	var other_meshes: Array[MeshInstance3D] = other["mesh_instances"]
	if not other_meshes.is_empty():
		_check_true("mesmo elemento compartilha o material",
			other_meshes[0].get_surface_override_material(0) == override)

	visual["mesh"].free()
	other["mesh"].free()


## O portão de caminho: `.glb` legado do Meshy passa intacto. Sem este teste,
## afrouxar o prefixo suja os corpos com base color assada e ninguém percebe
## até alguém abrir o jogo.
func _test_legacy_body_untouched() -> void:
	print("\n-- corpo legado nao e recolorido")
	var legacy_path := CreatureActor.model_path("CRT-001", "")
	if legacy_path == "":
		_warn("nenhum .glb legado na raiz; portao nao pode ser verificado")
		return
	_check_true("o caminho legado esta fora dos placeholders",
		not legacy_path.begins_with(ElementPalette.PLACEHOLDER_PREFIX), legacy_path)

	var visual := CreatureActor.build_visual(2.0, "ELE-001", "CRT-001", "")
	var meshes: Array[MeshInstance3D] = visual["mesh_instances"]
	if meshes.is_empty():
		visual["mesh"].free()
		return
	_check_true("nenhuma superficie recebeu override",
		meshes[0].get_surface_override_material(0) == null)
	visual["mesh"].free()


# ---------------------------------------------------------------------------
# aura
# ---------------------------------------------------------------------------

func _test_aura_lifecycle() -> void:
	print("\n-- casca da aura")
	var visual := CreatureActor.build_visual(2.0, "ELE-005", "CRT-003", PLACEHOLDER)
	var meshes: Array[MeshInstance3D] = visual["mesh_instances"]
	if meshes.is_empty():
		visual["mesh"].free()
		return

	var mi: MeshInstance3D = meshes[0]
	var parent := mi.get_parent()
	var before := parent.get_child_count()

	var shells := ElementPalette.attach_aura(meshes, "ELE-005")
	_check("uma casca por malha", shells.size(), meshes.size())
	_check("a casca entrou como IRMA da malha", parent.get_child_count(), before + 1)
	if not shells.is_empty():
		var shell: MeshInstance3D = shells[0]
		_check_true("a casca usa o shader de aura",
			shell.material_override is ShaderMaterial)
		_check("a casca aponta o mesmo esqueleto", shell.skeleton, mi.skeleton)
		_check_true("a casca nao projeta sombra",
			shell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	ElementPalette.detach_aura(shells)
	# Estado SÍNCRONO, não contagem de filhos: `queue_free` só é drenado no fim
	# do quadro, e conferir `get_child_count` aqui reprovaria por artefato.
	_check_true("detach marcou as cascas para remocao",
		shells.all(func(s: MeshInstance3D) -> bool: return s.is_queued_for_deletion()))

	var light := ElementPalette.build_aura_light("ELE-005", 2.0)
	_check("a luz usa a cor de aura do elemento",
		light.light_color, ElementPalette.aura_color("ELE-005"))
	_check_true("a luz nao gasta mapa de sombra", not light.shadow_enabled)
	light.free()

	visual["mesh"].free()


## O ciclo pelo ator, que é como o duelo usa. Idempotência importa: o sinal
## `rendered` reespelha o estado a cada turno, então `set_awakening_aura(true)`
## chega repetido e não pode empilhar casca nem luz.
func _test_actor_aura() -> void:
	print("\n-- aura pelo ator")
	var actor := CreatureActor.create(_db.creature("CRT-002"), Vector3.ZERO, 1)
	root.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)

	_check_true("nasce apagada", not actor.is_awakened())

	actor.set_awakening_aura(true)
	_check_true("acende", actor.is_awakened())
	var lights := _count_lights(actor)
	_check("acendeu uma luz", lights, 1)

	actor.set_awakening_aura(true)
	_check("chamada repetida nao empilha luz", _count_lights(actor), lights)

	actor.set_awakening_aura(false)
	_check_true("apaga", not actor.is_awakened())

	# `reset_engagement` é o caminho pelo qual uma criatura que sobreviveu ao
	# duelo volta a vagar. Ela não pode voltar acesa.
	actor.set_awakening_aura(true)
	actor.reset_engagement()
	_check_true("reset_engagement apaga a aura", not actor.is_awakened())

	actor.free()


func _count_lights(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is OmniLight3D:
			n += 1
	return n


# ---------------------------------------------------------------------------
# relatorio
# ---------------------------------------------------------------------------

func _check(label: String, actual: Variant, expected: Variant) -> void:
	_checks += 1
	if actual == expected:
		print("  ok   %s = %s" % [label, str(actual)])
	else:
		_failures += 1
		printerr("  FAIL %s = %s (esperado %s)" % [label, str(actual), str(expected)])


func _check_true(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s%s" % [label, (" — " + detail) if detail != "" else ""])
	else:
		_failures += 1
		printerr("  FAIL %s%s" % [label, (" — " + detail) if detail != "" else ""])


## Meta de conteúdo: sai alto e NÃO reprova. Mesmo critério de `test_data.gd`
## e do export — suíte vermelha significa quebrado.
func _warn(message: String) -> void:
	print("  AVISO %s" % message)
