class_name EncounterDirector
extends RefCounted

## Governa o ciclo de vida do encontro: engatar o duelo (selvagem ou de
## arena), encenar (`BattleStaging`), fechar o duelo e distribuir a
## consequência — drop, XP de criatura, XP de captura do Relicário, Glifo.
##
## Extraído de `WorldRoot` porque era o bloco que mais crescia a cada sistema
## novo de combate — foi ele que ganhou XP compartilhado, drops, Glifo e
## arena, tudo empilhado nas mesmas duas funções antes desta extração.
##
## `RefCounted`, sem nó próprio: os nós que ele cria (`DuelScreen`,
## `BattleStaging`) entram como filhos do `_parent` recebido em `setup` —
## ele mesmo nunca entra na árvore e nunca precisa de `_process`. As
## dependências (roster, bolsa, bestiário, etc.) são as mesmas referências
## estáveis que `WorldRoot` resolve uma vez em `_ready` e nunca reatribui, e
## por isso podem ser passadas uma vez aqui também.
##
## `on_duel_changed` existe só porque os testes headless leem
## `_world.get("_duel")` por reflexão (não por método) — mover o dono do
## duelo para fora de `WorldRoot` sem isso quebraria essa leitura. É o único
## motivo deste hook existir; toda outra comunicação de volta usa `Callable`
## simples porque não há mais de um assinante possível.

const DUEL_SCENE := "res://scenes/duel.tscn"

var _parent: Node3D
var _camera: IsoCamera
var _spawner: CreatureSpawner
var _roster: PlayerRoster
var _inventory: PlayerInventory
var _companion: CompanionActor
var _player: Node3D
var _progress: PlayerProgress
var _db: BestiaryData
var _mine_rng: RandomNumberGenerator

var _show_message: Callable
var _hide_world_hud: Callable
var _show_world_hud: Callable
var _clear_selection: Callable
var _update_hint: Callable
var _on_duel_changed: Callable

var _duel: DuelScreen
var _engaged_actor: CreatureActor
var _engaged_arena: ArenaActor
var _staging: BattleStaging
var _active_relic: PlayerRelic


func setup(
	parent: Node3D,
	camera: IsoCamera,
	spawner: CreatureSpawner,
	roster: PlayerRoster,
	inventory: PlayerInventory,
	companion: CompanionActor,
	player: Node3D,
	progress: PlayerProgress,
	db: BestiaryData,
	mine_rng: RandomNumberGenerator,
	show_message: Callable,
	hide_world_hud: Callable,
	show_world_hud: Callable,
	clear_selection: Callable,
	update_hint: Callable,
	on_duel_changed: Callable,
) -> void:
	_parent = parent
	_camera = camera
	_spawner = spawner
	_roster = roster
	_inventory = inventory
	_companion = companion
	_player = player
	_progress = progress
	_db = db
	_mine_rng = mine_rng
	_show_message = show_message
	_hide_world_hud = hide_world_hud
	_show_world_hud = show_world_hud
	_clear_selection = clear_selection
	_update_hint = update_hint
	_on_duel_changed = on_duel_changed


func is_duel_open() -> bool:
	return _duel != null


## A encenação do duelo corrente, ou null fora dele. Público para os testes
## headless medirem a convergência sem depender do `_process` do motor.
func staging() -> BattleStaging:
	return _staging


func _set_duel(duel: DuelScreen) -> void:
	_duel = duel
	_on_duel_changed.call(duel)


func engage_wild(actor: CreatureActor, relic: PlayerRelic, encounter_level: int) -> void:
	if _duel != null:
		return  # já há um combate em curso

	# Time inteiro caído: não há com quem lutar. Abrir o duelo aqui daria uma
	# tela travada na substituição, sem ninguém para escolher. A saída é
	# esperar a recuperação — que é justamente o custo que o HP persistente
	# existe para cobrar.
	if _roster.alive_count() == 0:
		_clear_selection.call()
		actor.reset_engagement()
		_show_message.call("Nenhuma criatura de pe. Espere se recuperarem.")
		return

	_engaged_actor = actor
	_active_relic = relic
	_clear_selection.call()

	# O painel de identificação já tinha sido escondido pelo `clear_selection`.
	_hide_world_hud.call()

	var packed: PackedScene = load(DUEL_SCENE)
	var duel := packed.instantiate() as DuelScreen
	# O time inteiro entra, com o HP com que cada uma saiu do último combate.
	# `player_code` continua preenchido só como rede: se o time chegar vazio, a
	# tela ainda sabe com quem lutar.
	duel.player_code = _roster.active()
	duel.player_party = _roster.to_party()
	duel.player_active_index = _roster.active_index()
	# A mesma instância: capturar sobe o nível do relicário aqui embaixo, e a
	# tela de duelo precisa da taxa/elemento/classe atuais pra montar a ação.
	duel.relic = relic
	duel.enemy_code = actor.creature_code
	duel.duel_level = encounter_level
	duel.closed.connect(_on_duel_closed)
	_set_duel(duel)

	# CanvasLayer para o overlay ficar acima do 3D sem herdar a pausa do
	# mundo — a tela precisa continuar respondendo a tecla.
	var layer := CanvasLayer.new()
	layer.name = "DuelLayer"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(duel)
	_parent.add_child(layer)

	_begin_staging(actor)

	if _camera:
		_camera.enter_battle()
		# Vão entre a companheira e a selvagem no centro do quadro, não o
		# jogador — mesmo par que `_begin_staging` encena.
		if _companion and is_instance_valid(_companion):
			_camera.set_battle_focus(_companion, actor)
	# Congela exploração e IA; o overlay segue processando.
	_parent.get_tree().paused = true


## Engata o duelo de arena — mesmo corpo de `engage_wild`, sem as partes de
## spawner selvagem (não há ator para remover/repor no mapa: o duelista
## continua lá depois, refazer a arena é permitido). `is_wild = false`
## desliga captura em `Battle` (`battle.gd:_do_capture`); a vitória é lida em
## `_on_duel_closed`, que concede o Glifo.
func engage_arena(actor: ArenaActor, relic: PlayerRelic) -> void:
	if _duel != null:
		return  # já há um combate em curso

	if _roster.alive_count() == 0:
		_clear_selection.call()
		_show_message.call("Nenhuma criatura de pe. Espere se recuperarem.")
		return

	_engaged_arena = actor
	_active_relic = relic
	_clear_selection.call()
	_hide_world_hud.call()

	var packed: PackedScene = load(DUEL_SCENE)
	var duel := packed.instantiate() as DuelScreen
	duel.player_code = _roster.active()
	duel.player_party = _roster.to_party()
	duel.player_active_index = _roster.active_index()
	duel.relic = relic
	duel.enemy_code = actor.opponent_code
	duel.duel_level = actor.opponent_level
	duel.is_wild = false
	duel.closed.connect(_on_duel_closed)
	_set_duel(duel)

	var layer := CanvasLayer.new()
	layer.name = "DuelLayer"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(duel)
	_parent.add_child(layer)

	# Sem criatura selvagem para encenar contra — a arena não tem o
	# equivalente a `CreatureActor` no mundo, só o duelista parado. A
	# encenação segue com o par jogador/companheira igual, sem lado inimigo.
	_end_staging()

	if _camera:
		_camera.enter_battle()
		# O duelista de arena não anda: parado ali é o próprio "adversário
		# encenado", o mesmo papel que a selvagem cumpre em `engage_wild`.
		if _companion and is_instance_valid(_companion):
			_camera.set_battle_focus(_companion, actor)
	_parent.get_tree().paused = true


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
	_parent.add_child(_staging)


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
	_parent.get_tree().paused = false
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

	var layer := _parent.get_node_or_null("DuelLayer")
	if layer:
		layer.queue_free()
	_set_duel(null)

	# Vitória → sai do mapa com respawn agendado.
	# Captura → sai do mapa SEM respawn; código entra no time do jogador.
	# Derrota/fuga → criatura permanece no mapa para poder ser reengajada.
	if _engaged_actor and is_instance_valid(_engaged_actor):
		if outcome == Battle.Outcome.PLAYER_WON:
			_spawner.remove_actor(_engaged_actor)
			# Uma mensagem só: `_show_message` substitui a anterior na hora, e
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
				_show_message.call("   ·   ".join(parts))
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
				_show_message.call("Time cheio (%d/%d) — a captura escapou."
					% [_roster.size(), _roster.capacity()])
		else:
			_engaged_actor.reset_engagement()
	elif _engaged_arena:
		# Sem ator de spawner para repor/remover — o duelista fica no mapa
		# vencendo ou perdendo. `grant_glyph` devolve `false` num refight
		# depois de já ter o Glifo, então isto não reanuncia nem duplica.
		if outcome == Battle.Outcome.PLAYER_WON and _progress:
			if _progress.grant_glyph(_engaged_arena.grants_glyph):
				_show_message.call("Glifo %s obtido." % _engaged_arena.grants_glyph.capitalize())
	_engaged_actor = null
	_engaged_arena = null
	_active_relic = null

	if outcome == Battle.Outcome.PLAYER_LOST:
		_show_message.call("Seu time caiu. Recuperando %d%% por minuto."
			% int(PlayerRoster.REGEN_FRACTION_PER_MINUTE * 100.0))

	_show_world_hud.call()
	# `_update_hint` também dispara via `population_changed` do spawner quando
	# a remoção ocorre, mas chamar aqui garante o texto certo mesmo nos
	# desfechos que não mexem na população.
	_update_hint.call()


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
	if _active_relic == null or _db == null or _inventory == null:
		return
	var result := _active_relic.grant_capture_xp(_db, _inventory)
	if result["leveled_up"]:
		_show_message.call("%s subiu para o nivel %d!"
			% [_active_relic.display_name(_db), int(result["new_level"])])
	elif result["waiting_material"]:
		_show_message.call("%s: XP cheio, falta %s."
			% [_active_relic.display_name(_db), _db.item_name(_active_relic.material_item_code(_db))])


func _creature_name(code: String) -> String:
	if _db == null or code == "":
		return code
	return str(_db.creature(code).get("name", code))
