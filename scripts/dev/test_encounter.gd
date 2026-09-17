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
var _phase := "walk"
## Quantos "passos" de deslocamento já demos para povoar o mapa. O mundo abre
## VAZIO de fauna desde 2026-09-06 — quem povoa é o jogador andando —, então a
## suíte precisa andar antes de ter o que clicar.
var _walk_steps := 0
var _failures := 0
var _checks := 0
var _size_min := 99.0
var _size_max := 0.0
var _post_close_wait := 0
var _target2: CreatureActor
var _target2_code := ""
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
		"walk":
			_drive_population()
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


## Anda com o jogador até o mapa ter fauna. O spawner rola uma chance a cada
## `SPAWN_CHECK_INTERVAL_METERS` percorridos, e a chance vem do bioma — então
## povoar aqui é literalmente deslocar o corpo, não chamar uma função de
## povoamento que não existe mais.
##
## Os saltos são grandes e em direções alternadas de propósito: o spawner
## consome TODOS os intervalos vencidos por quadro, então um salto de ~60 m já
## vale uma dúzia de rolagens, e alternar direção evita sair do mapa.
##
## A semente do RNG do spawner é fixada por reflexão (mesmo acesso a "privado"
## que a suíte já usa em `_world.get("_duel")`) porque produção perdeu o
## `spawn_seed` público nesta mesma mudança — e um teste que depende de sorteio
## sem semente falha um dia em cada tantos, no CI de outra pessoa.
func _drive_population() -> void:
	if _walk_steps == 0:
		var rng := _spawner.get("_rng") as RandomNumberGenerator
		if rng:
			rng.seed = 20260906
		# Vai para o MAR RASO (BIO-001) antes de começar, e o ponto é escolhido,
		# não qualquer um: TRÊS dos cinco biomas do PZ-01 têm `spawnChance` 0
		# de propósito — a costa (adro de NPC) e o par de vazio glacial/mar
		# profundo, que o catálogo declara sem vida. Rolar a vida toda dentro
		# de um deles deixaria o mapa vazio e reprovaria um spawner correto;
		# foi assim que esta suíte falhou na primeira versão, parada na costa.
		_player.global_position = Vector3(20.0, 4.0, 60.0)

	_walk_steps += 1
	# Vaivém curto que não sai do mar raso: a perna é para +x/-x, longe da
	# costa (-Z), da ilha (centro), do platô glacial (x ≤ −0,3 do meio-lado) e
	# do Mar Profundo (x ≥ +0,3). A 175 m (2026-09-16) essas duas fronteiras
	# ficam em ∓26,25 m e o vaivém vai de x −20 a +20 — cabe, com 6 m de folga
	# de cada lado. Encolher o mapa de novo pede rever estes pontos.
	# O spawner consome todos os intervalos vencidos por quadro, então cada
	# perna de 40 m já vale várias rolagens.
	var leg := 40.0 * (1 if _walk_steps % 2 == 0 else -1)
	_player.global_position += Vector3(leg, 0.0, leg * 0.3)

	if _spawner.actors().size() >= 6 or _walk_steps >= 40:
		_phase = "spawn"


func _check_spawn() -> void:
	print("povoamento:")
	var actors := _spawner.actors()
	_check_true("andar povoou o mapa", actors.size() > 0,
		"%d no mapa apos %d passos" % [actors.size(), _walk_steps])

	var codes := {}
	for a in actors:
		codes[a.creature_code] = true
		_size_min = minf(_size_min, a.size_meters)
		_size_max = maxf(_size_max, a.size_meters)
		_check_true_quiet("%s tem tamanho valido" % a.creature_code,
			a.size_meters >= 0.9 and a.size_meters <= 4.5)
	# Era "as escalas variam", de quando o tamanho saía de uma curva de
	# compressão logarítmica sobre o porte paleontológico real. A curva caiu
	# por decisão de produto (2026-09) e hoje TODA criatura mede o mesmo — a
	# asserção antiga cobrava justamente o que foi removido, e reprovava um
	# bundle correto. O que ainda vale cobrar é a uniformidade: um elenco onde
	# uma espécie destoa é bundle com dado errado, não variedade de propósito.
	# O número em si não entra aqui (Regra 1) — vem do bundle, e o teste só
	# exige que seja o MESMO para todo mundo.
	_check_true("toda criatura tem o mesmo tamanho padronizado",
		absf(_size_max - _size_min) < 0.001,
		"de %.2f m a %.2f m" % [_size_min, _size_max])
	_check_true("ha mais de uma especie", codes.size() > 1, "%d especies" % codes.size())

	# Nenhuma pode NASCER em cima do jogador — no modelo antigo isso abria o
	# jogo em combate; agora não abre mais, mas segue sendo um cheiro ruim.
	#
	# A prova é um spawn CONTROLADO, e não a distância dos corpos que já estão
	# no mapa: a fase de caminhada teleporta o jogador em pernas de 40 m, então
	# ele termina parado ao lado de quem nasceu enquanto ele estava longe. Medir
	# assim reprovava um spawner correto por medir a coisa errada — o contrato
	# é sobre o instante do NASCIMENTO, e é ele que este bloco recria.
	var before := _spawner.actors().size()
	_spawner.call("_spawn_one")
	var born_ok := _spawner.actors().size() > before
	if born_ok:
		var born: CreatureActor = _spawner.actors()[_spawner.actors().size() - 1]
		var d := born.global_position.distance_to(_player.global_position)
		_check_true("nasce longe do jogador", d >= CreatureSpawner.MIN_SPAWN_DISTANCE,
			"%.1f m (minimo %.1f)" % [d, CreatureSpawner.MIN_SPAWN_DISTANCE])
		var cam := _world.get_node_or_null("IsoCamera") as Camera3D
		if cam:
			_check_true("nasce fora do campo de visao",
				not cam.is_position_in_frustum(born.global_position))

	# Nem em terra seca. Os dois trechos emersos do PZ-01 — a costa e a ilha
	# da arena — são adro de NPC, e criatura marinha de pé neles contradiz o
	# mapa inteiro. O keep-out vive no `_find_spot`; é aqui que ele é cobrado.
	var terrain := _world.get_node_or_null("Ground") as MapTerrain
	if terrain:
		var on_dry := 0
		for a in actors:
			if terrain.on_coast(a.global_position) or terrain.on_island(a.global_position):
				on_dry += 1
		_check("nenhuma nasce na costa nem na ilha", on_dry, 0)

	# Nem em bioma que o catálogo declara SEM FAUNA. É um contrato diferente do
	# de cima: aquele é geografia (não ficar de pé em terra seca), este é
	# DADO — o platô glacial e o mar profundo estão em `spawnChance` 0,00
	# porque a nota do BIO-014 diz "nenhuma criatura nasce nem patrulha aqui".
	# A chance da rolagem é lida onde o JOGADOR está, e o corpo nasce num raio
	# que cruza fronteira, então sem o keep-out do spawner um jogador na beira
	# do mar raso semearia criaturas dentro do vazio.
	var biomes := _world.get("_map_biomes") as MapBiomes
	var db := root.get_node_or_null("Bestiary") as BestiaryData
	if biomes and db:
		var in_barren: Array[String] = []
		for a in actors:
			var code := biomes.biome_at(a.global_position)
			if db.biome_spawn_chance(code) <= 0.0:
				in_barren.append("%s em %s" % [a.creature_code, code])
		_check_true("nenhuma nasce em bioma sem fauna", in_barren.is_empty(),
			", ".join(in_barren))

	# Escolhe a mais próxima como alvo do teste, e LEVA O JOGADOR ATÉ ELA.
	var best := 1e9
	for a in actors:
		var d: float = a.global_position.distance_to(_player.global_position)
		if d < best:
			best = d
			_target = a
	print("  alvo: %s (%s) a %.1f m" % [_target.display_name, _target.creature_code, best])
	_approach(_target)


## Põe o jogador ao lado do alvo antes de clicar nele.
##
## Não é conveniência de bancada: sem isto o teste afirmava um contrato que o
## jogo não tem. A seleção CAI sozinha além de `WorldSelection.DESELECT_DISTANCE`
## (15 m, ancorada no raio de detecção da criatura — não no tamanho do mapa), e
## entre o primeiro e o segundo clique passa um quadro em que `_process` roda
## essa checagem. Clicar duas vezes numa criatura a 18 m nunca engatou; o
## segundo clique só reselecionava.
##
## Antes do resize de 2026-08-28 o teste passava por COINCIDÊNCIA de geometria:
## num mapa de 60 m com raio de spawn de 22, a criatura mais próxima caía
## dentro dos 15 m quase sempre. O mapa dobrou, a mais próxima passou a nascer
## a 18 m, e 2.997 de 3.030 verificações reprovaram de uma vez — a suíte estava
## medindo a sorte do sorteio, não o comportamento.
func _approach(actor: CreatureActor) -> void:
	if actor == null or _player == null:
		return
	# 3 m ao lado, não em cima: dois corpos sobrepostos são arremessados pela
	# física no primeiro quadro, e o alvo sairia de perto sozinho.
	var beside := actor.global_position + Vector3(3.0, 1.0, 0.0)
	_player.global_position = beside
	_player.velocity = Vector3.ZERO


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
	duel.battle.outcome = Battle.Outcome.PLAYER_WON
	duel.closed.emit(duel.battle.outcome)
	_phase = "post_close"


## Após vitória do jogador, a criatura sai do mapa. Sem isso, ganhar batalha
## deixava o mesmo bicho parado no mesmo lugar — o playtest ficava estranho
## porque a mesma vitória "não valia".
##
## Não há mais o que afirmar sobre reposição: até 2026-09-06 cada morte
## agendava um timer individual, e este teste cobrava `pending_respawns() == 1`.
## O modelo de população local ao jogador não tem timer nenhum — quem repõe é o
## deslocamento —, então a asserção antiga não descreve mais nada que exista.
## A asserção é de IDENTIDADE, não de contagem, e a diferença passou a
## importar: com o povoamento dirigido por deslocamento, o próprio
## `_approach()` desta suíte anda com o jogador e dispara rolagens. Um
## "população caiu de 7 para 6" corre contra um nascimento no mesmo quadro e
## falha sozinho — foi o que aconteceu na primeira versão. Se ESTA criatura
## saiu da lista é o contrato de verdade; quantas outras nasceram enquanto
## isso é assunto do spawner, não desta prova.
func _check_removal() -> void:
	print("pos-vitoria:")
	_check_true("a criatura derrotada saiu do mapa",
		not _spawner.actors().has(_target),
		"%d no mapa" % _spawner.actors().size())


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
		# Mesma razao do primeiro alvo: aproximar antes de clicar. Aqui o risco
		# era ainda maior, porque a vitoria anterior deixou o jogador onde a
		# encenacao do duelo o largou, nao onde ele clicou.
		_approach(_target2)
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
	# Salva o código antes de emitir closed — depois de queue_free o actor
	# não pode mais ser acessado com segurança.
	_target2_code = _target2.creature_code
	duel.battle.outcome = Battle.Outcome.CAPTURED
	duel.closed.emit(duel.battle.outcome)
	_phase = "post_capture"


func _check_capture_result() -> void:
	print("pos-captura:")
	# Identidade, não contagem — mesma razão de `_check_removal`.
	_check_true("criatura capturada saiu do mapa",
		not _spawner.actors().has(_target2),
		"%d no mapa" % _spawner.actors().size())
	# Vitória e captura são a mesma operação para o spawner desde 2026-09-06 —
	# o corpo sai, e ninguém agenda nada. O que separa as duas é o time crescer,
	# que é exatamente o que as asserções abaixo cobram.
	# A capturada entra como **reserva**: quem estava à frente continua à
	# frente. Trocar a ativa é decisão do jogador, não efeito colateral da
	# captura — senão uma criatura recém-pega, sem contexto nenhum, assumiria
	# a exploração e o perfil de mineração no meio do mapa.
	var roster := _world.roster()
	_check("o time cresceu para 2", roster.size(), 2)
	_check("a inicial continua a frente", roster.active(), _world.starter_code)
	_check_true("a capturada entrou como reserva",
		roster.reserves().size() == 1 and roster.reserves()[0] == _target2_code,
		"reservas: %s" % str(roster.reserves()))
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
