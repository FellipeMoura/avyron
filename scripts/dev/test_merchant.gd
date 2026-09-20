extends SceneTree

## Prova o laço da economia: minerar produz, o comerciante compra, a bolsa
## paga, e o que se compra faz alguma coisa.
##
## O que está sob teste é a promessa de que mineração deixou de ser um
## produtor sem escoadouro. Antes disto, todo minério coletado era peso morto
## — e o ritmo de mineração não tinha como ser avaliado, porque o que ele
## produzia não valia nada.
##
##     godot --headless --script res://scripts/dev/test_merchant.gd

const MERCHANT := "NPC-001"
const POULTICE := "ITM-016"       # Emplastro de Limo
const STONE := "ITM-001"          # Pedra, o mineral mais barato

var _world: WorldRoot
var _db: BestiaryData
var _frames := 0
var _phase := "init"
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_world = load("res://scenes/main.tscn").instantiate() as WorldRoot
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	match _phase:
		"init":
			_db = root.get_node_or_null("/root/Bestiary") as BestiaryData
			if _db == null:
				_db = BestiaryData.new()
				var err := _db.load_bundle()
				if err != "":
					_check_true("bundle carregou", false, err)
					_finish()
					return true
			_test_catalog()
			_test_economy_math()
			_test_purse()
			_test_shop_screen()
			# Antes de `_test_world_wiring`, que teleporta comerciante e posto
			# para perto do jogador: o layout tem de ser medido onde o
			# `WorldPopulator` os pôs.
			_test_village_layout()
			_test_npc_rigs_in_world()
			_test_world_wiring()
			_test_modal_guard()
			_test_actor_grounding()
			_phase = "done"
		"done":
			_finish()
			return true
	return false


# ---------------------------------------------------------------------------
# dados
# ---------------------------------------------------------------------------

func _test_catalog() -> void:
	print("catalogo de itens:")
	_check_true("o bundle traz o bloco items", _db.item_codes().size() > 0,
		"%d itens" % _db.item_codes().size())
	_check_true("mineral e consumivel convivem no mesmo catalogo",
		_db.items_in_category("mineral").size() > 0
		and _db.items_in_category("heal").size() > 0,
		"%d mineral, %d cura" % [
			_db.items_in_category("mineral").size(),
			_db.items_in_category("heal").size()])

	# O furo que o filtro do export existe para tapar: consumivel nao pode
	# aparecer na tabela de mineracao. Se aparecer, alguem removeu o filtro e
	# o jogador vai desenterrar emplastro do chao.
	var minable := {}
	for c in _db.mineral_codes():
		minable[str(c)] = true
	_check_true("nenhum consumivel e mineravel",
		not minable.has(POULTICE),
		"%d mineraveis de %d itens" % [minable.size(), _db.item_codes().size()])

	_check_true("emplastro tem efeito de cura",
		_db.item_effect_code(POULTICE) == "heal_percent"
		and _db.item_effect_value(POULTICE) > 0.0,
		"%d%%" % int(_db.item_effect_value(POULTICE)))
	_check("mineral nao tem efeito", _db.item_effect_code(STONE), "none")

	_check_true("o comerciante existe e tem catalogo",
		not _db.merchant(MERCHANT).is_empty()
		and (_db.merchant(MERCHANT).get("offers", []) as Array).size() > 0,
		"%d ofertas" % (_db.merchant(MERCHANT).get("offers", []) as Array).size())
	_check_true("e esta no mapa do jogo",
		_db.merchants_in_map("PZ-01").size() > 0)


func _test_economy_math() -> void:
	print("aritmetica da economia:")
	_check_true("a moeda tem nome", _db.currency_name(1) != "",
		"%s / %s" % [_db.currency_name(1), _db.currency_name(2)])
	_check_true("singular e plural diferem",
		_db.currency_name(1) != _db.currency_name(2))
	_check_true("ha bolsa inicial", _db.starting_currency() > 0,
		"%d" % _db.starting_currency())

	var ratio := _db.sell_ratio()
	_check_true("o comerciante paga menos do que cobra", ratio > 0.0 and ratio < 1.0,
		"%.2f" % ratio)

	# O spread e o que impede o loop infinito de comprar e revender.
	var buy := _db.item_value(POULTICE)
	var sell := _db.sell_price(POULTICE)
	_check_true("revender da prejuizo", sell < buy, "compra %d, vende %d" % [buy, sell])

	# Piso de 1: mineral barato nao pode arredondar para zero, ou vira lixo
	# que nunca sai do inventario.
	_check_true("mineral barato ainda vale algo", _db.sell_price(STONE) >= 1,
		"Pedra vende por %d" % _db.sell_price(STONE))
	_check("item sem preco nao vende", _db.sell_price("ITM-999"), 0)


# ---------------------------------------------------------------------------
# bolsa e inventário
# ---------------------------------------------------------------------------

func _test_purse() -> void:
	print("bolsa:")
	var inv := PlayerInventory.new()
	_check("comeca zerada", inv.currency, 0)

	inv.add_currency(100)
	_check("credita", inv.currency, 100)
	_check_true("gasta o que da", inv.spend(30))
	_check("debitou", inv.currency, 70)

	# Tudo ou nada: um debito parcial deixaria o jogador mais pobre sem
	# receber a compra.
	_check_true("nao gasta o que nao tem", not inv.spend(999))
	_check("e a bolsa nao mexeu", inv.currency, 70)
	_check_true("can_afford concorda", inv.can_afford(70) and not inv.can_afford(71))

	inv.add(STONE, 3)
	_check_true("remove o que tem", inv.remove(STONE, 2))
	_check("sobrou 1", inv.quantity(STONE), 1)
	_check_true("nao remove alem do que tem", not inv.remove(STONE, 5))
	_check("e a quantidade nao mexeu", inv.quantity(STONE), 1)
	_check_true("remover tudo tira a linha", inv.remove(STONE))
	_check("entries nao lista zerados", inv.entries().size(), 0)


# ---------------------------------------------------------------------------
# tela de troca
# ---------------------------------------------------------------------------

func _test_shop_screen() -> void:
	print("tela de troca:")
	var inv := PlayerInventory.new()
	inv.add_currency(200)

	var shop := MerchantScreen.new()
	root.add_child(shop)
	shop.setup(_db, inv, MERCHANT)

	# Compra: debita a bolsa e entrega o item, um pelo outro.
	var price := _db.item_value(POULTICE)
	shop._buy(POULTICE)
	_check("a bolsa pagou", inv.currency, 200 - price)
	_check("o item entrou", inv.quantity(POULTICE), 1)

	# Sem saldo: nada acontece dos dois lados.
	var poor := PlayerInventory.new()
	poor.add_currency(1)
	var shop2 := MerchantScreen.new()
	root.add_child(shop2)
	shop2.setup(_db, poor, MERCHANT)
	shop2._buy(POULTICE)
	_check("sem saldo, a bolsa nao mexe", poor.currency, 1)
	_check("e nada entra", poor.quantity(POULTICE), 0)

	# Venda: tira o item e credita.
	inv.add(STONE, 2)
	var before := inv.currency
	shop._sell(STONE)
	_check("a venda tirou uma unidade", inv.quantity(STONE), 1)
	_check_true("e creditou", inv.currency == before + _db.sell_price(STONE),
		"%d → %d" % [before, inv.currency])

	# Vender o que não se tem não pode creditar nada.
	var purse := inv.currency
	shop._sell("ITM-012")
	_check("vender o que nao se tem nao credita", inv.currency, purse)

	# O comerciante só vende o que está no catálogo dele — mineral não está.
	var wallet := inv.currency
	shop._buy(STONE)
	_check("nao compra o que nao esta a venda", inv.currency, wallet)

	shop.free()
	shop2.free()


# ---------------------------------------------------------------------------
# mundo
# ---------------------------------------------------------------------------

func _test_world_wiring() -> void:
	print("no mundo:")
	var inv := _world.inventory()
	_check_true("o jogador comeca com a bolsa do bestiario",
		inv.currency == _db.starting_currency(),
		"%d" % inv.currency)

	var merchant: MerchantActor = null
	for child in _world.get_children():
		if child is MerchantActor:
			merchant = child as MerchantActor
			break
	_check_true("o comerciante nasceu no mapa", merchant != null,
		merchant.display_name if merchant else "nenhum")
	if merchant == null:
		return

	# Longe demais: o clique avisa e nao abre.
	var player: Node3D = _world.get_node_or_null("Player")
	merchant.global_position = player.global_position + Vector3(50, 0, 0)
	_world.handle_click_on_interactable(merchant)
	_check_true("de longe nao abre a loja",
		_world.get_node_or_null("ShopLayer") == null)

	# Perto: abre e congela o mundo.
	merchant.global_position = player.global_position + Vector3(2, 0, 0)
	_world.handle_click_on_interactable(merchant)
	_check_true("de perto abre a loja", _world.get_node_or_null("ShopLayer") != null)
	_check_true("o mundo congelou", root.get_tree().paused)

	# Minerar durante a negociacao seria comer o bolo e ter o bolo.
	var items_before := inv.total_items()
	_world.start_mining()
	_check("nao minera com a loja aberta", inv.total_items(), items_before)

	var layer := _world.get_node_or_null("ShopLayer")
	var screen: MerchantScreen = layer.get_child(0)
	screen.closed.emit()
	_check_true("fechar solta o mundo", not root.get_tree().paused)
	# A referência cai na hora; o nó só sai da árvore no fim do quadro, porque
	# `queue_free` é diferido. Conferir o `_shop` é o que prova que uma segunda
	# loja pode abrir — que é o efeito que importa.
	_check_true("e a loja deixa de estar aberta", _world.get("_shop") == null)
	_check_true("a HUD do mapa voltou",
		(_world.get_node_or_null("HudLayer/InventoryPanel") as Control).visible)



## Com um overlay modal por cima, todo ponto de entrada público do mundo fica
## inerte — e volta a funcionar quando ele fecha.
##
## Em jogo quem segura isso é o pause (`WorldRoot._modal_open` explica), que
## impede o evento de chegar. Estes pontos são públicos porque teste headless
## não sintetiza mouse nem tecla, então eles pulam o pause e batem direto no
## guarda — que é justamente o que precisa de prova: ele estava escrito à mão
## em dez lugares e em quatro composições diferentes, e nada acusava a
## divergência.
##
## O posto do Relicário é o modal escolhido aqui de propósito: é o único que
## nenhuma outra suíte abre.
func _test_modal_guard() -> void:
	print("guarda modal:")
	var player: Node3D = _world.get_node_or_null("Player")
	var station: RelicStationActor = null
	for child in _world.get_children():
		if child is RelicStationActor:
			station = child as RelicStationActor
			break
	_check_true("o posto do relicario nasceu no mapa", station != null)
	if station == null:
		return

	# Guardião do portal é a forma física de uma travessia que exige Glifo:
	# existe quando o catálogo pede, e não existe quando não pede. Antes era
	# "um guardião, sempre", com o Glifo exigido cravado em código — e desde
	# que a topologia virou dado (`map_connections`) isso passaria a poder
	# contradizer o catálogo, barrando uma passagem que o dado diz ser livre.
	var db := _world.get("_db") as BestiaryData
	var gated := false
	if db:
		for link in db.connections_from_map(_world.map_code):
			if link is Dictionary and (link as Dictionary).get("requiredGlyph") != null:
				gated = true
				break
	var guardian_in_world := _world.get_node_or_null("PortalGuardian") != null
	_check("guardiao existe se e so se ha travessia exigindo Glifo",
		guardian_in_world, gated)

	station.global_position = player.global_position + Vector3(2, 0, 0)
	_world.handle_click_on_interactable(station)
	_check_true("de perto abre o posto",
		_world.get_node_or_null("RelicStationLayer") != null)
	_check_true("e congela o mundo", root.get_tree().paused)

	var inv := _world.inventory()
	var items_before := inv.total_items()
	_world.start_mining()
	_check("nao minera com o posto aberto", inv.total_items(), items_before)

	_world.toggle_roster_window()
	_check_true("a janela do time nao abre por cima",
		not (_world.get("_roster_window") as RosterWindow).is_open())

	_world.toggle_set_window()
	_check_true("a janela do set nao abre por cima",
		not (_world.get("_set_window") as PlayerSetWindow).is_open())

	# Outro ator interativo do mapa não pode engatar por baixo do posto.
	var merchant: MerchantActor = null
	for child in _world.get_children():
		if child is MerchantActor:
			merchant = child as MerchantActor
			break
	if merchant:
		merchant.global_position = player.global_position + Vector3(2, 0, 0)
		_world.handle_click_on_interactable(merchant)
		# Estado síncrono, não o nó: o `ShopLayer` do teste anterior ainda pode
		# estar na árvore, porque `queue_free` é diferido. `_shop` cai na hora.
		_check_true("a loja nao abre por baixo do posto", _world.get("_shop") == null)

	var layer := _world.get_node_or_null("RelicStationLayer")
	var screen: RelicStationScreen = layer.get_child(0)
	screen.closed.emit()
	_check_true("fechar solta o mundo", not root.get_tree().paused)
	_check_true("e o posto deixa de estar aberto", _world.get("_relic_screen") == null)

	# E o mundo volta a responder — sem isto o teste passaria com um guarda
	# travado em "sempre bloqueado".
	_world.toggle_roster_window()
	_check_true("com o posto fechado, a janela do time abre",
		(_world.get("_roster_window") as RosterWindow).is_open())
	_world.toggle_roster_window()

## Os quatro pontos fixos apoiam o corpo no chão pela mesma conta, e ela
## respeita a altura do terreno no ponto.
##
## `InteractableActor.ground_on_spot()` **soma** meia altura ao `y` que veio no
## spot, em vez de atribuir. Enquanto todo ator estiver em chão plano (`y = 0`)
## as duas contas dão o mesmo número — e foi assim que a divergência passou:
## comerciante e posto somavam (estão na costa, elevada), arena e guardião
## atribuíam (estão no centro plano), e os dois pares acertavam por
## coincidência de posição.
##
## O ROADMAP tem "mover portais/guardião para a costa" em aberto. Este teste é
## o que faz essa mudança ser de um arquivo só: com atribuição, um ator em
## terreno elevado afunda até a altura do chão plano.
func _test_actor_grounding() -> void:
	print("apoio no chao:")
	var ground := 2.4   # altura de costa plausível, longe de zero

	var merchant := MerchantActor.create({"code": "NPC-999", "name": "Teste"},
		Vector3(0.0, ground, 0.0))
	_world.add_child(merchant)
	_check_true("comerciante sobe meia altura a partir do terreno",
		is_equal_approx(merchant.position.y, ground + MerchantActor.HEIGHT * 0.5),
		"%.2f" % merchant.position.y)

	var station := RelicStationActor.create(Vector3(0.0, ground, 0.0))
	_world.add_child(station)
	_check_true("posto sobe meia altura a partir do terreno",
		is_equal_approx(station.position.y, ground + RelicStationActor.HEIGHT * 0.5),
		"%.2f" % station.position.y)

	# Estes dois são os que atribuíam. Em chão plano nada mudou; aqui a
	# diferença aparece.
	var arena := ArenaActor.create({"code": "NPC-998", "name": "Teste"},
		Vector3(0.0, ground, 0.0), "CRT-021", 18, "DALETH")
	_world.add_child(arena)
	_check_true("arena sobe meia altura a partir do terreno",
		is_equal_approx(arena.position.y, ground + ArenaActor.HEIGHT * 0.5),
		"%.2f" % arena.position.y)

	var guardian := PortalGuardianActor.create(Vector3(0.0, ground, 0.0),
		"DALETH", "Titanor", null)
	_world.add_child(guardian)
	_check_true("guardiao sobe meia altura a partir do terreno",
		is_equal_approx(guardian.position.y, ground + PortalGuardianActor.HEIGHT * 0.5),
		"%.2f" % guardian.position.y)

	# E em chão plano o resultado segue o de sempre — a mudança não move nada
	# do que já estava colocado.
	var flat := RelicStationActor.create(Vector3.ZERO)
	_world.add_child(flat)
	_check_true("em chao plano continua em meia altura",
		is_equal_approx(flat.position.y, RelicStationActor.HEIGHT * 0.5),
		"%.2f" % flat.position.y)

	for a in [merchant, station, arena, guardian, flat]:
		a.queue_free()


## A vila da costa (2026-09-20): três estruturas que não se sobrepõem, todas
## em chão plano do platô, dentro do bioma da costa — com o spawn do jogador
## junto.
##
## A sobreposição é medida contra a estrutura REAL na árvore
## (`model_footprint`, a AABB escalada do `.glb`), não contra um número
## escrito aqui: foi a largura de 5,7 m das estruturas a 3× que o espaçamento
## antigo (4,5 m, calibrado para cápsulas) não sabia. O chão plano e o bioma
## importam porque a âncora deixou de coincidir com `COAST_TOP` por acaso e
## passou a ser um recuo declarado — se alguém encolher o recuo até a rampa,
## ou alargar o espaçamento até sair de `RGN-001`, é aqui que aparece.
func _test_village_layout() -> void:
	print("layout da vila:")
	var terrain := _world.get("_terrain") as MapTerrain
	var biomes := _world.get("_map_biomes") as MapBiomes
	var actors := _village_actors()
	_check_true("os tres servicos da vila nasceram", actors.size() == 3, "%d" % actors.size())

	var spots := [
		WorldPopulator.CRAFTING_BENCH_SPOT, WorldPopulator.MERCHANT_SPOT,
		WorldPopulator.RELIC_STATION_SPOT, WorldPopulator.PLAYER_START_SPOT]
	var off_plateau: Array = []
	var off_biome: Array = []
	for s in spots:
		var p: Vector3 = s
		if absf(terrain.height_at(p) - MapTerrain.LAND_HEIGHT) > 0.01 or not terrain.on_coast(p):
			off_plateau.append("%s h=%.2f" % [p, terrain.height_at(p)])
		if biomes and biomes.biome_at(p) != "BIO-002":
			off_biome.append("%s -> %s" % [p, biomes.biome_at(p)])
	_check_true("servicos e spawn em chao plano da costa", off_plateau.is_empty(), str(off_plateau))
	_check_true("servicos e spawn dentro do bioma da costa (RGN-001)", off_biome.is_empty(), str(off_biome))

	# Vizinho a vizinho, ao longo da linha da vila: o vão entre paredes tem de
	# ser positivo — pelo menos 1 m, para a pessoa de um não encostar no outro.
	actors.sort_custom(func(a: InteractableActor, b: InteractableActor) -> bool:
		return a.global_position.x < b.global_position.x)
	var overlaps: Array = []
	for i in range(1, actors.size()):
		var left := actors[i - 1] as InteractableActor
		var right := actors[i] as InteractableActor
		var gap := (right.global_position.x - left.global_position.x) \
			- (left.model_footprint.x + right.model_footprint.x) * 0.5
		if gap < 1.0:
			overlaps.append("%s|%s vao=%.2f" % [left.name, right.name, gap])
	_check_true("estruturas vizinhas nao se sobrepoem (vao >= 1 m)", overlaps.is_empty(), str(overlaps))
	_check_true("as estruturas foram medidas (footprint > 0)",
		actors.all(func(a: InteractableActor) -> bool: return a.model_footprint.x > 0.0))


## Cada serviço da vila tem uma pessoa diante da estrutura: rig do kit, pés
## no chão, encarando o mar, na pose combinada e em loop, com a placa sobre
## a cabeça e uma cápsula de clique própria. É o contrato de
## `InteractableActor.attach_npc` — sem ele, a receita do bundle volta a ser
## código morto sem ninguém notar (foi assim entre 2026-09-18 e 20).
func _test_npc_rigs_in_world() -> void:
	print("pessoas da vila:")
	var terrain := _world.get("_terrain") as MapTerrain
	var expected := {
		"Merchant_NPC-001": MerchantActor.NPC_CLIP,
		"RelicStation": RelicStationActor.NPC_CLIP,
		"CraftingBench": CraftingBenchActor.NPC_CLIP,
	}
	for actor in _village_actors():
		var a := actor as InteractableActor
		var npc := a.get_node_or_null("Npc") as CharacterRig
		_check_true("%s tem uma pessoa (CharacterRig)" % a.name, npc != null)
		if npc == null:
			continue
		var ground := terrain.height_at(a.global_position)
		_check_true("%s: pes no chao" % a.name, absf(npc.global_position.y - ground) < 0.02,
			"%.2f vs %.2f" % [npc.global_position.y, ground])
		_check_true("%s: pes na base do corpo do ator" % a.name,
			is_equal_approx(npc.position.y, -a.body_height * 0.5), "%.2f" % npc.position.y)
		_check_true("%s: diante da fachada" % a.name, npc.position.z > a.model_footprint.y * 0.5,
			"z=%.2f, fundo/2=%.2f" % [npc.position.z, a.model_footprint.y * 0.5])
		_check_true("%s: encara o mar (+Z)" % a.name, absf(wrapf(npc.rotation.y, -PI, PI)) > PI - 0.01,
			"%.2f" % npc.rotation.y)
		var clip: String = expected.get(String(a.name), "")
		var anim := npc.get("_anim") as AnimationPlayer
		_check_true("%s: toca %s" % [a.name, clip], anim != null and anim.current_animation == clip,
			anim.current_animation if anim else "sem AnimationPlayer")
		_check_true("%s: a pose e loop" % a.name,
			anim != null and anim.has_animation(clip)
			and anim.get_animation(clip).loop_mode == Animation.LOOP_LINEAR)
		var sign := a.get_node_or_null("Sign") as MeshInstance3D
		_check_true("%s: a placa flutua sobre a cabeca da pessoa" % a.name,
			sign != null and Vector2(sign.position.x - npc.position.x, sign.position.z - npc.position.z).length() < 0.01
			and sign.position.y - npc.position.y > 1.8,
			"placa y=%.2f, pes y=%.2f" % [sign.position.y if sign else 0.0, npc.position.y])
		_check_true("%s: a pessoa tem capsula de clique" % a.name,
			a.get_node_or_null("NpcCollision") is CollisionShape3D)


## Só os que o `WorldPopulator` nomeou — os atores avulsos que outros testes
## desta suíte criam ficam de fora.
func _village_actors() -> Array:
	var out: Array = []
	for child in _world.get_children():
		var n := String(child.name)
		if n.begins_with("Merchant_") or n == "RelicStation" or n == "CraftingBench":
			out.append(child)
	return out


# ---------------------------------------------------------------------------

func _finish() -> void:
	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


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
