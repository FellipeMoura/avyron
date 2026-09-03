class_name Battle
extends RefCounted

## Máquina de combate por turnos, 1v1 com troca livre.
##
## Sem nós, sem sinais, sem árvore de cena: uma rodada entra como duas ações
## e sai como uma lista de eventos. Isso torna o sistema inteiro testável
## headless e deixa a apresentação — animação, câmera, HUD — livre para
## consumir os eventos no ritmo que quiser.
##
## Especificação: documentos `combate`, `carga-e-despertar` e `captura`.

enum Outcome {
	ONGOING,
	PLAYER_WON,
	PLAYER_LOST,
	CAPTURED,
	FLED,
}

## Teto e piso dos multiplicadores acumulados de buff/debuff. Sem isso, seis
## turnos empilhando +30% viram um número que a fórmula de dano não comporta.
const MODIFIER_MIN := 0.25
const MODIFIER_MAX := 4.0

var db: BestiaryData
var rules: Dictionary

var player_party: Array = []
var player_active_index := 0
var enemy: Combatant

## Batalha contra criatura selvagem: permite capturar e fugir.
var is_wild := true
var can_flee := true

var outcome: Outcome = Outcome.ONGOING
var round_number := 0
var log_events: Array = []

var rng := RandomNumberGenerator.new()

## Registro de participação de XP, alinhado por índice com `player_party` —
## não com quem está em campo agora. Uma troca no meio da luta não apaga o
## crédito de quem já agiu ou apanhou antes dela; é por isso que isto vive
## pelo tempo da batalha inteira, e não dentro de `Combatant` (que é
## descartado a cada luta de qualquer forma). Ver `xp_participants`.
var _xp_participation: Array = []


func _init(bestiary: BestiaryData, party: Array, opponent: Combatant, wild: bool = true) -> void:
	db = bestiary
	rules = bestiary.rules
	player_party = party
	enemy = opponent
	is_wild = wild
	rng.randomize()
	for i in player_party.size():
		_xp_participation.append({"participated": false, "damage_dealt": 0, "damage_taken": 0})


## Aplica os modificadores passivos do set do jogador (Amplificador e
## Encantador) — uma vez, no começo da batalha, e para a batalha inteira.
##
## ## Por que em todo o time, e não só em quem está em campo
##
## A peça é do **domador**, não da criatura: trocar de criatura no meio da
## luta não desequipa nada. Aplicar só na ativa obrigaria a reaplicar em cada
## troca e em cada substituição — três lugares para o mesmo efeito, e o
## terceiro seria esquecido. Aplicando no time inteiro na montagem, o
## modificador atravessa `_do_switch` e `replace_active` sem que nenhum dos
## dois precise saber que este sistema existe.
##
## ## Por que aqui e não em `PlayerLoadout`
##
## Porque o teto acumulado (`MODIFIER_MIN/MAX`) é desta classe e vale para
## **todas** as fontes de modificador — equipamento, habilidade de suporte, e
## o que vier. Se o loadout mexesse em `Combatant` direto, o clamp passaria a
## ter dois donos e a soma poderia estourar por um caminho e não pelo outro.
## É por isso que `PlayerLoadout.modifiers()` devolve dado cru.
##
## O alvo sai do **slot**, não do `effectCode`: `amplifier` cai no time do
## jogador, `enchanter` no adversário. Quem decidiu isso foi o catálogo, ao
## separar as duas colunas — o código só obedece, e um slot novo que ninguém
## ensinou aqui é ignorado em vez de aplicado no alvo errado.
func apply_loadout(loadout: PlayerLoadout) -> void:
	if loadout == null or db == null:
		return
	for mod in loadout.modifiers(db):
		var slot := str(mod["slot"])
		var targets: Array = []
		match slot:
			BestiaryData.SLOT_AMPLIFIER:
				targets = player_party
			BestiaryData.SLOT_ENCHANTER:
				targets = [enemy] if enemy != null else []
			_:
				continue
		for c: Combatant in targets:
			if c != null:
				_apply_modifier(c, str(mod["effect_code"]), float(mod["value"]))


## O único lugar que mexe em `attack_modifier`/`defense_modifier`, para
## equipamento e para golpe de suporte. Buff multiplica por `1 + v/100`,
## debuff por `1 - v/100`, e o clamp é o mesmo dos dois lados — foi extraído
## de `_apply_status` quando o equipamento virou a segunda fonte, e não
## duplicado.
func _apply_modifier(target: Combatant, effect_code: String, value: float) -> void:
	match effect_code:
		"buff_attack":
			target.attack_modifier = clampf(
				target.attack_modifier * (1.0 + value / 100.0), MODIFIER_MIN, MODIFIER_MAX)
		"buff_defense":
			target.defense_modifier = clampf(
				target.defense_modifier * (1.0 + value / 100.0), MODIFIER_MIN, MODIFIER_MAX)
		"debuff_attack":
			target.attack_modifier = clampf(
				target.attack_modifier * (1.0 - value / 100.0), MODIFIER_MIN, MODIFIER_MAX)
		"debuff_defense":
			target.defense_modifier = clampf(
				target.defense_modifier * (1.0 - value / 100.0), MODIFIER_MIN, MODIFIER_MAX)


func player_active() -> Combatant:
	return player_party[player_active_index] if player_active_index < player_party.size() else null


func charge_max() -> float:
	return float(rules["charge"]["max"])


func is_over() -> bool:
	return outcome != Outcome.ONGOING


## O ativo caiu mas ainda há criatura viva no time — a rodada não avança até
## o jogador escolher quem entra.
func needs_replacement() -> bool:
	if outcome != Outcome.ONGOING:
		return false
	var active := player_active()
	return active != null and active.is_fainted()


func living_party_indices() -> Array:
	var out: Array = []
	for i in player_party.size():
		if not player_party[i].is_fainted():
			out.append(i)
	return out


## Põe em campo quem substitui a ativa desmaiada.
##
## **Não** é a ação de troca. `_do_switch` custa a rodada e disputa prioridade,
## porque recuar uma criatura de pé é uma jogada; isto acontece *entre*
## rodadas e é de graça, porque o jogador não escolheu perder a criatura —
## cobrar um turno por ela seria punir duas vezes o mesmo golpe.
##
## Precisa existir separado por um motivo mecânico, não só de design:
## `resolve_round` pula o ator que está desmaiado, então uma ação de troca
## emitida pela ativa caída nunca chegaria a executar.
func replace_active(index: int) -> bool:
	if not needs_replacement():
		return false
	if index < 0 or index >= player_party.size() or player_party[index].is_fainted():
		return false
	player_active_index = index
	_log("switch", player_party[index], {
		"text": "%s entra no lugar" % player_party[index].display_name
	})
	return true


# ---------------------------------------------------------------------------
# Despertar Ancestral — fora do turno
# ---------------------------------------------------------------------------

## Ativar não consome o turno, então isto é chamado entre rodadas e não
## compete com atacar. Devolve false se o medidor não está cheio.
func activate_awakening(side_is_player: bool) -> bool:
	var c := player_active() if side_is_player else enemy
	if c == null or not c.can_awaken(charge_max()):
		return false
	c.awaken()
	_log("awaken", c, {
		"text": "%s acessa o Despertar Ancestral (%s) por %d turnos"
			% [c.display_name, c.awakening_name, c.awakening_duration]
	})
	return true


# ---------------------------------------------------------------------------
# rodada
# ---------------------------------------------------------------------------

## Resolve uma rodada completa e devolve só os eventos gerados nela.
func resolve_round(player_action: BattleAction, enemy_action: BattleAction) -> Array:
	if is_over():
		return []

	var start := log_events.size()
	round_number += 1

	for entry in _order(player_action, enemy_action):
		if is_over():
			break
		var actor: Combatant = entry["actor"]
		if actor.is_fainted():
			continue
		_execute(entry["action"], entry["is_player"])
		_check_faints()

	if not is_over():
		_tick_awakenings()

	return log_events.slice(start)


## Ordena as duas ações. Prioridade domina velocidade; empate vai para o
## sorteio, que é o que impede duas criaturas de mesma velocidade de terem
## uma ordem sempre previsível.
func _order(player_action: BattleAction, enemy_action: BattleAction) -> Array:
	var p_prio := _action_priority(player_action, player_active())
	var e_prio := _action_priority(enemy_action, enemy)

	var cmp := CombatMath.turn_order_compare(
		p_prio, player_active().effective_speed(),
		e_prio, enemy.effective_speed()
	)
	if cmp == 0:
		cmp = 1 if rng.randf() < 0.5 else -1

	var player_entry := {"actor": player_active(), "action": player_action, "is_player": true}
	var enemy_entry := {"actor": enemy, "action": enemy_action, "is_player": false}
	return [player_entry, enemy_entry] if cmp > 0 else [enemy_entry, player_entry]


func _action_priority(action: BattleAction, actor: Combatant) -> int:
	match action.kind:
		BattleAction.Kind.FLEE:
			return BattleAction.SWITCH_PRIORITY + 1
		BattleAction.Kind.SWITCH:
			return BattleAction.SWITCH_PRIORITY
		BattleAction.Kind.CAPTURE:
			return 0
		_:
			var a := actor.ability_by_code(action.ability_code)
			return int(a.get("priority", 0)) if not a.is_empty() else 0


func _execute(action: BattleAction, is_player: bool) -> void:
	match action.kind:
		BattleAction.Kind.SWITCH:
			_do_switch(action, is_player)
		BattleAction.Kind.CAPTURE:
			_do_capture(action, is_player)
		BattleAction.Kind.FLEE:
			_do_flee(is_player)
		BattleAction.Kind.ABILITY:
			_do_ability(action, is_player)


# ---------------------------------------------------------------------------
# ações
# ---------------------------------------------------------------------------

func _do_switch(action: BattleAction, is_player: bool) -> void:
	if not is_player:
		return  # o lado selvagem não troca
	var i := action.switch_to_index
	if i < 0 or i >= player_party.size() or player_party[i].is_fainted() or i == player_active_index:
		_log("invalid", player_active(), {"text": "troca invalida ignorada"})
		return

	var leaving := player_active()
	# Sair de campo reverte o Despertar: a transformação é do momento, não
	# um estado que se guarda no banco de reservas.
	leaving.revert()
	player_active_index = i
	_log("switch", player_party[i], {
		"text": "%s recua; %s entra" % [leaving.display_name, player_party[i].display_name]
	})


func _do_flee(is_player: bool) -> void:
	if not is_player:
		return
	if not can_flee:
		_log("flee_failed", player_active(), {"text": "nao da para fugir desta luta"})
		return
	outcome = Outcome.FLED
	_log("flee", player_active(), {"text": "voce fugiu"})


func _do_capture(action: BattleAction, is_player: bool) -> void:
	if not is_player:
		return
	if not is_wild:
		_log("capture_failed", enemy, {"text": "nao da para capturar a criatura de outro domador"})
		return

	# Tentar capturar é uma ação válida da ativa, sucesso ou não — conta para
	# participação de XP mesmo numa luta que termina em `CAPTURED` (que não
	# gera XP de qualquer forma, só drop; o registro aqui é por consistência).
	_mark_participation(player_active_index, 0, 0)

	var chance := RelicMath.capture_chance(
		db, action.relic_rate, action.relic_element, action.relic_class,
		enemy.catch_rate, enemy.element, enemy.creature_class
	)
	var roll := rng.randf()
	if roll < chance:
		outcome = Outcome.CAPTURED
		_log("capture", enemy, {
			"chance": chance,
			"text": "%s foi capturada (chance %.0f%%)" % [enemy.display_name, chance * 100.0]
		})
	else:
		_log("capture_failed", enemy, {
			"chance": chance,
			"text": "%s escapou (chance era %.0f%%)" % [enemy.display_name, chance * 100.0]
		})


func _do_ability(action: BattleAction, is_player: bool) -> void:
	var actor := player_active() if is_player else enemy
	var target := enemy if is_player else player_active()

	var ability := actor.ability_by_code(action.ability_code)
	if ability.is_empty() or actor.uses_left(action.ability_code) <= 0:
		_log("invalid", actor, {"text": "%s nao pode usar %s" % [actor.display_name, action.ability_code]})
		return
	if bool(ability["awakeningOnly"]) and not actor.is_awakened:
		_log("invalid", actor, {"text": "%s so com o Despertar ativo" % str(ability["name"])})
		return

	actor.consume_use(action.ability_code)
	# Ação válida executada, hit ou miss — é o que basta para participação
	# (documento de XP por participação: "executou uma ação válida em
	# combate"). Só a metade do jogador entra no registro; o lado selvagem
	# não acumula XP.
	if is_player:
		_mark_participation(player_active_index, 0, 0)

	if rng.randf() * 100.0 >= float(ability["accuracy"]):
		_log("miss", actor, {"text": "%s errou %s" % [actor.display_name, str(ability["name"])]})
		return

	var effect := str(ability["effectCode"])
	if effect == "damage":
		_apply_damage(actor, target, ability, is_player)
	else:
		_apply_status(actor, target, ability, effect, is_player)


func _apply_damage(actor: Combatant, target: Combatant, ability: Dictionary, is_player: bool) -> void:
	# Golpe sem elemento não recebe nem sofre multiplicador — utilitários
	# como Bote batem igual contra qualquer alvo.
	var ability_element := BestiaryData.ability_element(ability)
	var elem_mult := 1.0
	if ability_element != "":
		elem_mult = db.element_multiplier(ability_element, target.element)

	var d: Dictionary = rules["damage"]
	var variance := rng.randf_range(float(d["varianceMin"]), float(d["varianceMax"]))
	var dmg := CombatMath.damage(
		int(ability["power"]), actor.effective_attack(), target.effective_defense(),
		elem_mult, rules, variance
	)

	var hp_before := target.hp
	target.hp = maxi(0, target.hp - dmg)
	# Dano efetivo — a perda real de HP, sem contar overkill. É o que conta
	# para contribuição de XP (documento de XP por participação); `dmg` cru
	# seguiria contando um golpe de 100 contra 17 de HP como 100.
	var effective := hp_before - target.hp
	if is_player:
		_mark_participation(player_active_index, effective, 0)
	else:
		_mark_participation(player_active_index, 0, effective)

	# A carga sobe dos dois lados, mas quem apanha enche o dobro de quem bate.
	target.add_charge(
		CombatMath.charge_from_damage_taken(dmg, target.max_hp, target.effective_charge(), rules),
		charge_max()
	)
	actor.add_charge(
		CombatMath.charge_from_damage_dealt(dmg, target.max_hp, actor.effective_charge(), rules),
		charge_max()
	)

	var flavor := ""
	if elem_mult > 1.0:
		flavor = " — muito eficaz"
	elif elem_mult < 1.0:
		flavor = " — pouco eficaz"

	_log("damage", actor, {
		"target": target.code,
		"ability": str(ability["code"]),
		"damage": dmg,
		"element_multiplier": elem_mult,
		"target_hp": target.hp,
		"text": "%s usa %s: %d de dano%s (%s com %d/%d)"
			% [actor.display_name, str(ability["name"]), dmg, flavor,
			   target.display_name, target.hp, target.max_hp]
	})


func _apply_status(actor: Combatant, target: Combatant, ability: Dictionary, effect: String, is_player: bool) -> void:
	var value := float(ability["effectValue"])
	var name := str(ability["name"])

	# O quem-leva sai do próprio código do efeito: `buff_*` é sempre em si
	# mesmo, `debuff_*` sempre no alvo. A aritmética e o clamp são de
	# `_apply_modifier`, compartilhados com o set do jogador — a mesma soma
	# não pode ter dois tetos.
	match effect:
		"buff_attack":
			_apply_modifier(actor, effect, value)
			_log("buff", actor, {"text": "%s usa %s: ataque +%d%%" % [actor.display_name, name, int(value)]})
		"buff_defense":
			_apply_modifier(actor, effect, value)
			_log("buff", actor, {"text": "%s usa %s: defesa +%d%%" % [actor.display_name, name, int(value)]})
		"debuff_attack":
			_apply_modifier(target, effect, value)
			# Debuff é hostil — quem leva participa de XP mesmo sem perder HP
			# (documento de XP por participação: "recebido uma ação hostil").
			if not is_player:
				_mark_participation(player_active_index, 0, 0)
			_log("debuff", actor, {"text": "%s usa %s: ataque de %s -%d%%"
				% [actor.display_name, name, target.display_name, int(value)]})
		"debuff_defense":
			_apply_modifier(target, effect, value)
			if not is_player:
				_mark_participation(player_active_index, 0, 0)
			_log("debuff", actor, {"text": "%s usa %s: defesa de %s -%d%%"
				% [actor.display_name, name, target.display_name, int(value)]})
		"heal":
			var healed := mini(int(float(actor.max_hp) * value / 100.0), actor.max_hp - actor.hp)
			actor.hp += healed
			_log("heal", actor, {"amount": healed,
				"text": "%s usa %s: recupera %d de HP" % [actor.display_name, name, healed]})
		"charge_gain":
			actor.add_charge(value, charge_max())
			_log("charge", actor, {"amount": value,
				"text": "%s usa %s: carga em %d/100" % [actor.display_name, name, int(actor.charge_meter)]})


# ---------------------------------------------------------------------------
# fim de rodada
# ---------------------------------------------------------------------------

func _tick_awakenings() -> void:
	for c in [player_active(), enemy]:
		if c != null and c.tick_awakening():
			_log("revert", c, {"text": "%s volta a forma base" % c.display_name})


func _check_faints() -> void:
	if enemy.is_fainted():
		outcome = Outcome.PLAYER_WON
		_log("faint", enemy, {"text": "%s foi derrotada" % enemy.display_name})
		return

	var active := player_active()
	if active != null and active.is_fainted():
		_log("faint", active, {"text": "%s foi derrotada" % active.display_name})
		if living_party_indices().is_empty():
			outcome = Outcome.PLAYER_LOST


## `is_player` compara por REFERÊNCIA (`actor == player_active()`), não por
## código — um evento não pode ser atribuído ao lado errado numa luta onde as
## duas criaturas são da mesma espécie (mesmo `actor.code` dos dois lados).
## Existe para quem consome o log de fora (apresentação de golpe/status por
## evento) resolver o corpo certo sem precisar comparar código, que é
## exatamente o que quebraria nesse caso.
func _log(type: String, actor: Combatant, extra: Dictionary) -> void:
	var event := {
		"round": round_number,
		"type": type,
		"actor": actor.code if actor else "",
		"is_player": actor == player_active() if actor else false,
	}
	event.merge(extra)
	log_events.append(event)


# ---------------------------------------------------------------------------
# participação e contribuição — XP de vitória
#
# Registro bruto só; a fórmula de distribuição (parcela base + parcela por
# contribuição, arredondamento que conserva o total) fica em `ProgressionMath`,
# mesma separação de sempre entre "esta classe indexa/registra estado" e
# "aquela decide a fórmula". Quem consome isto é `WorldRoot`, só depois que a
# luta termina em vitória — `Battle` não sabe nada sobre XP em si.
# ---------------------------------------------------------------------------

func _mark_participation(index: int, dealt_delta: int, taken_delta: int) -> void:
	if index < 0 or index >= _xp_participation.size():
		return
	var p: Dictionary = _xp_participation[index]
	p["participated"] = true
	p["damage_dealt"] = int(p["damage_dealt"]) + dealt_delta
	p["damage_taken"] = int(p["damage_taken"]) + taken_delta


## Índice (em `player_party`) e contribuição de cada criatura que participou
## da luta — agiu validamente ou levou uma ação hostil enquanto em campo, a
## qualquer momento da batalha, não só quem terminou nela. Contribuição =
## dano causado efetivo + dano sofrido efetivo (sem overkill, ver
## `_apply_damage`). Vazio se, por algum motivo, ninguém chegou a agir.
func xp_participants() -> Array:
	var out: Array = []
	for i in _xp_participation.size():
		var p: Dictionary = _xp_participation[i]
		if bool(p.get("participated", false)):
			out.append({
				"index": i,
				"contribution": int(p.get("damage_dealt", 0)) + int(p.get("damage_taken", 0)),
			})
	return out


# ---------------------------------------------------------------------------
# IA do lado selvagem
# ---------------------------------------------------------------------------

func choose_enemy_action() -> BattleAction:
	return choose_action_for(enemy, player_active())


## Escolha simples e legível: entre os golpes disponíveis, prefere os de dano,
## e entre esses prefere o de maior dano esperado contra o alvo atual — o que
## faz a vantagem elemental ser sentida sem escrever uma árvore de decisão.
##
## Serve os dois lados: a IA do selvagem em jogo, e ambos os lados quando o
## `balance_probe` simula milhares de lutas.
func choose_action_for(actor: Combatant, target: Combatant) -> BattleAction:
	var options := actor.available_abilities()
	if options.is_empty():
		return BattleAction.use_ability("")  # sem opções: perde o turno

	var best: Dictionary = {}
	var best_score := -1.0

	for a in options:
		if str(a["effectCode"]) != "damage":
			continue
		var elem := BestiaryData.ability_element(a)
		var mult := 1.0
		if elem != "":
			mult = db.element_multiplier(elem, target.element)
		var score := float(a["power"]) * mult * (float(a["accuracy"]) / 100.0)
		if score > best_score:
			best_score = score
			best = a

	if best.is_empty():
		best = options[rng.randi() % options.size()]

	return BattleAction.use_ability(str(best["code"]))
