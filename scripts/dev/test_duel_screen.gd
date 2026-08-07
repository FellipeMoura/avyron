extends SceneTree

## Joga um duelo pela própria tela, batendo tecla, e verifica que a interface
## reage.
##
##     godot --headless --script res://scripts/dev/test_duel_screen.gd
##
## Sem isto, um erro de digitação no `_render` só apareceria com o jogo aberto
## — e o ponto da tela de duelo é justamente conseguir avaliar o combate
## rápido, sem abrir nada.

const MAX_ROUNDS := 40

var _screen: DuelScreen
var _frames := 0
var _failures := 0
var _checks := 0
var _rounds_played := 0
var _saw_awakening := false
var _text_before := ""


func _initialize() -> void:
	_screen = load("res://scenes/duel.tscn").instantiate()
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	if _frames == 3:
		_check_true("a tela renderizou", _screen_text().length() > 200,
			"%d caracteres" % _screen_text().length())
		_check_true("mostra os dois combatentes",
			_screen_text().contains("adversario") and _screen_text().contains("voce"))
		_check_true("mostra a versao dos dados", _screen_text().contains(_db().data_version))
		return false

	if _screen.battle.is_over() or _rounds_played >= MAX_ROUNDS:
		_finish()
		return true

	# Desperta assim que der, para exercitar esse caminho da interface.
	if _screen.battle.player_active().can_awaken(_screen.battle.charge_max()):
		_press(KEY_E)
		if _screen.battle.player_active().is_awakened:
			_saw_awakening = true
			_check_true("a tela anuncia o Despertar", _screen_text().contains("DESPERTO"))
		return false

	_text_before = _screen_text()
	_press(KEY_1)
	_rounds_played += 1
	return false


func _finish() -> void:
	_check_true("o duelo avancou", _rounds_played >= 2, "%d rodadas jogadas" % _rounds_played)
	_check_true("a tela mudou entre rodadas", _screen_text() != _text_before)
	_check_true("houve Despertar", _saw_awakening)
	_check_true("o duelo terminou", _screen.battle.is_over(),
		"desfecho %d" % _screen.battle.outcome)
	_check_true("a tela mostra o desfecho",
		_screen_text().contains("venceu") or _screen_text().contains("derrotada")
		or _screen_text().contains("capturada") or _screen_text().contains("fugiu"))

	# Tecla sem golpe correspondente avisa em vez de travar.
	_press(KEY_R)
	_check_true("R comeca um duelo novo", not _screen.battle.is_over())
	_press(KEY_9)
	_check_true("posicao vazia e recusada com aviso",
		_screen_text().contains("Nao existe golpe"))

	print("")
	print("--- amostra da tela ---")
	for line in _screen_text().split("\n").slice(0, 14):
		print("  " + line)

	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


func _press(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	_screen._input(ev)


## Texto puro, sem as marcações BBCode, para as asserções não dependerem de
## cor nem de formatação.
func _screen_text() -> String:
	var label := _screen.get_child(1) as RichTextLabel
	return label.get_parsed_text() if label else ""


func _db() -> BestiaryData:
	return _screen._db


func _check_true(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s%s" % [label, (" — " + detail) if detail != "" else ""])
	else:
		_failures += 1
		printerr("  FAIL %s%s" % [label, (" — " + detail) if detail != "" else ""])
