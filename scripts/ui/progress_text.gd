class_name ProgressText
extends RefCounted

## Como a progressão de nível vira texto. Uma frase só pra todo lugar que a
## mostra — janela do time, janela do set, posto do Relicário e a mensagem
## pós-luta — porque a leitura vem do mesmo funil (`PlayerRoster.progress_at`
## / `PlayerRelic.progress`), e duas frases pra um estado só fariam o jogador
## achar que são dois estados. Nada aqui calcula: só embrulha o dicionário
## que o funil devolve.
##
## Funções estáticas puras, mesmo contrato de `ItemEffects.heal_label`.

const COL_MOSS  := "#7A8C6B"
const COL_EMBER := "#C6552F"
const COL_SLATE := "#6B7280"

## Largura da barra em células — apresentação, não tuning.
const BAR_CELLS := 10


## Barra de XP em texto, `▰▰▰▱▱▱▱▱▱▱`. Cheia no teto de nível: não há próximo,
## e uma barra vazia ali leria como "nada feito". Sempre em moss — o acento
## ember da linha fica com `status_line`, uma vez só por linha.
static func bar(progress: Dictionary) -> String:
	var filled := BAR_CELLS
	if not bool(progress.get("at_cap", false)):
		var to_next := int(progress.get("xp_to_next", 0))
		var ratio := 0.0
		if to_next > 0:
			ratio = clampf(float(progress.get("xp", 0)) / float(to_next), 0.0, 1.0)
		filled = int(floor(ratio * BAR_CELLS))
	return "[color=%s]%s[/color][color=%s]%s[/color]" % [
		COL_MOSS, "▰".repeat(filled), COL_SLATE, "▱".repeat(BAR_CELLS - filled)]


## `xp 12/47`, ou `nivel maximo` no teto.
static func xp_label(progress: Dictionary) -> String:
	if bool(progress.get("at_cap", false)):
		return "[color=%s]nivel maximo[/color]" % COL_SLATE
	return "[color=%s]xp[/color] %d/%d" % [
		COL_SLATE, int(progress.get("xp", 0)), int(progress.get("xp_to_next", 0))]


## O que falta pra subir, na frase que responde à pergunta do jogador. Em
## bbcode, com "pronta pra subir" como o único acento ember:
##
##     pronta pra subir · falta 1× Arambita (tem 0)         barra cheia, sem o item
##     pronta pra subir · 1× Arambita na bolsa, sobe na proxima vitoria
##     sobe com 1× Arambita (tem 3)                          acumulando
##     sem classe: nao sobe de nivel                         relicário neutro
##     nivel maximo
##
## `trigger` é o que concede o próximo XP — "vitoria" pra criatura, "captura"
## pro relicário. Vazio quando o bundle não tem curva: não há o que dizer.
static func status_line(
	db: BestiaryData, progress: Dictionary, inventory: PlayerInventory, trigger := "vitoria"
) -> String:
	var parts := _status_parts(db, progress, inventory, trigger)
	if parts[0] == "" and parts[1] == "":
		return ""
	var out := ""
	if parts[0] != "":
		out += "[color=%s]%s[/color] " % [COL_EMBER, parts[0]]
	out += "[color=%s]%s[/color]" % [COL_SLATE, parts[1]]
	return out


## A mesma frase sem bbcode, pra HUD de mensagem (`Label` simples).
static func status_plain(
	db: BestiaryData, progress: Dictionary, inventory: PlayerInventory, trigger := "vitoria"
) -> String:
	var parts := _status_parts(db, progress, inventory, trigger)
	return (parts[0] + " " + parts[1]).strip_edges()


## `[acento, resto]` — o acento é o trecho que vai em ember, vazio quando a
## linha não tem urgência nenhuma.
static func _status_parts(
	db: BestiaryData, progress: Dictionary, inventory: PlayerInventory, trigger: String
) -> PackedStringArray:
	if bool(progress.get("at_cap", false)):
		return PackedStringArray(["", "nivel maximo"])
	if int(progress.get("xp_to_next", 0)) <= 0:
		return PackedStringArray(["", ""])
	# `can_level` só existe no dicionário do relicário — é lá que "sem classe"
	# é um estado legítimo (starter neutro). Criatura sempre tem classe; se o
	# material dela não existe, o furo é do catálogo, e a frase diz isso.
	if progress.has("can_level") and not bool(progress["can_level"]):
		return PackedStringArray(["", "sem classe: nao sobe de nivel"])
	var material := str(progress.get("material", ""))
	if material == "":
		return PackedStringArray(["", "sem material de classe no catalogo"])

	var item_name := db.item_name(material) if db else material
	var cost := int(progress.get("material_cost", 0))
	var have := inventory.quantity(material) if inventory else 0
	if bool(progress.get("xp_full", false)):
		if have >= cost:
			# O material chegou DEPOIS da trava: o próximo ganho resolve
			# sozinho, e dizer isso evita o jogador procurar um botão de subir.
			return PackedStringArray(["pronta pra subir",
				"· %d× %s na bolsa, sobe na proxima %s" % [cost, item_name, trigger]])
		return PackedStringArray(["pronta pra subir",
			"· falta %d× %s (tem %d)" % [cost, item_name, have]])
	return PackedStringArray(["", "sobe com %d× %s (tem %d)" % [cost, item_name, have]])
