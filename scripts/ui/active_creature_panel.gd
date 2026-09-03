class_name ActiveCreaturePanel
extends PanelContainer

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

const COL_BONE  := "#F2EDE0"
const COL_MOSS  := "#7A8C6B"
const COL_SLATE := "#6B7280"
const COL_EMBER := "#C6552F"

## Mesmo diretório espelhado que `CreatureInfoPanel` consulta — ver o
## comentário lá para o porquê do `ResourceLoader.exists` em vez de erro.
const CARDS_DIR := "res://cards/"

var _label: RichTextLabel
var _card: TextureRect
var _db: BestiaryData
var _biome_code := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left   = -300
	offset_top    = 16
	offset_right  = -16
	# Cresce até o conteúdo, como o painel de inventário: uma classe sem
	# perfil de trabalho tem três linhas a menos, e a caixa tem de acompanhar.
	offset_bottom = 16
	mouse_filter  = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0A0B0D", 0.75)
	style.border_color = Color("#1F2530")
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

	# Mesmo motivo do painel de identificação: PanelContainer estica todo
	# filho direto para o retângulo inteiro, então o card e o texto só
	# convivem lado a lado dentro de um HBox.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	_card = TextureRect.new()
	_card.custom_minimum_size = Vector2(48, 48)
	_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Ver o comentário em `CreatureInfoPanel`: sem isso o tamanho mínimo vira o
	# tamanho em pixels da arte original, e o painel inflava para acomodá-la.
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
	_label.add_theme_font_size_override("normal_font_size", 13)
	row.add_child(_label)


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
	if _label == null:
		return

	var lines: Array[String] = []
	lines.append("[color=%s]criatura ativa[/color]" % COL_SLATE)

	var c := _db.creature(creature_code) if (_db and creature_code != "") else {}
	if c.is_empty():
		_card.hide()
		lines.append("[color=%s][ nenhuma ][/color]" % COL_SLATE)
		_label.text = "\n".join(lines)
		return

	var card_path := CARDS_DIR + creature_code + ".png"
	if ResourceLoader.exists(card_path):
		_card.texture = load(card_path)
		_card.show()
	else:
		_card.hide()

	var class_code := str(c.get("class", ""))
	var element_code := str(c.get("element", ""))
	var element_name := str(_db.element(element_code).get("name", element_code))
	var class_name_label := str(_db.creature_class(class_code).get("name", class_code))

	lines.append("[color=%s][b]%s[/b][/color]   [color=%s]Lv %d[/color]"
		% [COL_BONE, str(c.get("name", creature_code)), COL_SLATE, level])
	lines.append("[color=%s]%s · %s[/color]" % [COL_SLATE, class_name_label, element_name])

	if hp >= 0 and max_hp > 0:
		# Caída fica em `ember`: é a informação que muda o que o jogador pode
		# fazer no próximo clique, então não pode se perder no cinza.
		var hp_color := COL_EMBER if hp <= 0 else COL_BONE
		var tag := "  [color=%s]caida[/color]" % COL_EMBER if hp <= 0 else ""
		lines.append("[color=%s]HP %d/%d[/color]%s" % [hp_color, hp, max_hp, tag])

	var stats := _db.stats_at_level(creature_code, level)
	if not stats.is_empty():
		lines.append("[color=%s]ATQ %d · DEF %d · VEL %d[/color]"
			% [COL_SLATE, int(stats["attack"]), int(stats["defense"]), int(stats["speed"])])

	# Perfil de mineração: só aparece se a classe tem `workFunction` no bundle.
	# Sem isso o painel mentiria dizendo "×1.0" para uma classe sem perfil.
	var role := MiningTable.role_label(_db, class_code)
	if role != "":
		lines.append("")
		lines.append("[color=%s]mineração[/color]  [color=%s]%s · ×%.1f[/color]"
			% [COL_SLATE, COL_MOSS, role, MiningTable.speed_modifier(_db, class_code)])
		# O bioma é a outra metade de `peso_classe × peso_bioma`, e sem ele o
		# painel explicaria metade do resultado. Desde que virou consulta por
		# posição ele também é o único lugar em que o jogador VÊ a partição
		# espacial funcionando: atravessar uma fronteira troca este nome e a
		# lista de preferidos junto.
		var biome_name := str(_db.biome(_biome_code).get("name", ""))
		if biome_name != "":
			lines.append("[color=%s]%s[/color]" % [COL_SLATE, biome_name])
		var preferred := MiningTable.preferred_names(_db, class_code, _biome_code, 3)
		if not preferred.is_empty():
			lines.append("[color=%s]%s[/color]" % [COL_SLATE, " · ".join(preferred)])

	lines.append("")
	lines.append("[color=%s][T] time  (%d/%d)[/color]"
		% [COL_SLATE, roster_size, roster_capacity])

	_label.text = "\n".join(lines)
