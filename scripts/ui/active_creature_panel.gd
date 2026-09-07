class_name ActiveCreaturePanel
extends Control

## A criatura ativa, no canto superior direito. Substitui o antigo painel de
## time, que mostrava um slot de captura e nada mais.
##
## Mostra o que muda de decisão enquanto se explora: quem está à frente, o que
## ela aguenta, e — o motivo de o painel existir — **o que ela minera**. A
## classe da ativa entra na fórmula da picareta, então o perfil de trabalho é
## informação de mapa, não de menu.
##
## Ao contrário do painel de identificação da criatura selvagem, aqui os stats
## aparecem: esconder número da própria criatura não cria tensão nenhuma, só
## obriga o jogador a abrir a janela do time para uma conta que ele deveria ter
## na cara.
##
## Reconstruído sobre os assets de `res://png/`: moldura, retrato, barra de HP
## e selo de nível viraram peças de imagem próprias em vez de linhas de texto.
## A base é `Control` (não mais `PanelContainer`) porque cada peça ocupa um
## retângulo diferente do canvas 1536×320 — um `PanelContainer` esticaria
## qualquer filho direto para o retângulo inteiro, que era exatamente o que a
## versão só-texto explorava com o `HBoxContainer` único.

signal inventory_requested
signal equipment_requested
signal relicary_requested

const COL_BONE  := "#F2EDE0"
const COL_MOSS  := "#7A8C6B"
const COL_SLATE := "#6B7280"
const COL_EMBER := "#C6552F"

## Mesmo diretório espelhado que `CreatureInfoPanel` consulta — ver o
## comentário lá para o porquê do `ResourceLoader.exists` em vez de erro.
const CARDS_DIR := "res://cards/"

const PANEL_DIR    := "res://png/panel/"
const PORTRAIT_DIR := "res://png/portraits/"
const STATUS_DIR   := "res://png/status/"
const BUTTONS_DIR  := "res://png/buttons/"
const CIRCLE_SHADER_PATH := "res://shaders/circular_portrait_mask.gdshader"

## Códigos do bestiário, não nomes: nomes são texto de apresentação (e o
## próprio bundle já avisa em `glyph_name` que a primeira leva de nomes é
## provisória), enquanto `CLS-00x`/`ELE-00x` são o identificador estável que
## sobrevive a uma renomeação. Ver `_warn_unknown` para o caso de um código
## que o bundle traga e este mapa ainda não conheça.
const CLASS_FRAME_BY_CODE := {
	"CLS-001": PORTRAIT_DIR + "portrait_class_arambi.png",
	"CLS-002": PORTRAIT_DIR + "portrait_class_kaira.png",
	"CLS-003": PORTRAIT_DIR + "portrait_class_yaruki.png",
	"CLS-004": PORTRAIT_DIR + "portrait_class_ambua.png",
	"CLS-005": PORTRAIT_DIR + "portrait_class_toruma.png",
}
const ELEMENT_RING_BY_CODE := {
	"ELE-001": PORTRAIT_DIR + "portrait_element_fire.png",
	"ELE-002": PORTRAIT_DIR + "portrait_element_water.png",
	"ELE-003": PORTRAIT_DIR + "portrait_element_nature.png",
	"ELE-004": PORTRAIT_DIR + "portrait_element_earth.png",
	"ELE-005": PORTRAIT_DIR + "portrait_element_electric.png",
}

## Canvas de referência dos assets (`png/panel/*.png` são todos 1536×320) e a
## largura final exibida — o resto do arquivo é medido neste espaço e um único
## `scale` no nó "Canvas" (ver `_ready`) escala tudo de uma vez, sem esticar
## nenhum ornamento fora de proporção.
const BASE_SIZE := Vector2(1536, 320)
const DISPLAY_WIDTH := 640.0

## Retângulos medidos direto nos PNGs (script de sondagem em cima do canal
## alfa/luminância de cada arquivo, não a olho): o retrato bate exatamente na
## referência do briefing (centro ~250×160, 280×280); os demais — selo, barra
## de HP e os três encaixes de botão — vieram da mesma sondagem sobre
## `active_creature_panel_background.png`/`panel_alignment_qa.png`.
const RECT_FULL     := Rect2(0, 0, 1536, 320)
const RECT_PORTRAIT := Rect2(110, 20, 280, 280)
## Abertura circular do retrato, local à `PortraitArea`: menor dos dois furos
## (moldura de classe ~688px de diâmetro, anel elemental ~538px, ambos no
## canvas 1024×1024) — o anel elemental é quem por cima decide até onde a
## criatura aparece, então é a referência do recorte.
const RECT_PORTRAIT_CLIP := Rect2(66, 66, 148, 148)
const RECT_LEVEL  := Rect2(430, 140, 96, 96)
const RECT_HEALTH := Rect2(540, 100, 416, 104)
## Canal interno da moldura de HP como FRAÇÃO do canvas 1024×256 do briefing
## (`x=188/1024, y=95/256, w=655/1024, h=84/256`) — `_build_health_bar`
## multiplica isto por `RECT_HEALTH.size` em vez de guardar um retângulo em
## pixels já resolvido, pra continuar correto se `RECT_HEALTH` mudar de nome
## sem ninguém lembrar de recalcular um segundo número à mão.
const HP_CHANNEL_NORM := Rect2(0.18359375, 0.37109375, 0.6396484375, 0.328125)
## Zoom da amostra dentro do círculo do retrato (ver o shader) — não do nó.
const PORTRAIT_ZOOM := 1.1
## Miolo visível dos quatro estados de botão dentro do canvas 512×512 (o
## resto é margem transparente) — sem recortar por aqui, o Godot encolhe o
## quadro INTEIRO pro encaixe e o ícone sobra pequeno, cercado de vão vazio.
const BUTTON_ICON_REGION := Rect2(96, 105, 320, 302)
## As duas faixas escuras que sobram entre a moldura e a barra de HP — medidas
## na tela renderizada, não só no PNG isolado: a aba plana do painel (longe da
## curva do retrato) é mais grossa do que a borda do medalhão do retrato
## sugeria, e um texto que respeitasse só aquela medida vazava por cima da
## aba de verdade.
const RECT_TOP_INFO    := Rect2(430, 62, 520, 36)
## `x` começa depois do selo de nível (que vai até 430+96=526): a versão
## anterior começava em 430, embaixo do próprio selo, e a segunda linha da
## mineração saía parcialmente escondida atrás dele.
const RECT_BOTTOM_INFO := Rect2(540, 208, 420, 46)
const RECT_INVENTORY := Rect2(1024, 98, 118, 118)
const RECT_EQUIPMENT := Rect2(1166, 98, 118, 118)
const RECT_RELICARY  := Rect2(1306, 98, 118, 118)

## Reserva de largura pro `[b]`/padding interno do `RichTextLabel` na hora de
## medir se o nome cabe — `_fit_text` mede a fonte pura, e negrito mais o
## padding do próprio label comem mais do que zero.
const NAME_MARGIN := 40.0

var _db: BestiaryData
var _biome_code := ""
var _warned_codes: Dictionary = {}

var _creature_portrait: TextureRect
var _class_frame: TextureRect
var _element_frame: TextureRect

var _health_bar: Control
var _health_fill: TextureProgressBar
var _health_highlight: TextureProgressBar
var _health_label: Label

var _level_area: Control
var _level_label: Label

var _top_info: RichTextLabel
var _bottom_info: RichTextLabel
## Guardados pra `_fit_text` medir com o MESMO tamanho de fonte que o label
## usa de verdade — os dois só existem depois de `_build_info_labels`.
var _top_info_font_size := 0
var _bottom_info_font_size := 0

var _inventory_button: TextureButton
var _equipment_button: TextureButton
var _relicary_button: TextureButton

## Compensação de fonte: todo texto do painel é filho de "Canvas", que leva o
## `scale` uniforme do conjunto (ver `_ready`) — sem multiplicar o tamanho da
## fonte pelo inverso desse fator, a letra encolheria junto com a arte e um
## `font_size` de 15 acabaria em ~6px de tela.
var _text_scale := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	var scale_factor := DISPLAY_WIDTH / BASE_SIZE.x
	_text_scale = 1.0 / scale_factor
	var display_size := BASE_SIZE * scale_factor
	offset_right  = -16
	offset_left   = offset_right - display_size.x
	offset_top    = 16
	offset_bottom = offset_top + display_size.y
	mouse_filter  = Control.MOUSE_FILTER_IGNORE

	# Tudo abaixo é montado no espaço 1536×320 do briefing; só este nó escala
	# o conjunto pro tamanho final, uma vez, de forma uniforme.
	var canvas := Control.new()
	canvas.name = "Canvas"
	canvas.position = Vector2.ZERO
	canvas.size = BASE_SIZE
	canvas.scale = Vector2(scale_factor, scale_factor)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)

	# Ordem de camadas do briefing: sombra, corpo, backplate, conteúdo
	# dinâmico (retrato/HP/nível), divisor, informações e botões.
	canvas.add_child(_full_texture_rect("PanelShadow", PANEL_DIR + "active_creature_panel_shadow.png"))
	canvas.add_child(_full_texture_rect("PanelBackground", PANEL_DIR + "active_creature_panel_background.png"))
	canvas.add_child(_full_texture_rect("PortraitBackplate", PANEL_DIR + "active_creature_portrait_backplate.png"))

	_build_portrait_area(canvas)
	_build_health_bar(canvas)
	_build_level_area(canvas)

	canvas.add_child(_full_texture_rect("PanelDivider", PANEL_DIR + "active_creature_panel_divider.png"))

	_build_info_labels(canvas)
	_build_actions(canvas)


func _full_texture_rect(node_name: String, path: String) -> TextureRect:
	var t := TextureRect.new()
	t.name = node_name
	t.position = RECT_FULL.position
	t.size = RECT_FULL.size
	t.texture = load(path)
	t.stretch_mode = TextureRect.STRETCH_SCALE
	# Sem isso o tamanho MÍNIMO do TextureRect vira o tamanho em pixels da
	# textura original — como todo asset aqui é maior que o retângulo onde
	# entra, o Godot ignoraria `.size` e infla cada peça pro próprio tamanho
	# do arquivo (ver `CreatureInfoPanel._ready` para o mesmo aviso).
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _build_portrait_area(parent: Control) -> void:
	var area := Control.new()
	area.name = "PortraitArea"
	area.position = RECT_PORTRAIT.position
	area.size = RECT_PORTRAIT.size
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(area)

	_creature_portrait = TextureRect.new()
	_creature_portrait.name = "CreaturePortrait"
	_creature_portrait.position = RECT_PORTRAIT_CLIP.position
	_creature_portrait.size = RECT_PORTRAIT_CLIP.size
	# COVERED (não CENTERED) porque a abertura é circular: sobrar fundo
	# transparente numa quina do quadrado de recorte apareceria como buraco
	# depois do shader cortar o círculo.
	_creature_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_creature_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_creature_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(CIRCLE_SHADER_PATH)
	mat.set_shader_parameter("zoom", PORTRAIT_ZOOM)
	_creature_portrait.material = mat
	_creature_portrait.hide()
	area.add_child(_creature_portrait)

	_class_frame = TextureRect.new()
	_class_frame.name = "ClassFrame"
	_class_frame.position = Vector2.ZERO
	_class_frame.size = RECT_PORTRAIT.size
	_class_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_class_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_class_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_class_frame.hide()
	area.add_child(_class_frame)

	_element_frame = TextureRect.new()
	_element_frame.name = "ElementFrame"
	_element_frame.position = Vector2.ZERO
	_element_frame.size = RECT_PORTRAIT.size
	_element_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_element_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_element_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_element_frame.hide()
	area.add_child(_element_frame)


func _build_health_bar(parent: Control) -> void:
	_health_bar = Control.new()
	_health_bar.name = "HealthBar"
	_health_bar.position = RECT_HEALTH.position
	_health_bar.size = RECT_HEALTH.size
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_health_bar)

	var frame := TextureRect.new()
	frame.name = "HealthFrame"
	frame.position = Vector2.ZERO
	frame.size = RECT_HEALTH.size
	frame.texture = load(STATUS_DIR + "active_creature_hp_frame.png")
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.add_child(frame)

	# Canal derivado do tamanho JÁ EXIBIDO da moldura (não de um segundo
	# retângulo em pixels guardado à parte) — arredondado pro pixel, porque
	# `RECT_HEALTH.size * fração` cai em fração de pixel quase sempre.
	var frame_size := RECT_HEALTH.size
	var channel := Rect2(
		(frame_size * Vector2(HP_CHANNEL_NORM.position.x, HP_CHANNEL_NORM.position.y)).round(),
		(frame_size * Vector2(HP_CHANNEL_NORM.size.x, HP_CHANNEL_NORM.size.y)).round(),
	)

	# `TextureProgressBar` em vez de trocar a textura por percentual: o valor
	# controla o recorte da MESMA imagem (`fill_mode` esquerda→direita mantém
	# a ponta esquerda fixa e encolhe pela direita), então não existe uma
	# textura por faixa de HP para manter.
	_health_fill = TextureProgressBar.new()
	_health_fill.name = "HealthFill"
	_health_fill.position = channel.position
	_health_fill.size = channel.size
	_health_fill.texture_progress = load(STATUS_DIR + "active_creature_hp_fill.png")
	_health_fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	# Sem isto, `TextureProgressBar` desenha `texture_progress` no tamanho
	# NATIVO do PNG (655×84) recortado pelo valor, ignorando `.size` — o fill
	# saía maior que o canal inteiro e vazava por trás do divisor e dos
	# botões. Nine-patch com margens zero é o que faz o Godot esticar a
	# textura pro retângulo do nó em vez de desenhá-la em pixel-a-pixel.
	_health_fill.nine_patch_stretch = true
	_health_fill.min_value = 0
	_health_fill.max_value = 1
	_health_fill.value = 1
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.add_child(_health_fill)

	# Mesmo retângulo e o mesmo valor do fill, sempre em conjunto — é o que
	# faz o highlight "acompanhar exatamente o preenchimento" em vez de
	# arriscar os dois se separarem numa edição futura. Opacidade reduzida
	# porque o brilho em cima do vermelho saturado do fill estava estourando
	# — ajuste de `modulate`, o PNG continua intacto.
	_health_highlight = TextureProgressBar.new()
	_health_highlight.name = "HealthHighlight"
	_health_highlight.position = channel.position
	_health_highlight.size = channel.size
	_health_highlight.texture_progress = load(STATUS_DIR + "active_creature_hp_highlight.png")
	_health_highlight.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_health_highlight.nine_patch_stretch = true
	_health_highlight.min_value = 0
	_health_highlight.max_value = 1
	_health_highlight.value = 1
	_health_highlight.modulate.a = 0.6
	_health_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.add_child(_health_highlight)

	_health_label = Label.new()
	_health_label.name = "HealthLabel"
	_health_label.position = channel.position
	_health_label.size = channel.size
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_label.add_theme_font_size_override("font_size", int(13 * _text_scale))
	_health_label.add_theme_color_override("font_color", Color(COL_BONE))
	_health_label.add_theme_color_override("font_outline_color", Color("#0A0B0D"))
	_health_label.add_theme_constant_override("outline_size", int(2 * _text_scale))
	_health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.add_child(_health_label)


func _build_level_area(parent: Control) -> void:
	_level_area = Control.new()
	_level_area.name = "LevelArea"
	_level_area.position = RECT_LEVEL.position
	_level_area.size = RECT_LEVEL.size
	_level_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_level_area)

	var badge := TextureRect.new()
	badge.name = "LevelBadge"
	badge.position = Vector2.ZERO
	badge.size = RECT_LEVEL.size
	badge.texture = load(STATUS_DIR + "active_creature_level_badge.png")
	badge.stretch_mode = TextureRect.STRETCH_SCALE
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_area.add_child(badge)

	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.position = Vector2.ZERO
	_level_label.size = RECT_LEVEL.size
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", int(24 * _text_scale))
	_level_label.add_theme_color_override("font_color", Color(COL_BONE))
	_level_label.add_theme_color_override("font_outline_color", Color("#0A0B0D"))
	_level_label.add_theme_constant_override("outline_size", int(3 * _text_scale))
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_area.add_child(_level_label)


func _build_info_labels(parent: Control) -> void:
	_top_info_font_size = int(17 * _text_scale)
	_top_info = RichTextLabel.new()
	_top_info.name = "TopInfo"
	_top_info.position = RECT_TOP_INFO.position
	_top_info.size = RECT_TOP_INFO.size
	_top_info.bbcode_enabled = true
	_top_info.scroll_active = false
	# `_fit_text` já garante que o nome cabe numa linha; isto é o
	# cinto-e-suspensório contra um caso que a medida aproximada errar —
	# sem isso um nome longo quebraria linha e vazaria por cima da barra
	# de HP em vez de simplesmente não aparecer inteiro.
	_top_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	_top_info.clip_contents = true
	_top_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_info.add_theme_font_size_override("normal_font_size", _top_info_font_size)
	parent.add_child(_top_info)

	_bottom_info_font_size = int(12 * _text_scale)
	_bottom_info = RichTextLabel.new()
	_bottom_info.name = "BottomInfo"
	_bottom_info.position = RECT_BOTTOM_INFO.position
	_bottom_info.size = RECT_BOTTOM_INFO.size
	_bottom_info.bbcode_enabled = true
	_bottom_info.scroll_active = false
	_bottom_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bottom_info.clip_contents = true
	_bottom_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_info.add_theme_font_size_override("normal_font_size", _bottom_info_font_size)
	parent.add_child(_bottom_info)


func _build_actions(parent: Control) -> void:
	var actions := Control.new()
	actions.name = "Actions"
	actions.position = Vector2.ZERO
	actions.size = BASE_SIZE
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(actions)

	_inventory_button = _make_button("InventoryButton", RECT_INVENTORY, "inventory")
	_inventory_button.pressed.connect(func(): inventory_requested.emit())
	actions.add_child(_inventory_button)

	_equipment_button = _make_button("EquipmentButton", RECT_EQUIPMENT, "equipment")
	_equipment_button.pressed.connect(func(): equipment_requested.emit())
	actions.add_child(_equipment_button)

	_relicary_button = _make_button("RelicaryButton", RECT_RELICARY, "relicary")
	_relicary_button.pressed.connect(func(): relicary_requested.emit())
	actions.add_child(_relicary_button)


## Um `TextureButton` por ação, os quatro estados vindos de
## `active_creature_button_<prefix>_<estado>.png`. `ignore_texture_size` +
## `size` explícito é o que garante o mesmo `Control Rect` nos quatro estados
## — sem isso o mínimo do nó seria o tamanho em pixels de cada textura
## (512×512), e trocar de estado não mudaria nada porque todas têm o mesmo
## tamanho de arquivo, mas o próprio layout ficaria refém desse mínimo.
func _make_button(node_name: String, rect: Rect2, prefix: String) -> TextureButton:
	var b := TextureButton.new()
	b.name = node_name
	b.position = rect.position
	b.size = rect.size
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.texture_normal = _button_state_texture(prefix, "normal")
	b.texture_hover = _button_state_texture(prefix, "hover")
	b.texture_pressed = _button_state_texture(prefix, "pressed")
	b.texture_disabled = _button_state_texture(prefix, "disabled")
	return b


## Recorta `BUTTON_ICON_REGION` do canvas 512×512 do estado — sem isso o
## Godot reduz o quadro INTEIRO (ícone + margem transparente) pro encaixe
## quadrado do painel, e o ícone visível sobra pequeno, cercado de vão vazio.
## `filter_clip` trava a amostra dentro da região quando o filtro linear do
## `STRETCH_SCALE` tentaria ler um texel vizinho fora dela.
func _button_state_texture(prefix: String, state: String) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(BUTTONS_DIR + "active_creature_button_%s_%s.png" % [prefix, state])
	atlas.region = BUTTON_ICON_REGION
	atlas.filter_clip = true
	return atlas


## O bioma entra pelo setup e é trocado por `set_biome`, nunca pelo refresh:
## o refresh roda a cada captura e recebe os números do time, que não têm nada
## a ver com onde o jogador está pisando.
func setup(db: BestiaryData, biome_code: String) -> void:
	_db = db
	_biome_code = biome_code
	refresh("", 1, 0, 6)


## Troca o bioma corrente sem redesenhar — quem redesenha é o refresh seguinte,
## que é quem tem os números do time em mãos.
##
## Existe desde que o bioma virou consulta por posição: ele muda enquanto o
## jogador anda, e chamar `setup` de novo a cada fronteira apagaria o painel
## para o estado vazio no meio da caminhada.
func set_biome(biome_code: String) -> void:
	_biome_code = biome_code


## `hp`/`max_hp` chegam prontos do time em vez de saírem de `stats_at_level`:
## o HP corrente persiste entre batalhas e é o time quem guarda, não o bundle.
## `hp` negativo desliga a linha — é o que o duelo solto de playtest passa.
## `roster_capacity` vem de `PlayerRoster.capacity()` — dinâmico desde que o
## Relicário existe, não mais o `MAX_SLOTS` fixo de antes.
func refresh(creature_code: String, level: int, roster_size: int, roster_capacity: int,
		hp: int = -1, max_hp: int = 0) -> void:
	if _top_info == null:
		return

	var c := _db.creature(creature_code) if (_db and creature_code != "") else {}
	if c.is_empty():
		_show_empty_state(roster_size, roster_capacity)
		return

	var class_code := str(c.get("class", ""))
	var element_code := str(c.get("element", ""))

	_update_portrait(creature_code, class_code, element_code)
	_update_health(hp, max_hp)

	_level_area.show()
	_level_label.text = str(level)

	# O nível já está no selo (`LevelArea`) — repeti-lo aqui como "Lv 10" era
	# a mesma informação duas vezes na mesma respirada visual.
	var caida := hp >= 0 and hp <= 0
	var name_tag := "  [color=%s]caida[/color]" % COL_EMBER if caida else ""
	var name := _fit_text(str(c.get("name", creature_code)), RECT_TOP_INFO.size.x - NAME_MARGIN,
		_top_info_font_size)
	_top_info.text = "[color=%s][b]%s[/b][/color]%s" % [COL_BONE, name, name_tag]

	# A faixa escura abaixo da barra de HP (`RECT_BOTTOM_INFO`) mede ~46px de
	# altura no canvas de 320 — só cabe UMA linha neste tamanho de fonte
	# (a versão com uma segunda linha de bioma/preferidos ficava cortada pelo
	# `clip_contents`, invisível, o que é pior que não mostrar). ATQ/DEF/VEL,
	# bioma, preferidos e a contagem do time saíram daqui — o time e o bioma
	# seguem visíveis na janela do time (tecla T) e ao cruzar fronteira; quem
	# fica é o papel de mineração, porque é ele — não os stats — o motivo do
	# painel existir (ver o comentário de topo do arquivo).
	var lines: Array[String] = []
	var role := MiningTable.role_label(_db, class_code)
	if role != "":
		var mine_plain := "mineracao  %s · x%.1f" % [role, MiningTable.speed_modifier(_db, class_code)]
		var mine_colored := "[color=%s]mineracao[/color]  [color=%s]%s · x%.1f[/color]" % [
			COL_SLATE, COL_MOSS, role, MiningTable.speed_modifier(_db, class_code)]
		lines.append(_fit_line(mine_plain, mine_colored, RECT_BOTTOM_INFO.size.x, _bottom_info_font_size))
	_bottom_info.text = "\n".join(lines)


## Trunca com reticências se `text` (sem bbcode) não couber em `max_width` na
## fonte padrão do tema, no mesmo `font_size` que o label realmente usa —
## medir com outro tamanho aprovaria strings que a tela depois recusa.
func _fit_text(text: String, max_width: float, font_size: int) -> String:
	var font := ThemeDB.fallback_font
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var truncated := text
	while truncated.length() > 1:
		truncated = truncated.substr(0, truncated.length() - 1)
		if font.get_string_size(truncated + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			return truncated + "…"
	return "…"


## Mede a versão SEM bbcode (`plain`) e devolve `colored` intacta se couber.
## Truncar a string com as tags ainda dentro cortaria no meio de um `[color=]`
## e quebraria o bbcode — no caso raro de estourar a largura, a linha perde a
## cor extra e vira só `COL_SLATE`, o que ainda é legível.
func _fit_line(plain: String, colored: String, max_width: float, font_size: int) -> String:
	var font := ThemeDB.fallback_font
	if font.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return colored
	return "[color=%s]%s[/color]" % [COL_SLATE, _fit_text(plain, max_width, font_size)]


func _show_empty_state(roster_size: int, roster_capacity: int) -> void:
	_creature_portrait.hide()
	_class_frame.hide()
	_element_frame.hide()
	_health_bar.hide()
	_level_area.hide()
	_top_info.text = "[color=%s]criatura ativa[/color]   [color=%s][ nenhuma ][/color]" % [COL_SLATE, COL_SLATE]
	_bottom_info.text = "[color=%s][T] time  (%d/%d)[/color]" % [COL_SLATE, roster_size, roster_capacity]


func _update_portrait(creature_code: String, class_code: String, element_code: String) -> void:
	var card_path := CARDS_DIR + creature_code + ".png"
	if ResourceLoader.exists(card_path):
		_creature_portrait.texture = load(card_path)
		_creature_portrait.show()
	else:
		_creature_portrait.hide()

	if class_code == "":
		_class_frame.hide()
	elif CLASS_FRAME_BY_CODE.has(class_code):
		_class_frame.texture = load(CLASS_FRAME_BY_CODE[class_code])
		_class_frame.show()
	else:
		_class_frame.hide()
		_warn_unknown("classe", class_code)

	if element_code == "":
		_element_frame.hide()
	elif ELEMENT_RING_BY_CODE.has(element_code):
		_element_frame.texture = load(ELEMENT_RING_BY_CODE[element_code])
		_element_frame.show()
	else:
		_element_frame.hide()
		_warn_unknown("elemento", element_code)


## Uma vez por código desconhecido, não por refresh: o refresh roda a cada
## captura/troca de ativa, e sem o dedupe o console afogaria num único código
## faltando no mapa.
func _warn_unknown(kind: String, code: String) -> void:
	if _warned_codes.has(code):
		return
	_warned_codes[code] = true
	push_warning("ActiveCreaturePanel: %s desconhecido '%s' — moldura nao aplicada." % [kind, code])


func _update_health(hp: int, max_hp: int) -> void:
	if hp < 0 or max_hp <= 0:
		_health_bar.hide()
		return
	_health_bar.show()
	_health_fill.max_value = max_hp
	_health_fill.value = hp
	_health_highlight.max_value = max_hp
	_health_highlight.value = hp
	_health_label.text = "%d/%d" % [hp, max_hp]
