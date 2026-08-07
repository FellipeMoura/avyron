extends SceneTree

## Prova o loop de encontro: as criaturas nascem no mapa, o jogador anda até
## uma, o combate começa in-world e o mundo volta ao normal ao fim.
##
##     godot --headless --script res://scripts/dev/test_encounter.gd

const MAX_FRAMES := 3000

var _world: Node3D
var _spawner: CreatureSpawner
var _player: CharacterBody3D
var _target: CreatureActor
var _frames := 0
var _phase := "spawn"
var _failures := 0
var _checks := 0
var _size_min := 99.0
var _size_max := 0.0


func _initialize() -> void:
	_world = load("res://scenes/main.tscn").instantiate()
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
			_phase = "walk"
		"walk":
			_walk_to_target()
		"battle":
			_check_battle()
		"done":
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

	# Nenhuma pode nascer em cima do jogador, senão o jogo abre em combate.
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


## Move o jogador pela posição, não pela velocidade.
##
## O `PlayerController` reescreve a velocidade a cada quadro de física a
## partir do input, então escrevê-la aqui não sobrevive ao quadro seguinte —
## o corpo freava no lugar. Que a caminhada por input funciona já é assunto
## do `test_playable`; o que está sendo verificado aqui é a proximidade
## disparar o encontro.
func _walk_to_target() -> void:
	if _target == null or not is_instance_valid(_target):
		_phase = "done"
		return

	var to := _target.global_position - _player.global_position
	to.y = 0.0
	if _world.get("_duel") != null:
		print("encontro:")
		_check_true("o combate comecou ao encostar", true,
			"a %.1f m de %s" % [to.length(), _target.display_name])
		_phase = "battle"
		return

	var step := minf(0.15, to.length())
	_player.global_position += to.normalized() * step


func _check_battle() -> void:
	var duel: DuelScreen = _world.get("_duel")
	_check_true("o mundo congelou", root.get_tree().paused)
	_check_true("o adversario e a criatura encostada",
		duel.battle.enemy.code == _target.creature_code,
		"%s" % duel.battle.enemy.display_name)
	_check_true("o jogador entrou com a criatura inicial",
		duel.battle.player_active().code == _world.starter_code)
	_check_true("a tela do duelo esta acima do mundo",
		_world.get_node_or_null("DuelLayer") != null)

	# Fecha o duelo e verifica que o mundo volta.
	duel.closed.emit(duel.battle.outcome)
	_phase = "done"


func _finish() -> void:
	_check_true("o mundo descongelou", not root.get_tree().paused)
	_check_true("o overlay saiu de cena", _world.get("_duel") == null)

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
