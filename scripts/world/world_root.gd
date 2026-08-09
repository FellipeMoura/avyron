class_name WorldRoot
extends Node3D

## Raiz do mapa de exploração e árbitro do encontro.
##
## A batalha acontece **no mesmo espaço**, sem corte para outra cena: a tela
## de combate entra como overlay, a câmera dá o zoom de aproximação e o mundo
## congela atrás. É o que `escala-e-camera-de-batalha` especifica, e é por
## isso que a troca de cena que existia aqui antes saiu.
##
## Fluxo de encontro por clique:
##   1º clique numa criatura → seleciona (destaque no material) + painel de
##     identificação aparece.
##   2º clique na mesma criatura → dispara `request_engage` no actor, que
##     emite `engaged` e vira em combate.
##   clique numa criatura diferente → troca a seleção (equivale ao 1º clique
##     dela).
##   clique fora ou Esc → limpa seleção.
##   afastar mais de `DESELECT_DISTANCE` da selecionada → auto-desseleciona,
##     porque uma seleção "esquecida" atrás de você é ruído visual.
##
## Contato físico com a criatura não faz mais nada: a decisão de entrar em
## combate é sempre do jogador. Criaturas agressivas continuam perseguindo,
## por pressão visual, mas quem aperta o gatilho é o mouse.
##
## ## A criatura ativa amarra os três sistemas
##
## Quem está à frente no `PlayerRoster` é a mesma criatura em toda parte: anda
## ao lado do jogador, entra no duelo, e — pela **classe** dela — decide o que
## a mineração produz e em que ritmo. Trocar a ativa pela janela do time (`T`)
## não é ajuste de menu: muda o que sai do chão no próximo `F`.

const DUEL_SCENE := "res://scenes/duel.tscn"

## Alcance máximo do raycast do clique. 60 m cobre folgadamente qualquer
## coisa visível dentro do enquadramento ortográfico de 12 unidades.
const CLICK_RAY_LENGTH := 60.0

## Distância a partir da qual a seleção cai sozinha. Um pouco além do raio de
## detecção da criatura (6 m) — o jogador se afastou o bastante para o alvo
## não ser mais o assunto imediato.
const DESELECT_DISTANCE := 15.0

## Criatura com que o jogador começa. Vira o slot 0 do time; as capturas
## entram como reserva atrás dela.
@export var starter_code := "CRT-002"
@export var encounter_level := 10

## Onde o jogador está. O mapa escolhe o elenco selvagem; o bioma é metade da
## fórmula de mineração — a outra metade é a classe da criatura ativa.
##
## Fica em `@export` em vez de derivado do bundle porque `maps` não carrega a
## junção mapa↔bioma no export. Quando carregar, isto vira consulta.
@export var map_code := "PZ-01"
@export var biome_code := "BIO-001"

var _camera: IsoCamera
var _player: Node3D
var _spawner: CreatureSpawner
var _duel: DuelScreen
var _engaged_actor: CreatureActor
var _selected: CreatureActor
var _info: CreatureInfoPanel
var _hint: Label
var _db: BestiaryData
var _companion: CompanionActor
var _roster: PlayerRoster
var _active_panel: ActiveCreaturePanel
var _roster_window: RosterWindow
var _inventory: PlayerInventory
var _inventory_panel: InventoryPanel
var _mine_rng := RandomNumberGenerator.new()
var _mine_cooldown := 0.0
var _mine_label: Label
var _merchants: Array[MerchantActor] = []
var _shop: MerchantScreen

## Onde o comerciante fica. Posição de cena, não de bestiário: o catálogo diz
## quem existe e em que mapa, o layout do mundo diz onde. Quando houver
## vilarejo modelado, isto vira um marcador na cena.
const MERCHANT_SPOT := Vector3(6.0, 0.0, -6.0)

## Segundos entre minerações consecutivas, antes do perfil de trabalho da
## classe ativa. Theria (×1.1) espera menos, Draconis (×0.9) espera mais.
const MINE_COOLDOWN_SEC := 3.0


func _ready() -> void:
	_camera = get_node_or_null("IsoCamera") as IsoCamera
	_player = get_node_or_null("Player")
	_db = get_node_or_null("/root/Bestiary") as BestiaryData

	# A câmera continua processando durante a pausa. Um Tween acompanha o
	# estado de pausa do nó a que está preso, então sem isto o zoom de entrada
	# em combate simplesmente não animaria — ficaria travado no valor inicial.
	if _camera:
		_camera.process_mode = Node.PROCESS_MODE_ALWAYS

	_inventory = PlayerInventory.new()
	# A bolsa inicial vem do bestiário, não de uma constante daqui: quanto o
	# jogador começa com é decisão de balanceamento, e balanceamento é PATCH
	# versionado.
	if _db:
		_inventory.add_currency(_db.starting_currency())
	_mine_rng.randomize()

	# O time precisa existir antes da companheira e da HUD: quem anda ao lado
	# do jogador é a ativa dele, não o `starter_code` solto.
	_roster = PlayerRoster.new()
	_roster.setup(_db, encounter_level, starter_code)

	_spawner = CreatureSpawner.new()
	_spawner.name = "CreatureSpawner"
	_spawner.level = encounter_level
	# O mapa é do mundo, não do spawner: quem povoa e quem minera têm de
	# concordar sobre onde o jogador está.
	_spawner.map_code = map_code
	add_child(_spawner)
	_spawner.creature_engaged.connect(_on_creature_engaged)
	# Mantém o hint em sincronia sem precisar polling: qualquer mudança de
	# população (spawn inicial, remoção pós-batalha, respawn) atualiza o
	# contador na HUD.
	_spawner.population_changed.connect(_update_hint)

	_spawn_companion()
	_spawn_merchants()
	_build_hud()
	_update_hint()


## Instancia os comerciantes que o bestiário coloca neste mapa. Zero é estado
## normal — um mapa sem comerciante é um mapa sem comerciante, não um erro.
func _spawn_merchants() -> void:
	if _db == null:
		return
	var spot := MERCHANT_SPOT
	for data in _db.merchants_in_map(map_code):
		var actor := MerchantActor.create(data, spot)
		actor.name = "Merchant_%s" % str(data.get("code", ""))
		actor.engaged.connect(_on_merchant_engaged)
		add_child(actor)
		_merchants.append(actor)
		# Segundo comerciante no mesmo mapa fica ao lado do primeiro em vez de
		# dentro dele. Provisório até haver vilarejo com posições próprias.
		spot += Vector3(2.5, 0.0, 0.0)


func _spawn_companion() -> void:
	# Sem player não faz sentido spawnar quem segue; sem bestiário não temos
	# como resolver o código do starter em cor/tamanho.
	if _player == null or _db == null:
		return
	_companion = CompanionActor.create(_db, _roster.active(), _player)
	if _companion == null:
		return
	_companion.name = "Companion"
	add_child(_companion)


func _process(delta: float) -> void:
	if _mine_cooldown > 0.0:
		_mine_cooldown = maxf(0.0, _mine_cooldown - delta)

	# O time se recupera com o tempo de mapa. Não precisa de trava para não
	# curar durante o combate: o mundo fica pausado, e um nó pausado não
	# processa. É a mesma razão de a câmera precisar de PROCESS_MODE_ALWAYS
	# logo acima — aqui o comportamento padrão é justamente o desejado.
	if _roster:
		_roster.regenerate(delta)

	# Solta a seleção quando o jogador vagou para longe. Sem isto, um alvo
	# esquecido do outro lado do mapa continua brilhando e o painel fica
	# poluindo a HUD.
	if _selected == null:
		return
	if not is_instance_valid(_selected):
		_clear_selection()
		return
	if _player and _selected.global_position.distance_to(_player.global_position) > DESELECT_DISTANCE:
		_clear_selection()


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)

	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color("#6B7280"))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 20
	_hint.offset_top = -44
	_hint.offset_bottom = -16
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hint)

	_info = CreatureInfoPanel.new()
	_info.name = "CreatureInfoPanel"
	layer.add_child(_info)

	_active_panel = ActiveCreaturePanel.new()
	_active_panel.name = "ActiveCreaturePanel"
	layer.add_child(_active_panel)

	_roster_window = RosterWindow.new()
	_roster_window.name = "RosterWindow"
	_roster_window.activate_requested.connect(activate_slot)
	layer.add_child(_roster_window)

	_inventory_panel = InventoryPanel.new()
	_inventory_panel.name = "InventoryPanel"
	layer.add_child(_inventory_panel)
	_inventory.changed.connect(_on_inventory_changed)

	if _db:
		_active_panel.setup(_db, biome_code)
		_roster_window.setup(_db)
		_inventory_panel.setup(_db)
	# Uma assinatura só mantém os dois painéis de time em dia — captura e troca
	# de ativa passam pelo mesmo sinal, então nenhum caminho pode esquecer de
	# redesenhar.
	_roster.changed.connect(_on_roster_changed)
	_on_roster_changed()

	_mine_label = Label.new()
	_mine_label.name = "MineLabel"
	_mine_label.add_theme_color_override("font_color", Color("#7A8C6B"))
	_mine_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_mine_label.offset_left = 20
	_mine_label.offset_top = -68
	_mine_label.offset_bottom = -48
	_mine_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mine_label.hide()
	layer.add_child(_mine_label)


func _update_hint() -> void:
	if _hint == null:
		return
	var count := _spawner.actors().size() if _spawner else 0
	_hint.text = "WASD anda · Shift corre · F minera · T time · clique numa criatura para ver, clique de novo para lutar   (%d no mapa)" % count


# ---------------------------------------------------------------------------
# input / seleção
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Durante a batalha ou a loja o overlay processa em separado — nada aqui
	# responde. Sem isto, `F` mineraria no meio de uma negociação.
	if _duel != null or _shop != null:
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		_handle_key(key.keycode)
		return

	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	# Clique que cai *sobre* a janela do time nem chega aqui — ela é o único
	# Control da HUD que para o evento. O que chega é clique no mundo com a
	# janela aberta, e selecionar uma criatura escondida atrás dela seria
	# acidente puro.
	if _roster_open():
		get_viewport().set_input_as_handled()
		return

	handle_click_at(mb.position)
	get_viewport().set_input_as_handled()


func _handle_key(keycode: Key) -> void:
	if keycode == KEY_T:
		toggle_roster_window()
	elif keycode == KEY_ESCAPE:
		# A janela aberta tem prioridade sobre a seleção: `Esc` fecha o que
		# está por cima, que é a leitura que qualquer um espera.
		if _roster_open():
			_roster_window.close()
		elif _selected != null:
			_clear_selection()
		else:
			return
	# Limitado por MAX_SLOTS, não por KEY_9: o rodapé da janela promete
	# "1–6", e uma tecla que aceita mais do que o texto diz é ruído.
	elif _roster_open() and keycode >= KEY_1 and keycode < KEY_1 + PlayerRoster.MAX_SLOTS:
		activate_slot(keycode - KEY_1)
	elif keycode == KEY_F and not _roster_open():
		trigger_mine()
	else:
		return
	get_viewport().set_input_as_handled()


func _roster_open() -> bool:
	return _roster_window != null and _roster_window.is_open()


## Ponto de entrada do clique. Público porque os testes headless disparam
## seleção e engate sem passar por evento de mouse — mais estável do que
## sintetizar `InputEventMouseButton` com coordenadas de tela.
func handle_click_at(screen_pos: Vector2) -> void:
	var hit := _pick_body(screen_pos)

	# Comerciante e criatura respondem ao mesmo gesto, mas não ao mesmo
	# fluxo: criatura tem seleção e segundo clique, comerciante abre direto —
	# não há decisão de "vale a pena entrar?" a ser tomada antes de olhar a
	# vitrine.
	if hit is MerchantActor:
		handle_click_on_merchant(hit as MerchantActor)
		return
	handle_click_on(hit as CreatureActor)


## Abre a loja, se o jogador estiver perto o bastante. Público pela mesma
## razão dos outros pontos de entrada: teste headless não sintetiza mouse.
func handle_click_on_merchant(actor: MerchantActor) -> void:
	if actor == null or _shop != null or _duel != null:
		return
	if _player and actor.flat_distance_to(_player.global_position) > MerchantActor.INTERACT_RANGE:
		_show_mine_msg("%s esta longe demais." % actor.display_name)
		return
	_clear_selection()
	actor.request_engage()


func handle_click_on(actor: CreatureActor) -> void:
	if actor == null:
		_clear_selection()
		return
	if actor == _selected:
		# Segundo clique na mesma criatura → engate.
		var to_engage := _selected
		_clear_selection()
		to_engage.request_engage()
	else:
		_select(actor)


## Devolve o corpo clicado — criatura, comerciante, ou null. Quem decide o que
## fazer com ele é `handle_click_at`; misturar as duas responsabilidades aqui
## foi o que fez esta função ter tipo de retorno fechado antes de existir mais
## de um tipo de coisa clicável.
func _pick_body(screen_pos: Vector2) -> Node3D:
	if _camera == null:
		return null
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * CLICK_RAY_LENGTH
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	# Ignora o próprio jogador — clicar em cima dele com uma criatura atrás
	# não deve "roubar" o clique da criatura.
	if _player and _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	if collider is CreatureActor or collider is MerchantActor:
		return collider as Node3D
	return null


func _select(actor: CreatureActor) -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = actor
	_selected.set_selected(true)
	if _info and _db:
		_info.show_for(_db, actor.creature_code, encounter_level, actor.size_meters)


func _clear_selection() -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = null
	if _info:
		_info.clear()


func selected_actor() -> CreatureActor:
	return _selected


func roster() -> PlayerRoster:
	return _roster


func inventory() -> PlayerInventory:
	return _inventory


# ---------------------------------------------------------------------------
# time
# ---------------------------------------------------------------------------

## Abre/fecha a janela do time. Público pelo mesmo motivo que `handle_click_on`
## e `trigger_mine`: os testes headless exercitam o fluxo pela API, não
## sintetizando tecla.
func toggle_roster_window() -> void:
	if _roster_window == null or _duel != null:
		return
	_roster_window.toggle()
	if _roster_window.is_open():
		# A seleção pendurada atrás da janela não teria como ser cancelada por
		# clique enquanto ela estivesse aberta.
		_clear_selection()
		_refresh_roster_window()


## Manda a criatura do slot à frente. Ignora silenciosamente slot vazio ou o
## da própria ativa — os dois são cliques sem consequência, não erros.
func activate_slot(index: int) -> void:
	if _roster == null or not _roster.set_active(index):
		return
	_show_mine_msg("À frente: %s" % _creature_name(_roster.active()))


## Reconstrói tudo que depende de quem está à frente. É o único ponto que sabe
## que trocar a ativa mexe em três coisas — companheira, painel e janela.
func _on_roster_changed() -> void:
	var active := _roster.active()

	if _companion and is_instance_valid(_companion) and _db and active != "" \
			and _companion.creature_code != active:
		_companion.set_creature(_db, active)

	if _active_panel:
		var i := _roster.active_index()
		_active_panel.refresh(active, encounter_level, _roster.size(),
			_roster.hp_at(i), _roster.max_hp_at(i))
	_refresh_roster_window()


func _refresh_roster_window() -> void:
	if _roster_window and _roster_window.is_open():
		_roster_window.refresh(_roster, encounter_level)


func _creature_name(code: String) -> String:
	if _db == null or code == "":
		return code
	return str(_db.creature(code).get("name", code))


## Classe da criatura ativa — a entrada da fórmula de mineração. "" quando não
## há ativa, o que faz `MiningTable` cair no peso do bioma sozinho.
func _active_class_code() -> String:
	if _db == null or _roster == null:
		return ""
	return str(_db.creature(_roster.active()).get("class", ""))


# ---------------------------------------------------------------------------
# mineração
# ---------------------------------------------------------------------------

## Ponto de entrada da tecla F. Público para os testes headless dispararem
## sem sintetizar InputEventKey.
##
## O que sai daqui é decidido por dois fatores do bundle: o bioma em que o
## jogador está e a classe da criatura que ele tem à frente. Nada de tabela
## local — trocar a ativa muda o resultado, e é para ser sentido.
func trigger_mine() -> void:
	if _duel != null or _shop != null:
		return  # não minera durante combate nem negociação
	if _mine_cooldown > 0.0:
		_show_mine_msg("Aguardando... (%.1fs)" % _mine_cooldown)
		return

	var class_code := _active_class_code()
	var mineral := MiningTable.sample(_mine_rng, _db, class_code, biome_code)
	if mineral.is_empty():
		# Bundle exportado antes do módulo de mineração, ou bioma sem taxas
		# cadastradas. Dizer isso é melhor que uma tecla que não faz nada.
		_show_mine_msg("Nada para minerar aqui.")
		return

	_inventory.add(str(mineral["code"]))
	_mine_cooldown = MINE_COOLDOWN_SEC / MiningTable.speed_modifier(_db, class_code)
	_show_mine_msg("Coletou: %s" % str(mineral["name"]))


func _show_mine_msg(text: String) -> void:
	if _mine_label == null:
		return
	_mine_label.text = text
	_mine_label.show()
	# Remove a mensagem automaticamente num único Tween — cancela o anterior
	# se uma segunda mineração ocorrer antes dos 2 s expirarem.
	var t := create_tween()
	t.tween_interval(2.0)
	t.tween_callback(_mine_label.hide)


func _on_inventory_changed() -> void:
	if _inventory_panel:
		_inventory_panel.refresh(_inventory.entries(), _inventory.currency)


# ---------------------------------------------------------------------------
# comércio
# ---------------------------------------------------------------------------

func _on_merchant_engaged(actor: MerchantActor) -> void:
	if _shop != null or _duel != null:
		return

	_hide_world_hud()

	_shop = MerchantScreen.new()
	_shop.name = "MerchantScreen"
	_shop.closed.connect(_on_shop_closed)

	var layer := CanvasLayer.new()
	layer.name = "ShopLayer"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(_shop)
	add_child(layer)

	# `setup` depois de entrar na árvore: o `_ready` é quem constrói o label,
	# e `setup` desenha nele.
	_shop.setup(_db, _inventory, actor.merchant_code)

	# Sem zoom de câmera aqui, ao contrário do combate. A aproximação existe
	# para o duelo porque o que importa vira o corpo das duas criaturas; numa
	# negociação o que importa é a tabela, e mexer na câmera seria movimento
	# sem função.
	get_tree().paused = true


func _on_shop_closed() -> void:
	get_tree().paused = false
	var layer := get_node_or_null("ShopLayer")
	if layer:
		layer.queue_free()
	_shop = null
	_show_world_hud()


## Esconde a HUD de exploração. Sem isto o hint de WASD e os painéis vazam
## atrás do overlay — ruído puro enquanto a atenção está em outra coisa.
func _hide_world_hud() -> void:
	if _hint:
		_hint.visible = false
	if _active_panel:
		_active_panel.visible = false
	if _roster_window:
		_roster_window.close()
	if _inventory_panel:
		_inventory_panel.visible = false
	if _mine_label:
		_mine_label.hide()


func _show_world_hud() -> void:
	if _hint:
		_hint.visible = true
	if _active_panel:
		_active_panel.visible = true
	if _inventory_panel:
		_inventory_panel.visible = true


# ---------------------------------------------------------------------------
# encontro
# ---------------------------------------------------------------------------

func _on_creature_engaged(actor: CreatureActor) -> void:
	if _duel != null:
		return  # já há um combate em curso

	# Time inteiro caído: não há com quem lutar. Abrir o duelo aqui daria uma
	# tela travada na substituição, sem ninguém para escolher. A saída é
	# esperar a recuperação — que é justamente o custo que o HP persistente
	# existe para cobrar.
	if _roster.alive_count() == 0:
		_clear_selection()
		actor.reset_engagement()
		_show_mine_msg("Nenhuma criatura de pe. Espere se recuperarem.")
		return

	_engaged_actor = actor
	_clear_selection()

	# O painel de identificação já tinha sido escondido pelo `_clear_selection`.
	_hide_world_hud()

	var packed: PackedScene = load(DUEL_SCENE)
	_duel = packed.instantiate() as DuelScreen
	# O time inteiro entra, com o HP com que cada uma saiu do último combate.
	# `player_code` continua preenchido só como rede: se o time chegar vazio, a
	# tela ainda sabe com quem lutar.
	_duel.player_code = _roster.active()
	_duel.player_party = _roster.to_party()
	_duel.player_active_index = _roster.active_index()
	# A mesma instância, não uma cópia: a resina gasta na batalha tem de sumir
	# da bolsa que o mapa desenha.
	_duel.inventory = _inventory
	_duel.enemy_code = actor.creature_code
	_duel.duel_level = encounter_level
	_duel.closed.connect(_on_duel_closed)

	# CanvasLayer para o overlay ficar acima do 3D sem herdar a pausa do
	# mundo — a tela precisa continuar respondendo a tecla.
	var layer := CanvasLayer.new()
	layer.name = "DuelLayer"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(_duel)
	add_child(layer)

	if _camera:
		_camera.enter_battle()
	# Congela exploração e IA; o overlay segue processando.
	get_tree().paused = true


func _on_duel_closed(outcome: int) -> void:
	get_tree().paused = false
	if _camera:
		_camera.exit_battle()

	# Lido **antes** de soltar o overlay: depois do `queue_free` a batalha vai
	# junto, e com ela o HP de todo mundo.
	var fought: Battle = _duel.battle if _duel else null
	var captured_hp := -1
	if fought:
		# Quem terminou a luta em campo passa a ser a ativa do mundo. Sem isto,
		# a criatura que o jogador colocou para segurar o combate voltaria para
		# a reserva sozinha assim que o overlay fechasse.
		_roster.absorb_party(fought.player_party, fought.player_active_index)
		captured_hp = fought.enemy.hp

	var layer := get_node_or_null("DuelLayer")
	if layer:
		layer.queue_free()
	_duel = null

	# Vitória → sai do mapa com respawn agendado.
	# Captura → sai do mapa SEM respawn; código entra no time do jogador.
	# Derrota/fuga → criatura permanece no mapa para poder ser reengajada.
	if _engaged_actor and is_instance_valid(_engaged_actor):
		if outcome == Battle.Outcome.PLAYER_WON:
			_spawner.remove_actor(_engaged_actor)
		elif outcome == Battle.Outcome.CAPTURED:
			# Entra com o HP com que foi capturada — enfraquecer para capturar
			# tem preço, e ele é pago depois, esperando ela se recuperar.
			# Time cheio: a criatura não some do mapa. Engolir a captura em
			# silêncio seria perder o bicho e a batalha juntos.
			if _roster.add(_engaged_actor.creature_code, captured_hp):
				_spawner.remove_actor(_engaged_actor, false)
			else:
				_engaged_actor.reset_engagement()
				_show_mine_msg("Time cheio (%d/%d) — a captura escapou."
					% [_roster.size(), PlayerRoster.MAX_SLOTS])
		else:
			_engaged_actor.reset_engagement()
	_engaged_actor = null

	if outcome == Battle.Outcome.PLAYER_LOST:
		_show_mine_msg("Seu time caiu. Recuperando %d%% por minuto."
			% int(PlayerRoster.REGEN_FRACTION_PER_MINUTE * 100.0))

	_show_world_hud()
	# `_update_hint` também dispara via `population_changed` do spawner quando
	# a remoção ocorre, mas chamar aqui garante o texto certo mesmo nos
	# desfechos que não mexem na população.
	_update_hint()
