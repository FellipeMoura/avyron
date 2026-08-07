extends SceneTree

## Prova o loop de encontro por clique: as criaturas nascem, o primeiro clique
## seleciona (destaque + painel de identificação), o segundo clique na mesma
## criatura inicia o combate in-world, e o mundo volta ao normal ao fim.
##
##     godot --headless --script res://scripts/dev/test_encounter.gd

const MAX_FRAMES := 3000

var _world: WorldRoot
var _spawner: CreatureSpawner
var _player: CharacterBody3D
var _target: CreatureActor
var _frames := 0
var _phase := "spawn"
var _failures := 0
var _checks := 0
var _size_min := 99.0
var _size_max := 0.0
var _actors_before_close := 0
var _post_close_wait := 0
var _target2: CreatureActor
var _target2_code := ""
var _actors_before_capture := 0
var _post_capture_wait := 0


func _initialize() -> void:
	_world = load("res://scenes/main.tscn").instantiate() as WorldRoot
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	# Buscados aqui, não em _initialize: o spawner é criado dentro do _ready
	# da raiz do mundo, e consultar cedo demais devolve null.
	if _spawner == null:
		_spawner = _world.get_node_or_null("CreatureSpawner")
		_player = _world.get_node_or_null("Player")
		if _spawner == null or _player == null:
			_check_true("mundo montado (spawner e jogador)", false,
				"spawner=%s player=%s" % [str(_spawner), str(_player)])
			_finish()
			return true

	match _phase:
		"spawn":
			_check_spawn()
			_phase = "first_click"
		"first_click":
			_do_first_click()
			_phase = "second_click"
		"second_click":
			_do_second_click()
		"battle":
			_check_battle()
		"post_close":
			# Espera um par de quadros para o `queue_free` do actor processar
			# antes de contar. Sem essa folga a asserção corre à frente da
			# limpeza que o Godot só executa no fim do quadro.
			_post_close_wait += 1
			if _post_close_wait >= 3:
				_check_removal()
				_phase = "done"
		"done":
			_check_true("o mundo descongelou apos vitoria", not root.get_tree().paused)
			_check_true("o overlay saiu apos vitoria", _world.get("_duel") == null)
			_pick_target2()
			_phase = "capture_first_click" if _target2 != null else "finish"
		"capture_first_click":
			_do_capture_first_click()
			_phase = "capture_second_click"
		"capture_second_click":
			_do_capture_second_click()
		"capture_battle":
			_check_capture_battle()
		"post_capture":
			_post_capture_wait += 1
			if _post_capture_wait >= 3:
				_check_capture_result()
				_phase = "finish"
		"finish":
			_finish()
			return true

	if _frames > MAX_FRAMES:
		_check_true("o teste terminou dentro do limite", false,
			"travou na fase '%s' apos %d quadros" % [_phase, _frames])
		_finish()
		return true
	return false


func _check_spawn() -> void:
	print("povoamento:")
	var actors := _spawner.actors()
	_check_true("nasceram criaturas", actors.size() > 0, "%d no mapa" % actors.size())

	var codes := {}
	for a in actors:
		codes[a.creature_code] = true
		_size_min = minf(_size_min, a.size_meters)
		_size_max = maxf(_size_max, a.size_meters)
		_check_true_quiet("%s tem tamanho valido" % a.creature_code,
			a.size_meters >= 0.9 and a.size_meters <= 4.5)
	_check_true("as escalas variam", _size_max > _size_min,
		"de %.2f m a %.2f m" % [_size_min, _size_max])
	_check_true("ha mais de uma especie", codes.size() > 1, "%d especies" % codes.size())

	# Nenhuma pode nascer em cima do jogador — no modelo antigo isso abria o
	# jogo em combate; agora não abre mais, mas segue sendo um cheiro ruim.
	var too_close := 0
	for a in actors:
		if a.global_position.distance_to(_player.global_position) < 5.0:
			too_close += 1
	_check("nenhuma nasce em cima do jogador", too_close, 0)

	# Escolhe a mais próxima como alvo do teste.
	var best := 1e9
	for a in actors:
		var d: float = a.global_position.distance_to(_player.global_position)
		if d < best:
			best = d
			_target = a
	print("  alvo: %s (%s) a %.1f m" % [_target.display_name, _target.creature_code, best])


## Primeiro clique: sem batalha; a criatura deve ficar marcada como selecionada
## e o painel de identificação deve estar visível.
##
## Chama o entry point público em vez de sintetizar `InputEventMouseButton` —
## coordenadas de tela em headless dependem da câmera renderizando, o que não
## acontece nesse modo. Testar pela API é o contrato do WorldRoot.
func _do_first_click() -> void:
	print("primeiro clique:")
	_world.handle_click_on(_target)

	_check_true("o alvo ficou selecionado", _target.is_selected())
	_check_true("o WorldRoot conhece a selecao", _world.selected_actor() == _target)
	_check_true("nenhum combate comecou no 1o clique",
		_world.get_node_or_null("DuelLayer") == null)

	var info: CreatureInfoPanel = _world.get_node_or_null("HudLayer/CreatureInfoPanel")
	_check_true("o painel de identificacao apareceu", info != null and info.visible)


## Segundo clique na mesma criatura: dispara o combate.
func _do_second_click() -> void:
	print("segundo clique:")
	_world.handle_click_on(_target)

	_check_true("a selecao foi limpa ao engatar", _world.selected_actor() == null)
	_check_true("o combate comecou", _world.get_node_or_null("DuelLayer") != null,
		"a %s" % _target.display_name)
	_phase = "battle"


func _check_battle() -> void:
	var duel: DuelScreen = _world.get("_duel")
	_check_true("o mundo congelou", root.get_tree().paused)
	_check_true("o adversario e a criatura clicada",
		duel.battle.enemy.code == _target.creature_code,
		"%s" % duel.battle.enemy.display_name)
	_check_true("o jogador entrou com a criatura inicial",
		duel.battle.player_active().code == _world.starter_code)
	_check_true("a tela do duelo esta acima do mundo",
		_world.get_node_or_null("DuelLayer") != null)

	# Força vitória do jogador antes de fechar — o outcome real deste teste é
	# indeterminado (nenhum turno foi jogado), e o fluxo que queremos exercer
	# é a remoção da criatura do mapa pós-vitória.
	_actors_before_close = _spawner.actors().size()
	duel.battle.outcome = Battle.Outcome.PLAYER_WON
	duel.closed.emit(duel.battle.outcome)
	_phase = "post_close"


## Após vitória do jogador, a criatura sai do mapa e um slot de respawn entra
## na fila. Sem isso, ganhar batalha deixava o mesmo bicho parado no mesmo
## lugar — o playtest ficava estranho porque a mesma vitória "não valia".
func _check_removal() -> void:
	print("pos-vitoria:")
	_check_true("a criatura derrotada saiu do mapa",
		_spawner.actors().size() == _actors_before_close - 1,
		"%d → %d" % [_actors_before_close, _spawner.actors().size()])
	_check_true("o slot dela virou respawn pendente",
		_spawner.pending_respawns() == 1,
		"%d pendentes" % _spawner.pending_respawns())


## Segundo alvo: a criatura mais próxima do jogador que ainda está no mapa
## depois de a primeira ter sido derrotada.
func _pick_target2() -> void:
	_target2 = null
	var best := 1e9
	for a in _spawner.actors():
		var d: float = a.global_position.distance_to(_player.global_position)
		if d < best:
			best = d
			_target2 = a
	if _target2:
		print("captura: alvo %s (%s) a %.1f m"
			% [_target2.display_name, _target2.creature_code, best])
	else:
		print("captura: nenhum alvo disponivel, pulando fase")


func _do_capture_first_click() -> void:
	print("captura - primeiro clique:")
	_world.handle_click_on(_target2)
	_check_true("alvo2 ficou selecionado", _target2.is_selected())


func _do_capture_second_click() -> void:
	print("captura - segundo clique:")
	_world.handle_click_on(_target2)
	_check_true("combate comecou para captura",
		_world.get_node_or_null("DuelLayer") != null)
	_phase = "capture_battle"


func _check_capture_battle() -> void:
	var duel: DuelScreen = _world.get("_duel")
	_check_true("mundo congelou para captura", root.get_tree().paused)
	_actors_before_capture = _spawner.actors().size()
	# Salva o código antes de emitir closed — depois de queue_free o actor
	# não pode mais ser acessado com segurança.
	_target2_code = _target2.creature_code
	duel.battle.outcome = Battle.Outcome.CAPTURED
	duel.closed.emit(duel.battle.outcome)
	_phase = "post_capture"


func _check_capture_result() -> void:
	print("pos-captura:")
	_check_true("criatura capturada saiu do mapa",
		_spawner.actors().size() == _actors_before_capture - 1,
		"%d → %d" % [_actors_before_capture, _spawner.actors().size()])
	# Captura não agenda respawn — a criatura foi ao time, não voltou ao bioma.
	# Ainda há 1 pendente da vitória anterior, mas nenhum novo foi adicionado.
	_check_true("captura nao agendou respawn",
		_spawner.pending_respawns() == 1,
		"%d pendentes" % _spawner.pending_respawns())
	var player_team := _world.team()
	_check_true("criatura entrou no time",
		player_team.size() == 1 and player_team[0] == _target2_code,
		"time: %s" % str(player_team))
	_check_true("o mundo descongelou apos captura", not root.get_tree().paused)
	_check_true("o overlay saiu apos captura", _world.get("_duel") == null)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	_checks += 1
	if actual == expected:
		print("  ok   %s = %s" % [label, str(actual)])
	else:
		_failures += 1
		printerr("  FAIL %s = %s (esperado %s)" % [label, str(actual), str(expected)])


func _check_true(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s%s" % [label, (" — " + detail) if detail != "" else ""])
	else:
		_failures += 1
		printerr("  FAIL %s%s" % [label, (" — " + detail) if detail != "" else ""])


## Para asserções repetidas por criatura: só reporta quando falha, senão o
## log vira uma parede de linhas idênticas.
func _check_true_quiet(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("  FAIL %s" % label)
