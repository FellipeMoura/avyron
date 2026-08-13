class_name WorldHud
extends RefCounted

## Construção da HUD de exploração e as operações mecânicas sobre ela:
## hint de teclas, mensagem transitória (`mine_label`, usado por toda ação
## temporária — minerar, curar, trocar ativa — não só mineração) e o par
## esconder/reexibir que loja, posto do Relicário e duelo chamam ao abrir e
## fechar.
##
## `RefCounted` com métodos `static`, sem estado: os nós continuam
## pertencendo a `WorldRoot` (é ele quem os usa em mais lugares — input,
## troca de time, cura), então cada função recebe as referências que precisa
## em vez de guardá-las aqui. Só `build()` cria nó; o resto é leitura e
## `.visible`.

## Pacote dos sete nós que `build()` monta, para `WorldRoot` guardar cada um
## no próprio campo — os campos continuam lá porque são usados em métodos
## fora do escopo desta extração (input, janela do time, cura).
class Panels:
	var hint: Label
	var info: CreatureInfoPanel
	var active_panel: ActiveCreaturePanel
	var roster_window: RosterWindow
	var set_window: PlayerSetWindow
	var inventory_panel: InventoryPanel
	var mine_label: Label


## Monta a `CanvasLayer "HudLayer"` com os sete elementos da HUD de
## exploração. `on_activate`/`on_use_item` são os callbacks de
## `RosterWindow` (tocam time e bolsa, não HUD); `on_inventory_changed` é o
## handler que mantém bolsa e janela do time em dia — continua vivendo em
## `WorldRoot`.
##
## Não conecta nem chama `roster.changed`/`on_roster_changed`: isso fica por
## conta de quem chama, depois de guardar os painéis nos próprios campos —
## chamar aqui dentro refrescaria `_active_panel` antes de `WorldRoot`
## atribuí-lo, e o primeiro refresh cairia no vazio (foi exatamente o que
## aconteceu: "criatura ativa" nascia em branco até o próximo evento de
## time).
static func build(
	parent: Node3D, db: BestiaryData, biome_code: String, inventory: PlayerInventory,
	on_activate: Callable, on_use_item: Callable, on_inventory_changed: Callable
) -> Panels:
	var panels := Panels.new()

	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	parent.add_child(layer)

	panels.hint = Label.new()
	panels.hint.add_theme_color_override("font_color", Color("#6B7280"))
	panels.hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panels.hint.offset_left = 20
	panels.hint.offset_top = -44
	panels.hint.offset_bottom = -16
	panels.hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panels.hint)

	panels.info = CreatureInfoPanel.new()
	panels.info.name = "CreatureInfoPanel"
	layer.add_child(panels.info)

	panels.active_panel = ActiveCreaturePanel.new()
	panels.active_panel.name = "ActiveCreaturePanel"
	layer.add_child(panels.active_panel)

	panels.roster_window = RosterWindow.new()
	panels.roster_window.name = "RosterWindow"
	panels.roster_window.activate_requested.connect(on_activate)
	panels.roster_window.item_use_requested.connect(on_use_item)
	layer.add_child(panels.roster_window)

	panels.set_window = PlayerSetWindow.new()
	panels.set_window.name = "PlayerSetWindow"
	layer.add_child(panels.set_window)

	panels.inventory_panel = InventoryPanel.new()
	panels.inventory_panel.name = "InventoryPanel"
	layer.add_child(panels.inventory_panel)
	inventory.changed.connect(on_inventory_changed)

	if db:
		panels.active_panel.setup(db, biome_code)
		# A janela precisa da bolsa para listar o que há de cura. A mesma
		# instância, não uma cópia — o que ela desenha tem de ser o que o
		# comerciante acabou de vender.
		panels.roster_window.setup(db, inventory)
		panels.inventory_panel.setup(db)

	panels.mine_label = Label.new()
	panels.mine_label.name = "MineLabel"
	panels.mine_label.add_theme_color_override("font_color", Color("#7A8C6B"))
	panels.mine_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panels.mine_label.offset_left = 20
	panels.mine_label.offset_top = -68
	panels.mine_label.offset_bottom = -48
	panels.mine_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panels.mine_label.hide()
	layer.add_child(panels.mine_label)

	return panels


static func update_hint(hint: Label, actor_count: int) -> void:
	if hint == null:
		return
	hint.text = ("WASD anda · F minera · T time · E set · V bolsa · " +
		"clique numa criatura para ver, clique de novo para lutar   (%d no mapa)") % actor_count


## Esconde a HUD de exploração. Sem isto o hint de WASD e os painéis vazam
## atrás do overlay — ruído puro enquanto a atenção está em outra coisa.
static func hide_world(
	hint: Label, active_panel: ActiveCreaturePanel, roster_window: RosterWindow,
	set_window: PlayerSetWindow, inventory_panel: InventoryPanel, mine_label: Label
) -> void:
	if hint:
		hint.visible = false
	if active_panel:
		active_panel.visible = false
	if roster_window:
		roster_window.close()
	if set_window:
		set_window.close()
	if inventory_panel:
		inventory_panel.visible = false
	if mine_label:
		mine_label.hide()


static func show_world(
	hint: Label, active_panel: ActiveCreaturePanel, inventory_panel: InventoryPanel,
	inventory_hidden: bool
) -> void:
	if hint:
		hint.visible = true
	if active_panel:
		active_panel.visible = true
	# Respeita a escolha do jogador (`V`) — reabrir a loja/posto não deve
	# trazer a bolsa de volta se ele pediu pra escondê-la.
	if inventory_panel:
		inventory_panel.visible = not inventory_hidden


## Mensagem transitória no canto inferior esquerdo — some sozinha em 2s.
## `owner` só empresta `create_tween()`; nenhum estado fica aqui.
static func show_message(mine_label: Label, owner: Node, text: String) -> void:
	if mine_label == null:
		return
	mine_label.text = text
	mine_label.show()
	# Remove a mensagem automaticamente num único Tween — cancela o anterior
	# se uma segunda mensagem chegar antes dos 2 s expirarem.
	var t := owner.create_tween()
	t.tween_interval(2.0)
	t.tween_callback(mine_label.hide)
