extends SceneTree

## Prova o ciclo de vida da aura do Despertar Ancestral: nasce e morre com a
## transformação, não empilha em chamada repetida, e usa a rampa neutra fixa
## de `ElementPalette` (sem elemento nem carta desde 2026-09 — ver o
## comentário de topo de `element_palette.gd` sobre por que a recoloração de
## corpo por elemento saiu).
##
##     godot --headless --script res://scripts/dev/test_palette.gd
##
## Até 2026-09 esta suíte também provava a leitura da paleta do bundle, a
## recoloração do corpo placeholder e a sobreposição por `cardPalette` — tudo
## isso saiu junto com o sistema que testava. O que sobra (aura, luz, efeito
## de golpe/status) é a fatia que continua existindo, só com cor fixa.

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
# aura
# ---------------------------------------------------------------------------

## O efeito de área não depende de malha nenhuma — não precisa de
## `CreatureActor.build_visual` para existir, e é isso que deixa a cápsula
## (criatura sem `.glb`) também despertar visível.
func _test_aura_lifecycle() -> void:
	print("\n-- efeito de area do Despertar")
	var vfx := ElementPalette.attach_area_vfx(2.0)
	_check_true("instanciou o efeito de area", vfx != null)
	if vfx == null:
		return
	_check_true("e um VFXElementalAreaBB", vfx is VFXElementalAreaBB)
	if vfx is VFXElementalAreaBB:
		var area: VFXElementalAreaBB = vfx
		_check("cor primaria = aura neutra fixa",
			area.primary_color, ElementPalette.NEUTRAL_AURA)
		_check("cor secundaria = mid neutro fixo",
			area.secondary_color, ElementPalette.NEUTRAL_MID)
		_check("cor terciaria = shadow neutro fixo",
			area.tertiary_color, ElementPalette.NEUTRAL_SHADOW)
		_check_true("raio de area escala com o porte", area.area_radius > 0.0)

	ElementPalette.detach_area_vfx(vfx)
	# Estado SÍNCRONO, não contagem de filhos: `queue_free` só é drenado no fim
	# do quadro, e conferir `get_child_count` aqui reprovaria por artefato.
	_check_true("detach marcou o efeito para remocao", vfx.is_queued_for_deletion())

	var light := ElementPalette.build_aura_light(2.0)
	_check("a luz usa a cor de aura neutra fixa",
		light.light_color, ElementPalette.NEUTRAL_AURA)
	_check_true("a luz nao gasta mapa de sombra", not light.shadow_enabled)
	light.free()


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
	_check("efeito de area entrou como filho",
		actor.find_children("*", "VFXElementalAreaBB", true, false).size(), 1)
	_check("burst de cast entrou como filho",
		actor.find_children("*", "VFXElementalCastBB", true, false).size(), 1)

	actor.set_awakening_aura(true)
	_check("chamada repetida nao empilha luz", _count_lights(actor), lights)
	_check("chamada repetida nao empilha efeito de area",
		actor.find_children("*", "VFXElementalAreaBB", true, false).size(), 1)

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
