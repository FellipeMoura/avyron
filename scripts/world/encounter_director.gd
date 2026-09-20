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

## Relevo do mapa, repassado à encenação para ela apoiar os corpos no chão e
## respeitar a borda. Atribuído por `WorldRoot` depois do `setup`, como já
## acontece com `CreatureSpawner.terrain` e `CompanionActor.terrain` — fora do
## `setup` porque é a única dependência que pode legitimamente faltar (bancada
## de teste sem mundo), e enfiá-la numa lista de dezesseis parâmetros
## obrigatórios só esconderia isso.
var terrain: MapTerrain

## O set do domador (Amplificador/Encantador), injetado depois do `setup`
## pela mesma razão de `terrain`: a lista já tem dezesseis parâmetros
## obrigatórios, e este pode legitimamente faltar numa bancada de teste sem
## mundo. Ao contrário do relicário — que `engage_*` recebe por parâmetro
## porque o posto o **substitui** por outra instância —, o loadout é sempre o
## mesmo objeto: ele muda por dentro, então uma referência guardada aqui
## nunca fica velha.
var loadout: PlayerLoadout

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

## Compasso de cada categoria de evento animado — quanto tempo `_animate_round_events`
## espera antes do próximo, e por extensão quanto o turno inteiro atrasa o
## texto/HP (decisão do usuário: esperar a animação, não texto instantâneo em
## paralelo). Reusa os MESMOS números do VFX (`ElementPalette.BATTLE_*_LIFETIME`)
## pra golpe/status — corpo e partícula terminam juntos, de propósito. Só
## `DEATH_BEAT` é novo: não existe VFX de desmaio, então não há lifetime
## nenhum pra herdar. `ATTACK3_ENTER_BEAT`/`ATTACK3_EXIT_BEAT` também são
## novos, só pro combo de `Attack3` (`Cast_Enter`→`Cast`→`Cast_Exit`): o
## meio do combo já reusa `BATTLE_ATTACK_LIFETIME`, mas entrada e saída não
## têm VFX equivalente pra herdar tempo.
const DEATH_BEAT := 0.9

## Teto de espera por perna da investida, em segundos. A corrida é da
## `BattleStaging` e normalmente leva ~0,6 s; isto só existe pra um turno
## nunca ficar preso esperando um corpo que não consegue chegar.
const CHARGE_TIMEOUT := 3.0
const ATTACK3_ENTER_BEAT := 0.35
const ATTACK3_EXIT_BEAT := 0.35


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
	duel.loadout = loadout
	duel.enemy_code = actor.creature_code
	duel.duel_level = encounter_level
	duel.closed.connect(_on_duel_closed)
	duel.rendered.connect(_sync_awakening_auras)
	# `_play_battle_effects` reativo (ligado a `rendered`) foi substituído por
	# isto: `DuelScreen` agora ESPERA a animação antes de renderizar (decisão
	# do usuário — texto/HP só depois do golpe tocar), então quem decide a
	# ordem é ela, chamando isto com `await` ANTES do `_render()`, não depois.
	duel.animate_round = Callable(self, "_animate_round_events")
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
	duel.loadout = loadout
	duel.enemy_code = actor.opponent_code
	duel.duel_level = actor.opponent_level
	duel.is_wild = false
	duel.closed.connect(_on_duel_closed)
	duel.rendered.connect(_sync_awakening_auras)
	# `_play_battle_effects` reativo (ligado a `rendered`) foi substituído por
	# isto: `DuelScreen` agora ESPERA a animação antes de renderizar (decisão
	# do usuário — texto/HP só depois do golpe tocar), então quem decide a
	# ordem é ela, chamando isto com `await` ANTES do `_render()`, não depois.
	duel.animate_round = Callable(self, "_animate_round_events")
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
	_staging.terrain = terrain

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


## Espelha nos corpos 3D quem está em Despertar Ancestral. Ligado ao sinal
## `rendered` da tela, que dispara a cada mudança de estado da batalha.
##
## O estado é LIDO da batalha, não acumulado a partir dos eventos do log. É a
## diferença entre um espelho e uma máquina de estados paralela: despertar,
## reverter por tempo, cair em combate e trocar de criatura são quatro
## caminhos que apagam a aura, e reagir a evento exigiria acertar os quatro.
## `set_awakening_aura` já ignora chamada repetida, então reespelhar todo
## quadro de turno não custa nada.
##
## Chamado por NOME, como o resto do contrato de corpo movido de fora — a
## bancada de `Node3D` solto das suítes não precisa implementar a aura para
## ser encenada.
##
## O lado inimigo pode não ter corpo: numa arena o adversário é um duelista
## parado, sem `CreatureActor` equivalente no mundo (ver `engage_arena`). Aí
## só o lado do jogador acende, e é o comportamento certo — inventar um corpo
## para pendurar a aura seria pior que não mostrá-la.
func _sync_awakening_auras() -> void:
	if _duel == null or _duel.battle == null:
		return
	var hero: Combatant = _duel.battle.player_active()
	if hero != null:
		_set_body_aura(_companion, hero.is_awakened)
	if _duel.battle.enemy != null:
		_set_body_aura(_engaged_actor, _duel.battle.enemy.is_awakened)


func _set_body_aura(body: Node, active: bool) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("set_awakening_aura"):
		body.call("set_awakening_aura", active)


## Toca a sequência ANIMADA de uma rodada — chamada por `DuelScreen` (com
## `await`) DEPOIS de `battle.resolve_round` e ANTES do próprio `_render()`,
## porque o usuário escolheu esperar a animação: texto e HP só aparecem
## quando o golpe já tocou, não em paralelo com ele.
##
## Tranca a marcha dos dois lados no `BattleStaging` (se houver — arena não
## tem encenação do lado inimigo) ANTES do primeiro evento e destranca DEPOIS
## do último, sempre no início/fim da RODADA e nunca por evento: destrancar
## entre "HitReact" e "Death" do mesmo corpo deixaria a encenação puxar um
## quadro de `Idle` por cima bem no meio da sequência. Quem desmaiou fica
## trancado — ver `_release_gait`.
func _animate_round_events(events: Array) -> void:
	if _duel == null or _duel.battle == null:
		return
	_lock_gait(_companion, true)
	_lock_gait(_engaged_actor, true)
	for event in events:
		await _animate_one_event(_duel.battle, event as Dictionary)
	_release_gait_if_alive(true, _duel.battle)
	_release_gait_if_alive(false, _duel.battle)


func _lock_gait(body: Node3D, locked: bool) -> void:
	if _staging != null and is_instance_valid(_staging) and body != null and is_instance_valid(body):
		_staging.lock_gait(body, locked)


## Destranca só quem SEGUE vivo — o lado que desmaiou fica preso na pose de
## `Death` até o duelo fechar (a encenação inteira morre junto, então nunca
## sobra destrancado no mapa). `is_player` aqui identifica o LADO do jogador,
## não o evento — por isso o parâmetro chama diferente do resto do arquivo.
func _release_gait_if_alive(is_player_side: bool, battle: Battle) -> void:
	var combatant: Combatant = battle.player_active() if is_player_side else battle.enemy
	if combatant != null and combatant.is_fainted():
		return
	_lock_gait(_companion if is_player_side else _engaged_actor, false)


## Um evento: efeito visual (`_dispatch_battle_effect`, já existia) MAIS
## clipe de corpo — a peça que faltava pra alguma coisa acontecer com a
## criatura em si, não só com a partícula do lado dela. `await` no fim é o
## compasso: cada evento tem seu tempo antes do próximo, e é essa espera que
## o `await` de `DuelScreen` acaba herdando por inteiro.
##
## `is_player` no evento (não `actor.code`) decide o lado — ver o comentário
## de `Battle._log` sobre por que código não basta (duelo espécie-contra-a-
## mesma-espécie tem o mesmo código dos dois lados).
##
## Dano recolore pelo elemento da HABILIDADE, não de quem a usa — golpes
## utilitários sem elemento (`ability_element` vazio) caem no elemento de
## quem usou como fallback, pra nunca sair cinza de engenharia. Status
## (buff/debuff/heal/charge) não tem elemento próprio no catálogo — usa
## sempre o de quem usou, mesmo quando aplicado no oponente (debuff).
##
## Só dano/miss mexem no CORPO (`Attack`/`Attack2`/`Attack3`/`HitReact`/
## `Dodge`/`Death`) — status (buff/debuff/heal/charge) continua só efeito
## visual, sem clipe: não existe gesto de "usar golpe de suporte" no
## vocabulário das criaturas. Qual das três variantes de ataque toca vem do
## bestiário (`ability.attackVariant`, ver `_attack_clip_for`) — decisão de
## conteúdo, não sorteio nem categoria hardcoded aqui.
func _animate_one_event(battle: Battle, event: Dictionary) -> void:
	var is_player := bool(event.get("is_player", false))
	var type := str(event.get("type", ""))
	var actor: Combatant = battle.player_active() if is_player else battle.enemy
	var actor_code := actor.code if actor != null else ""

	match type:
		"damage":
			var ability_code := str(event.get("ability", ""))
			var ability := actor.ability_by_code(ability_code) if actor != null else {}
			var element_code := BestiaryData.ability_element(ability)
			if element_code == "" and actor != null:
				element_code = actor.element
			var variant := _attack_clip_for(ability)
			if variant == "Attack3":
				# Golpe do Despertar: o impacto É o feixe (a bola e as faíscas
				# da ponta dele). O swing/claw do corpo a corpo não entra —
				# um corte de garra no fim de um raio contaria duas histórias.
				await _play_attack3_sequence(is_player, true, element_code)
			else:
				# Curta distância: corre, e o efeito só nasce no CONTATO —
				# disparado antes, a partícula estouraria no alvo com o
				# atacante ainda do outro lado do vão.
				var charged := await _charge_out(is_player)
				if variant == "Attack2":
					# Golpe ELEMENTAR: o mesmo corte do básico, mas na cor do
					# elemento, mais o estouro de impacto. O básico (`Attack`)
					# segue com o corte neutro e sem estouro — é a diferença
					# visível entre os dois golpes de curta distância.
					_dispatch_battle_effect(not is_player, "damage_elemental", element_code, ability_code, actor_code)
					_dispatch_battle_effect(not is_player, "impact", element_code, ability_code, actor_code)
				else:
					_dispatch_battle_effect(not is_player, "damage", element_code, ability_code, actor_code)
				_play_body_clip(is_player, variant)
				_play_body_clip(not is_player, "HitReact")
				await _wait(ElementPalette.BATTLE_ATTACK_LIFETIME)
				if charged:
					_rest_body(not is_player)
					await _charge_back()
		"miss":
			# Golpe saiu, o alvo escapa dele — `Dodge` é de quem apanharia,
			# nunca de quem atacou.
			var ability_code := str(event.get("ability", ""))
			var ability := actor.ability_by_code(ability_code) if actor != null else {}
			var variant := _attack_clip_for(ability)
			if variant == "Attack3":
				var miss_element := BestiaryData.ability_element(ability)
				if miss_element == "" and actor != null:
					miss_element = actor.element
				await _play_attack3_sequence(is_player, false, miss_element)
				_play_body_clip(not is_player, "Dodge")
				await _wait(ElementPalette.BATTLE_ATTACK_LIFETIME)
			else:
				# Errar também custa a corrida: o golpe saiu, só não pegou.
				var charged := await _charge_out(is_player)
				_play_body_clip(is_player, variant)
				_play_body_clip(not is_player, "Dodge")
				await _wait(ElementPalette.BATTLE_ATTACK_LIFETIME)
				if charged:
					_rest_body(not is_player)
					await _charge_back()
		"capture_failed":
			# `Battle._do_capture` loga este evento com `actor` = a própria
			# criatura selvagem (não quem tentou capturar) — `is_player` já é
			# o lado de quem escapou, direto, mesmo padrão de `"faint"`.
			_play_body_clip(is_player, "Dodge")
			await _wait(ElementPalette.BATTLE_ATTACK_LIFETIME)
		"buff", "heal", "charge":
			_dispatch_battle_effect(is_player, type, actor.element if actor != null else "", "", actor_code)
			await _wait(ElementPalette.BATTLE_CHARGE_LIFETIME if type == "charge" else ElementPalette.BATTLE_STATUS_LIFETIME)
		"debuff":
			_dispatch_battle_effect(not is_player, type, actor.element if actor != null else "", "", actor_code)
			await _wait(ElementPalette.BATTLE_STATUS_LIFETIME)
		"faint":
			# `is_player` aqui já é o lado de QUEM DESMAIOU — `Battle._log`
			# grava o evento com `actor` = o próprio combatente caído.
			_play_body_clip(is_player, "Death")
			await _wait(DEATH_BEAT)


## Investida do golpe de curta distância: manda o corpo do lado que AGIU
## correr até o adversário e espera o contato. Quem anda o corpo é a
## `BattleStaging` (dona única da posição em duelo — ver "A investida" lá);
## aqui só se pede e se espera. Devolve `false` quando não houve corrida — sem
## encenação (bancada de teste), corpo ausente — e o turno segue do posto,
## como era antes de 2026-09-18.
##
## Quais golpes investem sai do dado: `attackVariant` `attack` (básico) e
## `attack2` (elementar) são corpo a corpo; `attack3` (Despertar) é
## conjuração à distância e não passa por aqui.
func _charge_out(player_side: bool) -> bool:
	var body: Node3D = _companion if player_side else _engaged_actor
	if _staging == null or not is_instance_valid(_staging) or body == null or not is_instance_valid(body):
		return false
	if not _staging.charge(body):
		return false
	await _until_charge_leaves(BattleStaging.ChargePhase.OUT)
	return _staging != null and is_instance_valid(_staging) \
		and _staging.charge_phase() == BattleStaging.ChargePhase.HOLD


## Devolve um corpo ao repouso da própria escada de marcha (`Idle`, ou
## `Swim_Idle` submerso) — por NOME, como o resto do contrato de encenação.
##
## Existe por causa da retirada: `HitReact`/`Dodge` são mais curtos que o
## compasso do golpe e terminam sozinhos, e um `AnimationPlayer` que chega ao
## fim só para de escrever — o corpo fica no último quadro. Antes da investida
## isso durava um instante (a marcha destrancava logo em seguida); com a volta
## do atacante no meio, quem apanhou ficaria meio segundo congelado de
## guarda torta vendo o outro correr. A marcha segue trancada: isto é um
## pedido único, não a encenação retomando o corpo.
func _rest_body(player_side: bool) -> void:
	var body: Node = _companion if player_side else _engaged_actor
	if body != null and is_instance_valid(body) and body.has_method("staged_gait"):
		body.call("staged_gait", 0.0)


func _charge_back() -> void:
	if _staging == null or not is_instance_valid(_staging):
		return
	_staging.retreat()
	await _until_charge_leaves(BattleStaging.ChargePhase.BACK)
	# A meia-volta no posto ainda é investida: seguir antes dela acabar faria
	# o `charge()` do contra-ataque ser recusado (uma por vez), e o adversário
	# golpearia do posto, sem correr.
	await _until_charge_leaves(BattleStaging.ChargePhase.TURN)


## Espera quadro a quadro, e não pelos sinais da encenação, de propósito: o
## duelo pode fechar no meio da corrida (ESC continua saindo durante a
## resolução do turno) e a encenação morre junto — um `await` num sinal de nó
## liberado não retoma nunca, e o turno ficaria preso com as teclas travadas.
func _until_charge_leaves(phase: BattleStaging.ChargePhase) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	var deadline := Time.get_ticks_msec() + int(CHARGE_TIMEOUT * 1000.0)
	while _staging != null and is_instance_valid(_staging) and _staging.charge_phase() == phase:
		if Time.get_ticks_msec() > deadline:
			return
		await loop.process_frame


## `Engine.get_main_loop()`, não `_parent.get_tree()`: uma bancada de teste
## pode montar o `EncounterDirector` sem `setup()` nenhum (só os campos que o
## próprio teste precisa, via reflexão), e `_parent` ficaria null nesse caso.
func _wait(seconds: float) -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		await (loop as SceneTree).create_timer(seconds).timeout


## Feixe do lado que AGIU até o corpo do lado oposto — por nome, como o resto.
func _dispatch_battle_beam(player_side: bool, element_code: String, duration: float) -> void:
	var source: Node = _companion if player_side else _engaged_actor
	var target: Node = _engaged_actor if player_side else _companion
	if source == null or not is_instance_valid(source) or target == null or not is_instance_valid(target):
		return
	if source.has_method("play_battle_beam"):
		source.call("play_battle_beam", target, element_code, duration)


## `player_side` true = companheira, false = criatura selvagem/duelista —
## mesmo mapeamento de `_set_body_aura`. `source_creature_code` é sempre quem
## AGIU, não o corpo que recebe a chamada — nem sempre são o mesmo (debuff:
## quem "é dono" da cor é o atacante, quem recebe o efeito visual é o alvo).
func _dispatch_battle_effect(
	player_side: bool, kind: String, element_code: String, variant_seed: String, source_creature_code: String,
) -> void:
	var body: Node = _companion if player_side else _engaged_actor
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("play_battle_effect"):
		body.call("play_battle_effect", kind, element_code, variant_seed, source_creature_code)


## Mesmo mapeamento de `_dispatch_battle_effect`, só que pro clipe do CORPO
## em vez do VFX. `player_side` aqui é sempre "de quem é o corpo que deve
## animar" — quem chama já decidiu isso (`is_player` pra quem golpeou, `not
## is_player` pra quem apanhou).
func _play_body_clip(player_side: bool, clip: String) -> void:
	var body: Node = _companion if player_side else _engaged_actor
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("play_battle_clip"):
		body.call("play_battle_clip", clip)


## Qual clipe de ataque uma habilidade toca — dado do bestiário
## (`ability_stats.attack_variant`, exportado como `attackVariant`), nunca
## sorteio nem categoria hardcoded aqui. Valor ausente ou desconhecido cai em
## `"Attack"`, mesmo padrão de fallback silencioso de `BestiaryData.
## ability_element`.
func _attack_clip_for(ability: Dictionary) -> String:
	match str(ability.get("attackVariant", "attack")):
		"attack2":
			return "Attack2"
		"attack3":
			return "Attack3"
		_:
			return "Attack"


## `Attack3` não é mais um clipe único no vocabulário — é a encenação de três
## clipes já existentes na UAL (`Cast_Enter`/`Cast`/`Cast_Exit`, vindos de
## Spell_Simple_Enter/Shoot/Exit). `hit_target` decide se o alvo reage no
## meio da sequência (dano) ou não (miss) — o "Shoot" é o instante do
## impacto, por isso o `HitReact` do lado oposto entra ali, não no fim.
##
## Desde 2026-09-18 o "Shoot" dispara o FEIXE de energia na cor do elemento
## (`ElementPalette.play_battle_beam`), que vive exatamente o compasso do
## `Cast`. O alvo só reage depois de `BATTLE_BEAM_OPEN_TIME` — o tempo do
## feixe atravessar o vão; reagir no quadro do disparo leria como o alvo
## apanhando de um raio que ainda não chegou. No erro o feixe sai do mesmo
## jeito: o golpe foi dado, só não pegou.
func _play_attack3_sequence(is_player: bool, hit_target: bool, element_code: String = "") -> void:
	_play_body_clip(is_player, "Cast_Enter")
	await _wait(ATTACK3_ENTER_BEAT)
	_play_body_clip(is_player, "Cast")
	_dispatch_battle_beam(is_player, element_code, ElementPalette.BATTLE_ATTACK_LIFETIME)
	await _wait(ElementPalette.BATTLE_BEAM_OPEN_TIME)
	if hit_target:
		_play_body_clip(not is_player, "HitReact")
	await _wait(ElementPalette.BATTLE_ATTACK_LIFETIME - ElementPalette.BATTLE_BEAM_OPEN_TIME)
	_play_body_clip(is_player, "Cast_Exit")
	await _wait(ATTACK3_EXIT_BEAT)


func _on_duel_closed(outcome: int) -> void:
	_parent.get_tree().paused = false
	# A encenação sai antes de o mundo voltar a andar. Deixá-la viva um quadro
	# a mais poria a perseguição da criatura e a trilha da companheira
	# disputando o mesmo `global_position` com ela.
	_end_staging()
	# A aura é do duelo. Apagar os dois lados aqui, e não confiar no caminho de
	# cada desfecho, é o que garante que ninguém volte ao mapa aceso: a
	# selvagem tem `reset_engagement`, mas só na derrota e na fuga — e a
	# companheira não tem caminho nenhum.
	_set_body_aura(_companion, false)
	_set_body_aura(_engaged_actor, false)
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

	# Vitória e captura → o corpo sai do mapa. Desde que o povoamento virou
	# local ao jogador (2026-09-06) as duas são a MESMA operação para o
	# spawner: não há mais respawn agendado por morte, quem repõe é o
	# deslocamento do jogador. O que ainda as separa é o que acontece do lado
	# de cá — a captura entra no time, a vitória distribui XP e drop.
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
				_spawner.remove_actor(_engaged_actor)
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
		# depois de já ter o Glifo, então isto não reanuncia nem duplica —
		# e devolve `false` também para código vazio, que é o caso NORMAL de
		# arena intermediária: só a última de uma era concede Glifo.
		if outcome == Battle.Outcome.PLAYER_WON and _progress:
			if _progress.grant_glyph(_engaged_arena.grants_glyph):
				# O save guarda o código; quem aparece na tela é o nome do
				# catálogo. `capitalize()` sobre o código daria "Glf 001".
				var glyph_label := _engaged_arena.grants_glyph
				if _db:
					glyph_label = _db.glyph_name(_engaged_arena.grants_glyph)
				_show_message.call("Glifo %s obtido." % glyph_label)
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
			# A mesma frase da janela do time — com a QUANTIDADE que falta, que
			# é o item 5 do documento `progressao`: "faltam 2 unidades" é a
			# mensagem útil, "não pode subir" não é.
			line += " (%s)" % ProgressText.status_plain(_db, _roster.progress_at(idx), _inventory)
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
	elif result["waiting_material"] and str(result["material"]) != "":
		# Relicário sem classe (o starter) trava com a barra cheia de
		# propósito e não tem material que destrave — avisar "falta ." a cada
		# captura, como acontecia, era pedir um item que não existe. A janela
		# do set é quem explica esse estado; aqui só o que tem solução.
		_show_message.call("%s: %s." % [
			_active_relic.display_name(_db),
			ProgressText.status_plain(_db, _active_relic.progress(_db), _inventory, "captura")])


func _creature_name(code: String) -> String:
	if _db == null or code == "":
		return code
	return str(_db.creature(code).get("name", code))
