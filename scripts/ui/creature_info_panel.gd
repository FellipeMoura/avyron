class_name CreatureInfoPanel
extends PanelContainer

## Painel de identificação da criatura selecionada.
##
## Aparece no primeiro clique de uma criatura no mapa. Mostra o essencial pra
## decidir engajar — nome, classe, elemento, tamanho — e nada além disso.
## Stats efetivos ficam de fora de propósito: descoberta faz parte do combate,
## e se o jogador puder ler tudo antes, o cálculo de "vale a pena entrar?"
## deixa de existir.

const COL_BONE := "#F2EDE0"
const COL_MOSS := "#7A8C6B"
const COL_EMBER := "#C6552F"
const COL_SLATE := "#6B7280"

## Espelhado pelo bestiário (`pnpm game:export`) a partir de
## `apps/web/public/crt-cards/`, um `.png` por criatura, nomeado pelo código —
## mesmo contrato dos props de bioma: diretório inteiro, sem entrar no bundle.
## Cobertura é parcial de propósito (arte chega uma criatura de cada vez), por
## isso `ResourceLoader.exists` decide entre mostrar e esconder, nunca um erro.
const CARDS_DIR := "res://cards/"

var _label: RichTextLabel
var _card: TextureRect


func _ready() -> void:
	# Ancorado no rodapé central, largura fixa: a leitura tem de ser previsível
	# entre diferentes tamanhos de janela, e centralizar embaixo evita competir
	# com a criatura selecionada, que costuma estar no meio da tela.
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -260
	offset_right = 260
	offset_top = -140
	offset_bottom = -24
	custom_minimum_size = Vector2(520, 108)

	# Sem isso, um clique caindo em cima do painel é consumido pela HUD e nunca
	# chega ao `_unhandled_input` do WorldRoot — desmarcar a criatura clicando
	# ao lado ficaria bugado sempre que o painel encobrisse o ponto do clique.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0A0B0D")
	style.set_border_width_all(1)
	style.border_color = Color(COL_SLATE)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)

	# PanelContainer estica QUALQUER filho direto para o retângulo inteiro —
	# com dois filhos eles se sobreporiam. O HBox é o único filho direto por
	# isso, e é ele quem reparte o espaço entre o card e o texto.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	_card = TextureRect.new()
	_card.custom_minimum_size = Vector2(64, 64)
	_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Sem isso, o tamanho MÍNIMO do TextureRect é o tamanho em pixels da arte
	# original (a `expand_mode` padrão é `EXPAND_KEEP_SIZE`) — como o card é
	# bem maior que 64×64, o painel inteiro inflava para acomodar a textura, o
	# texto ia parar fora da área visível, e sobrava uma caixa preta enorme no
	# lugar. `EXPAND_IGNORE_SIZE` desliga essa influência: quem manda no
	# tamanho é só `custom_minimum_size` e o `stretch_mode` acima.
	_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.hide()
	row.add_child(_card)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("normal_font_size", 14)
	row.add_child(_label)

	hide()


## Popula o painel com dados da criatura e o exibe. `level` e `size_meters` já
## vêm do actor no mundo — o painel não recalcula nada, só formata.
func show_for(db: BestiaryData, creature_code: String, level: int, size_meters: float) -> void:
	var card_path := CARDS_DIR + creature_code + ".png"
	if ResourceLoader.exists(card_path):
		_card.texture = load(card_path)
		_card.show()
	else:
		_card.hide()

	var c := db.creature(creature_code)
	var creature_name := str(c.get("name", creature_code))
	var element_code := str(c.get("element", ""))
	var element_name := str(db.element(element_code).get("name", element_code))
	var class_code := str(c.get("class", ""))
	var class_label := str(db.creature_class(class_code).get("name", class_code))

	var lines: Array[String] = []
	lines.append("[color=%s][b]%s[/b][/color]   [color=%s]Lv %d[/color]"
		% [COL_BONE, creature_name, COL_SLATE, level])
	lines.append("[color=%s]%s · %s · %.1f m[/color]"
		% [COL_SLATE, class_label, element_name, size_meters])
	lines.append("")
	lines.append("[color=%s]Clique novamente para lutar[/color]   [color=%s]· Esc cancela[/color]"
		% [COL_MOSS, COL_SLATE])
	_label.text = "\n".join(lines)
	show()


func clear() -> void:
	hide()
