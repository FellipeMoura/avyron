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
var _staging: BattleStaging
var _arenas: Array[ArenaActor] = []
var _engaged_arena: ArenaActor
var _portal_guardian: PortalGuardianActor

## Onde o comerciante fica. Posição de cena, não de bestiário: o catálogo diz
## quem existe e em que mapa, o layout do mundo diz onde. Quando houver
## vilarejo modelado, isto vira um marcador na cena.
const MERCHANT_SPOT := Vector3(6.0, 0.0, -6.0)

## Idem, pro posto do Relicário — depositar/retirar do storage e trocar de
## modelo só funcionam perto daqui (documento `relicario`: "exige estar em
## um ponto fixo"). Mesmo raciocínio de placeholder que o comerciante já é.
const RELIC_STATION_SPOT := Vector3(9.0, 0.0, -6.0)

## Idem, pra arena e pro guardião do portal (documento `glifos-e-portais`).
## Guardião fica mais longe dos outros pontos de interação — ele marca a
## borda do mapa, não um serviço no meio dele.
const ARENA_SPOT := Vector3(-6.0, 0.0, -6.0)
const PORTAL_SPOT := Vector3(-6.0, 0.0, -14.0)

## Conteúdo da arena única desta era: contra quem o jogador luta, em que
## nível, e qual Glifo a vitória concede. Fixo em código pelo mesmo motivo
## de `starter_code` — o catálogo descreve que existe um duelista (`role =
## duelist`), não qual criatura específica ele usa. `CRT-021` (Inostrancevia)
## é `hero`/Theria, um dos predadores de topo já cadastrados — leitura
## natural de "campeão da arena" dentre o elenco existente.
const ARENA_OPPONENT_CODE := "CRT-021"
const ARENA_OPPONENT_LEVEL := 18
const ARENA_GRANTS_GLYPH := "DALETH"

## O que o guardião exige e para onde ele levaria — só a exibição, ver
## `PortalGuardianActor.can_pass()` para a checagem em si.
const PORTAL_REQUIRED_GLYPH := "DALETH"
const PORTAL_DESTINATION_LABEL := "Titanor"

## Sem sistema de aquisição ainda (fora de escopo no handoff de design), todo
## jogador começa equipado com o mesmo modelo. Decisão de design (documento
## `relicario`): o starter é neutro — sem elemento, sem classe, `slotCapacity
## = 2` — só para ensinar captura/gerenciamento antes da primeira
## especialização, que vem depois como recompensa de arena (fora de escopo
## aqui). `_pick_starter_relic` procura por ele no bundle; ver o aviso lá se
## não achar.

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
	_relic = _pick_starter_relic()
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

	_spawn_companion()
	_spawn_merchants()
	_spawn_relic_station()
	_spawn_arenas()
	_spawn_portal_guardian()
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


## Um posto só por mapa, sempre presente — ao contrário do comerciante, não é
## dado do bestiário (não existe `npc_role` pra isso ainda), então não há
## "zero é normal" aqui: sem storage não há como esvaziar slots pra trocar de
## modelo, e essa regra do design doc precisa de um lugar pra valer.
func _spawn_relic_station() -> void:
	_relic_station = RelicStationActor.create(RELIC_STATION_SPOT)
	_relic_station.name = "RelicStation"
	_relic_station.engaged.connect(_on_relic_station_engaged)
	add_child(_relic_station)


## Instancia os duelistas de arena que o bestiário coloca neste mapa
## (`role = duelist`, documento `glifos-e-portais`). Zero é normal, mesmo
## raciocínio de `_spawn_merchants` — hoje só existe um nesta era.
func _spawn_arenas() -> void:
	if _db == null:
		return
	var spot := ARENA_SPOT
	for data in _db.duelists_in_map(map_code):
		var actor := ArenaActor.create(
			data, spot, ARENA_OPPONENT_CODE, ARENA_OPPONENT_LEVEL, ARENA_GRANTS_GLYPH)
		actor.name = "Arena_%s" % str(data.get("code", ""))
		actor.engaged.connect(_on_arena_engaged)
		add_child(actor)
		_arenas.append(actor)
		spot += Vector3(2.5, 0.0, 0.0)


## Um guardião só, sempre presente — igual ao posto do Relicário, não é dado
## do bestiário (sem `npc_role` que sirva ainda). Fixo nesta era: é ele quem
## bloqueia a progressão até Titanor.
func _spawn_portal_guardian() -> void:
	_portal_guardian = PortalGuardianActor.create(
		PORTAL_SPOT, PORTAL_REQUIRED_GLYPH, PORTAL_DESTINATION_LABEL, _progress)
	_portal_guardian.name = "PortalGuardian"
	_portal_guardian.engaged.connect(_on_portal_guardian_engaged)
	add_child(_portal_guardian)


## Procura no bundle um modelo de Relicário neutro — sem `element`, sem
## `class` — para equipar o jogador de saída. `null` sem bestiário.
##
## Hoje **nenhum modelo assim existe no catálogo**: RLC-001/002/003 têm
## elemento e classe fixos (e `slotCapacity = 3`, não 2). Isto não é algo que
## este jogo deva resolver inventando um código local — o bundle exportado é
## a fonte de verdade (ver cabeçalho de `BestiaryData`), e duplicar o modelo
## aqui divergiria dele na primeira reexportação.
##
## O que falta do lado do avyron-bestiary, para desbloquear isto:
##   1. Schema: `relics.elementId`/`relics.classId` hoje são `NOT NULL`
##      (`packages/db/src/schema/relics.ts`) — precisam aceitar ausência,
##      mesmo padrão que `abilities.elementCode` já usa para golpe sem
##      afinidade.
##   2. API: `CreateRelicBodySchema` (`RelicsTypes.ts`) exige
##      `elementCode`/`classCode` como string — precisam virar opcionais.
##   3. Um novo relic model via `POST /relics` + `POST /relic-stats`, com:
##        code, name          — únicos, como qualquer relic
##        elementCode         — ausente (null)
##        classCode           — ausente (null)
##        slotCapacity        — 2
##        baseCaptureRate, captureRatePerLevel, maxLevel
##                            — tuning em aberto, qualquer valor razoável serve
##        combatBuffBase, combatBuffPerLevel
##                            — sem função em combate desde este patch
##                              (`duel_screen.gd` não aplica mais), podem ficar
##                              em 0 ou o default do schema
##   4. `pnpm game:export` para o bundle pegar o modelo novo.
##
## Até isso existir, o jogador entra sem relicário equipado — captura fica
## indisponível (mesmo tratamento que já existe para "nenhum relicario
## equipado" em `DuelScreen._try_capture`), e o aviso abaixo torna o motivo
## visível no log em vez de falhar em silêncio.
func _pick_starter_relic() -> PlayerRelic:
	if _db == null:
		return null
	for code in _db.relic_codes():
		var r := _db.relic(code)
		if BestiaryData.relic_element_code(r) == "" and BestiaryData.relic_class_code(r) == "":
			return PlayerRelic.from_bestiary(_db, code)
	push_warning(
		"WorldRoot: sem relicario neutro (sem elemento/classe) no catalogo — " +
		"o starter precisa ser criado no avyron-bestiary (ver comentario de " +
		"_pick_starter_relic). Jogador comeca sem relicario equipado."
	)
	return null


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
	_roster_window.item_use_requested.connect(use_item_on_slot)
	layer.add_child(_roster_window)

	_set_window = PlayerSetWindow.new()
	_set_window.name = "PlayerSetWindow"
	layer.add_child(_set_window)

	_inventory_panel = InventoryPanel.new()
	_inventory_panel.name = "InventoryPanel"
	layer.add_child(_inventory_panel)
	_inventory.changed.connect(_on_inventory_changed)

	if _db:
		_active_panel.setup(_db, biome_code)
		# A janela precisa da bolsa para listar o que há de cura. A mesma
		# instância, não uma cópia — o que ela desenha tem de ser o que o
		# comerciante acabou de vender.
		_roster_window.setup(_db, _inventory)
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
	_hint.text = "WASD anda · Shift corre · F minera · T time · E set · V bolsa · clique numa criatura para ver, clique de novo para lutar   (%d no mapa)" % count


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
		elif _selected != null:
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
	var hit := _pick_body(screen_pos)

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
	if actor == _selected:
		# Segundo clique na mesma criatura → engate.
		var to_engage := _selected
		_clear_selection()
		to_engage.request_engage()
	else:
		_select(actor)


## Devolve o corpo clicado — criatura, comerciante, posto do relicário, ou
## null. Quem decide o que fazer com ele é `handle_click_at`; misturar as
## duas responsabilidades aqui
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
	if collider is CreatureActor or collider is MerchantActor or collider is RelicStationActor \
			or collider is ArenaActor or collider is PortalGuardianActor:
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


func relic() -> PlayerRelic:
	return _relic


## A encenação do duelo corrente, ou null fora dele. Público para os testes
## headless medirem a convergência sem depender do `_process` do motor.
func staging() -> BattleStaging:
	return _staging


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


## Esconde a HUD de exploração. Sem isto o hint de WASD e os painéis vazam
## atrás do overlay — ruído puro enquanto a atenção está em outra coisa.
func _hide_world_hud() -> void:
	if _hint:
		_hint.visible = false
	if _active_panel:
		_active_panel.visible = false
	if _roster_window:
		_roster_window.close()
	if _set_window:
		_set_window.close()
	if _inventory_panel:
		_inventory_panel.visible = false
	if _mine_label:
		_mine_label.hide()


func _show_world_hud() -> void:
	if _hint:
		_hint.visible = true
	if _active_panel:
		_active_panel.visible = true
	# Respeita a escolha do jogador (`V`) — reabrir a loja/posto não deve
	# trazer a bolsa de volta se ele pediu pra escondê-la.
	if _inventory_panel:
		_inventory_panel.visible = not _inventory_hidden


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
	# A mesma instância: capturar sobe o nível do relicário aqui embaixo, e a
	# tela de duelo precisa da taxa/elemento/classe atuais pra montar a ação.
	_duel.relic = _relic
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

	_begin_staging(actor)

	if _camera:
		_camera.enter_battle()
	# Congela exploração e IA; o overlay segue processando.
	get_tree().paused = true


## Engata o duelo de arena — mesmo corpo de `_on_creature_engaged`, sem as
## partes de spawner selvagem (não há ator para remover/repor no mapa: o
## duelista continua lá depois, refazer a arena é permitido). `is_wild =
## false` desliga captura em `Battle` (`battle.gd:_do_capture`); a vitória é
## lida em `_on_duel_closed`, que concede o Glifo.
func _on_arena_engaged(actor: ArenaActor) -> void:
	if _duel != null:
		return  # já há um combate em curso

	if _roster.alive_count() == 0:
		_clear_selection()
		_show_mine_msg("Nenhuma criatura de pe. Espere se recuperarem.")
		return

	_engaged_arena = actor
	_clear_selection()
	_hide_world_hud()

	var packed: PackedScene = load(DUEL_SCENE)
	_duel = packed.instantiate() as DuelScreen
	_duel.player_code = _roster.active()
	_duel.player_party = _roster.to_party()
	_duel.player_active_index = _roster.active_index()
	_duel.relic = _relic
	_duel.enemy_code = actor.opponent_code
	_duel.duel_level = actor.opponent_level
	_duel.is_wild = false
	_duel.closed.connect(_on_duel_closed)

	var layer := CanvasLayer.new()
	layer.name = "DuelLayer"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(_duel)
	add_child(layer)

	# Sem criatura selvagem para encenar contra — a arena não tem o
	# equivalente a `CreatureActor` no mundo, só o duelista parado. A
	# encenação segue com o par jogador/companheira igual, sem lado inimigo.
	_end_staging()

	if _camera:
		_camera.enter_battle()
	get_tree().paused = true


## Fala com o guardião do portal. Sem `can_pass()`, barra e explica o porquê;
## com, reconhece o Glifo — mas nunca troca de cena: não existe conteúdo de
## Titanor pra ir (documento `glifos-e-portais`, "fora de escopo").
func _on_portal_guardian_engaged(actor: PortalGuardianActor) -> void:
	if actor.can_pass():
		_show_mine_msg("O Guardiao reconhece o Glifo e se afasta — mas %s ainda nao existe neste build."
			% actor.destination_label)
	else:
		_show_mine_msg("O Guardiao barra a passagem: prove que esta pronto na arena.")


## Põe a companheira e a criatura selvagem frente a frente enquanto o duelo
## dura. Quem luta pelo jogador é a **ativa**, então é o corpo dela que encena —
## o domador fica onde estava, assistindo.
##
## Silenciosamente não faz nada quando falta um dos dois lados: em playtest de
## cena solta pode não haver companheira, e um duelo sem encenação continua
## sendo um duelo.
func _begin_staging(actor: CreatureActor) -> void:
	_end_staging()
	if _companion == null or not is_instance_valid(_companion) or actor == null:
		return
	_staging = BattleStaging.create(
		_companion, _companion.size_meters, actor, actor.size_meters)
	# O domador entra na composição atrás da própria criatura. Sem jogador a
	# encenação segue valendo para o par que luta.
	if _player:
		_staging.set_trainer(_player, _player_radius())
	add_child(_staging)


## Raio do corpo do jogador, lido da cena. Vem da forma de colisão, e não de
## uma constante aqui, porque a cápsula do `Player` vive em `main.tscn` — duas
## medidas do mesmo corpo discordariam no dia em que uma delas mudasse.
##
## O padrão só entra se a cena não tiver forma de cápsula, o que hoje não
## acontece: é rede para playtest de cena montada à mão.
func _player_radius(default_radius: float = 0.35) -> float:
	var collision := _player.get_node_or_null("Collision") as CollisionShape3D
	if collision and collision.shape is CapsuleShape3D:
		return (collision.shape as CapsuleShape3D).radius
	return default_radius


func _end_staging() -> void:
	if _staging and is_instance_valid(_staging):
		_staging.queue_free()
	_staging = null


func _on_duel_closed(outcome: int) -> void:
	get_tree().paused = false
	# A encenação sai antes de o mundo voltar a andar. Deixá-la viva um quadro
	# a mais poria a perseguição da criatura e a trilha da companheira
	# disputando o mesmo `global_position` com ela.
	_end_staging()
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
			# Uma mensagem só: `_show_mine_msg` substitui a anterior na hora, e
			# perder o aviso de drop pro aviso de XP (ou vice-versa) no mesmo
			# quadro seria pior que juntar os dois numa linha.
			var parts: Array[String] = []
			var drop_msg := _grant_drops(fought)
			if drop_msg != "":
				parts.append(drop_msg)
			var xp_msg := _grant_creature_xp(fought)
			if xp_msg != "":
				parts.append(xp_msg)
			if not parts.is_empty():
				_show_mine_msg("   ·   ".join(parts))
		elif outcome == Battle.Outcome.CAPTURED:
			# Entra com o HP com que foi capturada — enfraquecer para capturar
			# tem preço, e ele é pago depois, esperando ela se recuperar.
			# Time cheio: a criatura não some do mapa. Engolir a captura em
			# silêncio seria perder o bicho e a batalha juntos.
			var captured_level := fought.enemy.level if fought else -1
			if _roster.add(_engaged_actor.creature_code, captured_hp, captured_level):
				_spawner.remove_actor(_engaged_actor, false)
				_grant_capture_xp()
			else:
				_engaged_actor.reset_engagement()
				_show_mine_msg("Time cheio (%d/%d) — a captura escapou."
					% [_roster.size(), _roster.capacity()])
		else:
			_engaged_actor.reset_engagement()
	elif _engaged_arena:
		# Sem ator de spawner para repor/remover — o duelista fica no mapa
		# vencendo ou perdendo. `grant_glyph` devolve `false` num refight
		# depois de já ter o Glifo, então isto não reanuncia nem duplica.
		if outcome == Battle.Outcome.PLAYER_WON and _progress:
			if _progress.grant_glyph(_engaged_arena.grants_glyph):
				_show_mine_msg("Glifo %s obtido." % _engaged_arena.grants_glyph.capitalize())
	_engaged_actor = null
	_engaged_arena = null

	if outcome == Battle.Outcome.PLAYER_LOST:
		_show_mine_msg("Seu time caiu. Recuperando %d%% por minuto."
			% int(PlayerRoster.REGEN_FRACTION_PER_MINUTE * 100.0))

	_show_world_hud()
	# `_update_hint` também dispara via `population_changed` do spawner quando
	# a remoção ocorre, mas chamar aqui garante o texto certo mesmo nos
	# desfechos que não mexem na população.
	_update_hint()


## Sorteia o que a criatura derrotada largou e joga na bolsa. Chamado só em
## `PLAYER_WON` — capturar não mata a criatura, então não há o que largar.
## Devolve a mensagem pronta, ou "" sem drop nenhum — quem chama decide como
## (ou se) mostrar, porque `PLAYER_WON` também concede XP no mesmo instante.
func _grant_drops(fought: Battle) -> String:
	if fought == null or _db == null or _inventory == null:
		return ""
	var won := LootTable.roll(_mine_rng, _db.creature_drops(fought.enemy.code))
	if won.is_empty():
		return ""
	for item_code in won:
		_inventory.add(item_code)
	var names: Array[String] = []
	for item_code in won:
		names.append(_db.item_name(item_code))
	return "Encontrado: %s" % ", ".join(names)


## Concede XP de vitória a todas as criaturas que participaram da luta — não
## só quem terminou nela em campo (ver `Battle.xp_participants`). O total é
## calculado do jeito de sempre (`xpYield * nível / yieldDivisor`) e é um pool
## fixo: trocar mais criaturas na luta não cria XP, só muda entre quem ele se
## reparte (`ProgressionMath.distribute_xp`). Cada participante passa
## individualmente pela própria exigência dupla de sempre — XP cheio e
## material da própria classe — em `grant_xp_at`. Devolve a mensagem pronta
## com uma linha por criatura, ou "" se não houve XP a conceder.
func _grant_creature_xp(fought: Battle) -> String:
	if fought == null or _db == null or _inventory == null:
		return ""
	var xp_rules: Dictionary = _db.progression_rules().get("xp", {})
	if xp_rules.is_empty():
		return ""
	var divisor := float(xp_rules.get("yieldDivisor", 0.0))
	if divisor <= 0.0:
		return ""
	var gained := int(floor(float(fought.enemy.xp_yield) * float(fought.enemy.level) / divisor))
	if gained <= 0:
		return ""

	var participants := fought.xp_participants()
	if participants.is_empty():
		# Não deveria acontecer numa vitória — alguém teve de agir para vencer
		# — mas cai para quem terminou em campo em vez de perder o XP da luta
		# em silêncio.
		participants = [{"index": fought.player_active_index, "contribution": 0}]

	var contributions: Array = []
	for p in participants:
		contributions.append(int(p["contribution"]))
	var shares := ProgressionMath.distribute_xp(gained, contributions)

	var lines: Array[String] = []
	for i in participants.size():
		var idx := int(participants[i]["index"])
		var amount := int(shares[i])
		if amount <= 0:
			continue
		var result := _roster.grant_xp_at(idx, amount, _inventory)
		var name := _creature_name(_roster.code_at(idx))
		var line := "%s +%d XP" % [name, amount]
		if result["leveled_up"]:
			line += " (subiu para o nivel %d!)" % int(result["new_level"])
		elif result["waiting_material"]:
			var cls := str(_db.creature(_roster.code_at(idx)).get("class", ""))
			line += " (XP cheio, falta %s)" % _db.item_name(_db.class_material_item(cls))
		lines.append(line)

	return "  ·  ".join(lines)


## Concede XP de captura ao relicário equipado e sobe de nível se der — precisa
## de XP cheio e do material da própria classe do relicário disponível na
## bolsa (documento `relicario`). Chamado só depois que a captura já entrou
## no time, nunca numa captura que escapou por time cheio.
func _grant_capture_xp() -> void:
	if _relic == null or _db == null or _inventory == null:
		return
	var result := _relic.grant_capture_xp(_db, _inventory)
	if result["leveled_up"]:
		_show_mine_msg("%s subiu para o nivel %d!"
			% [_relic.display_name(_db), int(result["new_level"])])
	elif result["waiting_material"]:
		_show_mine_msg("%s: XP cheio, falta %s."
			% [_relic.display_name(_db), _db.item_name(_relic.material_item_code(_db))])
