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
## Ao engatar, `BattleStaging` põe a companheira e a selvagem frente a frente,
## à distância de duelo. Sem isso o combate abriria com o par exatamente como a
## exploração o deixou — de costas, colados ou a oito metros — e o overlay
## narraria um confronto que a imagem não mostra.
##
## ## A criatura ativa amarra os três sistemas
##
## Quem está à frente no `PlayerRoster` é a mesma criatura em toda parte: anda
## ao lado do jogador, entra no duelo, e — pela **classe** dela — decide o que
## a mineração produz e em que ritmo. Trocar a ativa pela janela do time (`T`)
## não é ajuste de menu: muda o que sai do chão no próximo `F`.

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
## Espelha o duelo aberto em `_encounter`. Existe como campo próprio (em vez
## de só `_encounter.is_duel_open()`) porque os testes headless leem
## `_world.get("_duel")` por reflexão — ver o comentário de
## `EncounterDirector.on_duel_changed`.
var _duel: DuelScreen
var _encounter: EncounterDirector
var _selection: WorldSelection
var _info: CreatureInfoPanel
var _hint: Label
var _db: BestiaryData
var _progress: PlayerProgress
var _companion: CompanionActor
var _roster: PlayerRoster
var _active_panel: ActiveCreaturePanel
var _roster_window: RosterWindow
var _set_window: PlayerSetWindow
var _inventory: PlayerInventory
var _inventory_panel: InventoryPanel
## Escolha do jogador (tecla `V`), não estado de tela. `_show_world_hud` —
## chamado ao fechar loja/posto/duelo — respeita isto em vez de sempre
## reexibir a bolsa, senão "esconder" duraria só até a próxima negociação.
var _inventory_hidden := false
var _relic: PlayerRelic
var _relic_station: RelicStationActor
var _relic_screen: RelicStationScreen
var _mine_rng := RandomNumberGenerator.new()
var _mine_cooldown := 0.0
var _mine_label: Label
var _merchants: Array[MerchantActor] = []
var _shop: MerchantScreen
var _arenas: Array[ArenaActor] = []
var _portal_guardian: PortalGuardianActor

## Posições dos pontos de interesse fixos (comerciante, posto do Relicário,
## arena, guardião do portal), o conteúdo da arena e o requisito do guardião
## agora vivem em `WorldPopulator`, que é quem os usa para instanciar.
##
## Sem sistema de aquisição ainda (fora de escopo no handoff de design), todo
## jogador começa equipado com o mesmo modelo. Decisão de design (documento
## `relicario`): o starter é neutro — sem elemento, sem classe, `slotCapacity
## = 2` — só para ensinar captura/gerenciamento antes da primeira
## especialização, que vem depois como recompensa de arena (fora de escopo
## aqui). `WorldPopulator.pick_starter_relic` procura por ele no bundle; ver
## o aviso lá se não achar.

## Segundos entre minerações consecutivas, antes do perfil de trabalho da
## classe ativa. Theria (×1.1) espera menos, Draconis (×0.9) espera mais.
const MINE_COOLDOWN_SEC := 3.0


func _ready() -> void:
	_camera = get_node_or_null("IsoCamera") as IsoCamera
	_player = get_node_or_null("Player")
	_db = get_node_or_null("/root/Bestiary") as BestiaryData
	# Mesmo padrão do Bestiary: nunca referenciar o autoload pelo identificador
	# global bare (`Progress.foo()`) — scripts carregados fora do boot padrão
	# de cena (como os testes headless que fazem `load()` direto) não
	# resolvem esse identificador, e a falha é erro de compilação, não de
	# runtime.
	_progress = get_node_or_null("/root/Progress") as PlayerProgress

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

	# Sem aquisição ainda, todo jogador entra com o mesmo relicário — mas a
	# capacidade do time já reflete o `slotCapacity` dele desde o início.
	_relic = WorldPopulator.pick_starter_relic(_db)
	if _relic:
		_roster.set_capacity(_relic.slot_capacity(_db))

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

	# O que existe neste mapa e onde — comerciante, posto, arena, guardião e
	# companheira não têm estado que sobreviva além do povoamento em si, por
	# isso vivem em `WorldPopulator` como funções estáticas em vez de métodos
	# daqui. A conexão do sinal `engaged` continua sendo decisão de WorldRoot:
	# quem povoa não é quem decide o que acontece ao interagir.
	_companion = WorldPopulator.spawn_companion(self, _db, _roster, _player)
	_merchants = WorldPopulator.spawn_merchants(self, _db, map_code, _on_merchant_engaged)
	_relic_station = WorldPopulator.spawn_relic_station(self, _on_relic_station_engaged)
	_arenas = WorldPopulator.spawn_arenas(self, _db, map_code, _on_arena_engaged)
	_portal_guardian = WorldPopulator.spawn_portal_guardian(
		self, _progress, _on_portal_guardian_engaged)

	# Ciclo de vida do duelo — engate, encenação, fechamento, drop/XP/glifo —
	# vive em `EncounterDirector`. `_duel` continua espelhado aqui via
	# `on_duel_changed` só para os testes que leem o campo por reflexão.
	_encounter = EncounterDirector.new()
	_encounter.setup(
		self, _camera, _spawner, _roster, _inventory, _companion, _player, _progress, _db,
		_mine_rng, _show_mine_msg, _hide_world_hud, _show_world_hud, _clear_selection,
		_update_hint, func(d: DuelScreen): _duel = d)

	_build_hud()

	# Depende de `_info`, que só existe depois de `_build_hud`.
	_selection = WorldSelection.new()
	_selection.setup(self, _camera, _player, _info, _db, encounter_level)

	_update_hint()


func _process(delta: float) -> void:
	if _mine_cooldown > 0.0:
		_mine_cooldown = maxf(0.0, _mine_cooldown - delta)

	# O time se recupera com o tempo de mapa. Não precisa de trava para não
	# curar durante o combate: o mundo fica pausado, e um nó pausado não
	# processa. É a mesma razão de a câmera precisar de PROCESS_MODE_ALWAYS
	# logo acima — aqui o comportamento padrão é justamente o desejado.
	if _roster:
		_roster.regenerate(delta)

	if _selection:
		_selection.update()


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	var panels := WorldHud.build(
		self, _db, biome_code, _inventory, activate_slot, use_item_on_slot, _on_inventory_changed)
	_hint = panels.hint
	_info = panels.info
	_active_panel = panels.active_panel
	_roster_window = panels.roster_window
	_set_window = panels.set_window
	_inventory_panel = panels.inventory_panel
	_mine_label = panels.mine_label

	# Conectado e disparado só depois de guardar os painéis acima: o handler
	# lê `_active_panel`, e chamá-lo antes da atribuição refrescaria um campo
	# ainda nulo — o painel "criatura ativa" nascia em branco até o próximo
	# evento de time (captura, troca).
	_roster.changed.connect(_on_roster_changed)
	_on_roster_changed()


func _update_hint() -> void:
	var count := _spawner.actors().size() if _spawner else 0
	WorldHud.update_hint(_hint, count)


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
	elif keycode == KEY_E and not _roster_open():
		toggle_set_window()
	elif keycode == KEY_V:
		toggle_inventory_panel()
	elif keycode == KEY_ESCAPE:
		# A janela aberta tem prioridade sobre a seleção: `Esc` fecha o que
		# está por cima, que é a leitura que qualquer um espera. Dentro da
		# janela do time ela volta um passo antes de fechar — sair da escolha
		# de item direto para o mapa perderia o contexto de uma tecla só. O
		# set não tem passo intermediário (é só leitura), então fecha direto.
		if _roster_open():
			if not _roster_window.back():
				_roster_window.close()
		elif _set_window != null and _set_window.is_open():
			_set_window.close()
		elif _selection.selected_actor() != null:
			_clear_selection()
		else:
			return
	elif keycode == KEY_I and _roster_open():
		open_item_menu()
	# Limitado pela capacidade atual do time, não por KEY_9 fixo: o rodapé da
	# janela promete "1–N", e uma tecla que aceita mais do que o texto diz é
	# ruído. Ainda clampado a 9 — dígito único, mesmo teto que o comerciante já
	# usa — mesmo que um relicário exótico erga a capacidade além disso.
	elif _roster_open() and keycode >= KEY_1 and keycode < KEY_1 + mini(_roster.capacity(), 9):
		_roster_window.choose_row(keycode - KEY_1)
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
	var hit := _selection.pick_body(screen_pos)

	# Comerciante e criatura respondem ao mesmo gesto, mas não ao mesmo
	# fluxo: criatura tem seleção e segundo clique, comerciante abre direto —
	# não há decisão de "vale a pena entrar?" a ser tomada antes de olhar a
	# vitrine.
	if hit is MerchantActor:
		handle_click_on_merchant(hit as MerchantActor)
		return
	if hit is RelicStationActor:
		handle_click_on_relic_station(hit as RelicStationActor)
		return
	if hit is ArenaActor:
		handle_click_on_arena(hit as ArenaActor)
		return
	if hit is PortalGuardianActor:
		handle_click_on_portal_guardian(hit as PortalGuardianActor)
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


## Abre o posto do relicário, se o jogador estiver perto. Mesmo padrão de
## `handle_click_on_merchant`.
func handle_click_on_relic_station(actor: RelicStationActor) -> void:
	if actor == null or _relic_screen != null or _duel != null or _shop != null:
		return
	if _player and actor.flat_distance_to(_player.global_position) > RelicStationActor.INTERACT_RANGE:
		_show_mine_msg("O posto do relicario esta longe demais.")
		return
	_clear_selection()
	actor.request_engage()


## Engata o duelo de arena, se o jogador estiver perto. Mesmo padrão de
## `handle_click_on_merchant`.
func handle_click_on_arena(actor: ArenaActor) -> void:
	if actor == null or _duel != null or _shop != null:
		return
	if _player and actor.flat_distance_to(_player.global_position) > ArenaActor.INTERACT_RANGE:
		_show_mine_msg("%s esta longe demais." % actor.display_name)
		return
	_clear_selection()
	actor.request_engage()


## Fala com o guardião do portal, se o jogador estiver perto. Mesmo padrão de
## `handle_click_on_merchant`.
func handle_click_on_portal_guardian(actor: PortalGuardianActor) -> void:
	if actor == null or _duel != null or _shop != null:
		return
	if _player and actor.flat_distance_to(_player.global_position) > PortalGuardianActor.INTERACT_RANGE:
		_show_mine_msg("O guardiao esta longe demais.")
		return
	_clear_selection()
	actor.request_engage()


func handle_click_on(actor: CreatureActor) -> void:
	if actor == null:
		_clear_selection()
		return
	if actor == _selection.selected_actor():
		# Segundo clique na mesma criatura → engate.
		var to_engage := actor
		_clear_selection()
		to_engage.request_engage()
	else:
		_selection.select(actor)


func _clear_selection() -> void:
	_selection.clear()


func selected_actor() -> CreatureActor:
	return _selection.selected_actor()


func roster() -> PlayerRoster:
	return _roster


func inventory() -> PlayerInventory:
	return _inventory


func relic() -> PlayerRelic:
	return _relic


## A encenação do duelo corrente, ou null fora dele. Público para os testes
## headless medirem a convergência sem depender do `_process` do motor.
func staging() -> BattleStaging:
	return _encounter.staging() if _encounter else null


# ---------------------------------------------------------------------------
# time
# ---------------------------------------------------------------------------

## Abre/fecha a janela do time. Público pelo mesmo motivo que `handle_click_on`
## e `trigger_mine`: os testes headless exercitam o fluxo pela API, não
## sintetizando tecla.
func toggle_roster_window() -> void:
	if _roster_window == null or _duel != null:
		return
	# Só uma janela central por vez — abertas juntas se sobrepõem na tela.
	if _set_window != null and _set_window.is_open():
		_set_window.close()
	_roster_window.toggle()
	if _roster_window.is_open():
		# A seleção pendurada atrás da janela não teria como ser cancelada por
		# clique enquanto ela estivesse aberta.
		_clear_selection()
		_refresh_roster_window()


## Abre/fecha a janela do set do jogador (tecla `E`). Público pelo mesmo
## motivo dos outros pontos de entrada: teste headless não sintetiza tecla.
func toggle_set_window() -> void:
	if _set_window == null or _duel != null:
		return
	if _roster_window != null and _roster_window.is_open():
		_roster_window.close()
	_set_window.toggle()
	if _set_window.is_open():
		_clear_selection()
		_set_window.refresh(_db, _relic)


## Esconde/reexibe o painel de bolsa (tecla `V`) — puramente cosmético, não
## desliga mineração nem qualquer outra função da bolsa.
func toggle_inventory_panel() -> void:
	_inventory_hidden = not _inventory_hidden
	if _inventory_panel:
		_inventory_panel.visible = not _inventory_hidden


## Manda a criatura do slot à frente. Ignora silenciosamente slot vazio ou o
## da própria ativa — os dois são cliques sem consequência, não erros.
func activate_slot(index: int) -> void:
	if _roster == null or not _roster.set_active(index):
		return
	_show_mine_msg("À frente: %s" % _creature_name(_roster.active()))


## Abre a escolha de item de cura dentro da janela do time. Público pela mesma
## razão dos outros pontos de entrada: teste headless não sintetiza tecla.
##
## A recusa é falada. Uma tecla que não faz nada quando a bolsa está vazia é
## indistinguível de uma tecla quebrada, e o jogador testaria as duas hipóteses
## antes de concluir que precisa comprar emplastro.
func open_item_menu() -> void:
	if _roster_window == null or not _roster_open():
		return
	if not _roster_window.open_item_mode():
		_show_mine_msg("Nenhum item de cura na bolsa.")


## Usa um item de cura numa criatura do time. É o dono da bolsa **e** do time
## que faz as duas metades, na ordem em que uma depende da outra: mede a cura,
## recusa se ela for nula, consome, aplica.
##
## Consumir por último importa porque a cura é determinística — gastar antes
## de medir o efeito arriscaria perder óbolos por um clique sem efeito nenhum.
func use_item_on_slot(index: int, item_code: String) -> void:
	if _roster == null or _inventory == null or _db == null or item_code == "":
		return
	if index < 0 or index >= _roster.size():
		return

	var effect := _db.item_effect_code(item_code)
	if not ItemEffects.is_heal(effect):
		return
	if not _inventory.has(item_code):
		_show_mine_msg("Voce nao tem %s." % _db.item_name(item_code))
		return

	var amount := ItemEffects.heal_amount(
		effect, _db.item_effect_value(item_code), _roster.max_hp_at(index))
	if _roster.missing_hp_at(index) <= 0 or amount <= 0:
		_show_mine_msg("%s nao tem o que curar." % _creature_name(_roster.code_at(index)))
		return

	if not _inventory.remove(item_code):
		return
	var healed := _roster.heal_at(index, amount)
	_show_mine_msg("%s: %s recuperou %d de HP."
		% [_db.item_name(item_code), _creature_name(_roster.code_at(index)), healed])


## Reconstrói tudo que depende de quem está à frente. É o único ponto que sabe
## que trocar a ativa mexe em três coisas — companheira, painel e janela.
func _on_roster_changed() -> void:
	var active := _roster.active()

	if _companion and is_instance_valid(_companion) and _db and active != "" \
			and _companion.creature_code != active:
		_companion.set_creature(_db, active)

	if _active_panel:
		var i := _roster.active_index()
		_active_panel.refresh(active, _roster.level_at(i), _roster.size(), _roster.capacity(),
			_roster.hp_at(i), _roster.max_hp_at(i))
	_refresh_roster_window()


func _refresh_roster_window() -> void:
	if _roster_window and _roster_window.is_open():
		_roster_window.refresh(_roster)


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
	WorldHud.show_message(_mine_label, self, text)


func _on_inventory_changed() -> void:
	if _inventory_panel:
		_inventory_panel.refresh(_inventory.entries(), _inventory.currency)
	# A janela do time lista quantidade de item e some com a lista quando a
	# última cura acaba. Sem isto, comprar emplastro com a janela aberta a
	# deixaria dizendo que a bolsa está vazia.
	_refresh_roster_window()


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


func _on_relic_station_engaged(actor: RelicStationActor) -> void:
	if _relic_screen != null or _duel != null or _shop != null:
		return

	_hide_world_hud()

	_relic_screen = RelicStationScreen.new()
	_relic_screen.name = "RelicStationScreen"
	_relic_screen.closed.connect(_on_relic_screen_closed)
	# A troca de modelo acontece dentro da tela (novo `PlayerRelic`, própria
	# capacidade) — o mundo só precisa saber qual passou a valer, pra montar
	# o próximo duelo com ele.
	_relic_screen.relic_swapped.connect(func(new_relic: PlayerRelic): _relic = new_relic)

	var layer := CanvasLayer.new()
	layer.name = "RelicStationLayer"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(_relic_screen)
	add_child(layer)

	_relic_screen.setup(_db, _roster, _relic)
	get_tree().paused = true


func _on_relic_screen_closed() -> void:
	get_tree().paused = false
	var layer := get_node_or_null("RelicStationLayer")
	if layer:
		layer.queue_free()
	_relic_screen = null
	_show_world_hud()


func _hide_world_hud() -> void:
	WorldHud.hide_world(_hint, _active_panel, _roster_window, _set_window, _inventory_panel, _mine_label)


func _show_world_hud() -> void:
	WorldHud.show_world(_hint, _active_panel, _inventory_panel, _inventory_hidden)


# ---------------------------------------------------------------------------
# encontro
# ---------------------------------------------------------------------------

## Delega para `EncounterDirector.engage_wild` — o ciclo de vida do duelo
## (encenação, fechamento, drop/XP/glifo) vive lá.
func _on_creature_engaged(actor: CreatureActor) -> void:
	_encounter.engage_wild(actor, _relic, encounter_level)


## Delega para `EncounterDirector.engage_arena` — mesmo motivo.
func _on_arena_engaged(actor: ArenaActor) -> void:
	_encounter.engage_arena(actor, _relic)


## Fala com o guardião do portal. Sem `can_pass()`, barra e explica o porquê;
## com, reconhece o Glifo — mas nunca troca de cena: não existe conteúdo de
## Titanor pra ir (documento `glifos-e-portais`, "fora de escopo"). Fica aqui
## e não em `EncounterDirector` porque nunca abre duelo — é conversa, não
## combate.
func _on_portal_guardian_engaged(actor: PortalGuardianActor) -> void:
	if actor.can_pass():
		_show_mine_msg("O Guardiao reconhece o Glifo e se afasta — mas %s ainda nao existe neste build."
			% actor.destination_label)
	else:
		_show_mine_msg("O Guardiao barra a passagem: prove que esta pronto na arena.")
