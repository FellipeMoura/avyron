extends SceneTree

## Prova que a criatura ativa **segue** o jogador, em vez de estar presa a ele.
##
## A diferença é fácil de descrever e fácil de perder: uma companheira grudada
## num offset se mexe no mesmo quadro que o comando, orbita quando o jogador
## gira parado, e chega ao lado dele cortando a curva na diagonal. Uma que
## segue sai depois, ignora giro no lugar, e chega por trás fazendo o caminho
## que ele fez.
##
## Este teste é determinístico de propósito: o "jogador" é um `Node3D` movido à
## mão em passos fixos, sem física nem input. O que está sob medição é a lei de
## seguimento, e amarrá-la ao motor de física traria jitter que esconderia
## justamente as margens pequenas — o atraso de largada é da ordem de um
## oitavo de segundo.
##
##     godot --headless --script res://scripts/dev/test_companion.gd

const STEP := 1.0 / 60.0
const WALK := PlayerController.WALK_SPEED

var _db: BestiaryData
var _failures := 0
var _checks := 0
var _frames := 0


func _initialize() -> void:
	_db = BestiaryData.new()
	var err := _db.load_bundle()
	if err != "":
		printerr("FALHA ao carregar o bundle: ", err)
		quit(1)


## Os testes rodam num quadro, não no `_initialize`: um nó adicionado à raiz
## antes de a árvore estar viva não conta como dentro dela, e `global_position`
## devolve o transform vazio — o que faria toda medição aqui virar zero.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_run()
	return true


func _run() -> void:
	_test_spawn()
	_test_turning_in_place()
	_test_start_delay()
	_test_settles_behind()
	_test_follows_the_path()
	_test_own_facing()
	_test_creature_swap_keeps_place()
	_test_follows_seabed_over_open_water()

	# Fora da árvore de cena: nada libera este Node por nós.
	_db.free()

	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)


# ---------------------------------------------------------------------------
# bancada
# ---------------------------------------------------------------------------

## Jogador de mentira + companheira, prontos e assentados.
##
## `set_process(false)` é essencial: o nó está na árvore, então o motor também
## chamaria `_process`, e cada passo do teste contaria dobrado.
func _rig() -> Array:
	var player := Node3D.new()
	player.name = "FakePlayer"
	root.add_child(player)

	var companion := CompanionActor.create(_db, "CRT-002", player)
	root.add_child(companion)
	companion.set_process(false)

	return [player, companion]


## `free()` e não `queue_free()`: os testes rodam todos dentro de um quadro, e
## a fila de liberação só é drenada no fim dele — as bancadas se empilhariam
## vivas, e a próxima veria nós da anterior ainda na raiz.
func _teardown(rig: Array) -> void:
	(rig[1] as CompanionActor).free()
	(rig[0] as Node3D).free()


## Anda o jogador `seconds` na direção dada, em passos de um quadro, chamando
## o `_process` da companheira em cada um — o mesmo caminho do jogo.
func _walk(rig: Array, direction: Vector3, seconds: float, speed: float = WALK) -> void:
	var player := rig[0] as Node3D
	var companion := rig[1] as CompanionActor
	var frames := int(seconds / STEP)
	for _i in frames:
		player.global_position += direction.normalized() * speed * STEP
		companion._process(STEP)


func _idle(rig: Array, seconds: float) -> void:
	var companion := rig[1] as CompanionActor
	for _i in int(seconds / STEP):
		companion._process(STEP)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	var d := a - b
	d.y = 0.0
	return d.length()


# ---------------------------------------------------------------------------
# testes
# ---------------------------------------------------------------------------

func _test_spawn() -> void:
	print("nascimento:")
	var rig := _rig()
	var player := rig[0] as Node3D
	var companion := rig[1] as CompanionActor

	var gap := _flat_distance(companion.global_position, player.global_position)
	_check_true("nasce na distancia de seguimento",
		absf(gap - CompanionActor.FOLLOW_DISTANCE) < 0.01, "%.2f m" % gap)

	# Atrás, não ao lado: a frente do jogador é -Z, então o vetor dele até ela
	# tem de apontar para a retaguarda.
	var to_companion := (companion.global_position - player.global_position).normalized()
	var player_back := player.global_transform.basis.z
	_check_true("nasce atras, nao ao lado",
		to_companion.dot(player_back) > 0.99, "dot = %.3f" % to_companion.dot(player_back))

	# A armadilha que o rastro semeado existe para evitar: com trilha de um
	# ponto só, o alvo cai em cima do jogador e ela dispara para os pés dele.
	var before := companion.global_position
	_idle(rig, 0.5)
	_check_true("parada, nao corre para cima do jogador",
		_flat_distance(companion.global_position, before) < 0.01,
		"andou %.3f m" % _flat_distance(companion.global_position, before))

	_teardown(rig)


func _test_turning_in_place() -> void:
	print("jogador gira no lugar:")
	var rig := _rig()
	var player := rig[0] as Node3D
	var companion := rig[1] as CompanionActor

	var before := companion.global_position
	# Meia volta em um segundo, sem sair do lugar.
	for i in int(1.0 / STEP):
		player.rotation.y = TAU * 0.5 * (float(i) * STEP)
		companion._process(STEP)

	# Este é o sintoma que o usuário descreveu: a versão presa a um offset
	# local orbitava o jogador aqui, porque o alvo girava junto com ele.
	_check_true("nao orbita quando o jogador gira parado",
		_flat_distance(companion.global_position, before) < 0.01,
		"andou %.3f m" % _flat_distance(companion.global_position, before))

	_teardown(rig)


func _test_start_delay() -> void:
	print("largada:")
	var rig := _rig()
	var companion := rig[1] as CompanionActor

	var before := companion.global_position

	# Primeiro instante do comando: o jogador já anda, ela ainda não.
	_walk(rig, Vector3.FORWARD, 0.1)
	var early := _flat_distance(companion.global_position, before)
	_check_true("nao parte no mesmo quadro do comando", early < 0.02,
		"andou %.3f m em 0.1 s" % early)
	_check_true("e ainda esta parada, nao so devagar", companion._speed < 0.2,
		"%.3f m/s" % companion._speed)

	# Um pouco depois, já saiu.
	_walk(rig, Vector3.FORWARD, 0.9)
	var later := _flat_distance(companion.global_position, before)
	_check_true("um segundo depois ja esta perseguindo", later > 0.5,
		"andou %.2f m em 1.0 s" % later)

	# Ela passa acima da velocidade de caminhada de propósito: perdeu terreno
	# na largada e está recuperando. O que não pode é estourar o teto.
	_check_true("recupera o terreno perdido acima do passo dele",
		companion._speed > WALK, "%.2f m/s" % companion._speed)
	_check_true("sem estourar o teto de velocidade",
		companion._speed <= CompanionActor.MAX_SPEED,
		"%.2f de %.2f m/s" % [companion._speed, CompanionActor.MAX_SPEED])

	_teardown(rig)


func _test_settles_behind() -> void:
	print("regime e repouso:")
	var rig := _rig()
	var player := rig[0] as Node3D
	var companion := rig[1] as CompanionActor

	_walk(rig, Vector3.FORWARD, 3.0)
	var walking_gap := _flat_distance(companion.global_position, player.global_position)
	_check_true("caminhando, fica atras a uma distancia de leitura",
		walking_gap > CompanionActor.FOLLOW_DISTANCE and walking_gap < 3.6,
		"%.2f m" % walking_gap)

	# Parado, recolhe.
	_idle(rig, 3.0)
	var rest_gap := _flat_distance(companion.global_position, player.global_position)
	_check_true("parada, recolhe para perto", rest_gap < walking_gap,
		"%.2f m" % rest_gap)
	_check_true("e para de vez", companion._speed < 0.01, "%.3f m/s" % companion._speed)

	_teardown(rig)


func _test_follows_the_path() -> void:
	print("curva:")
	var rig := _rig()
	var player := rig[0] as Node3D
	var companion := rig[1] as CompanionActor

	# Uma perna reta, depois virada de 90°. Quem segue o rastro faz o mesmo
	# canto; quem persegue um offset corta a diagonal.
	var first_leg := Vector3.FORWARD
	var second_leg := Vector3.RIGHT
	_walk(rig, first_leg, 1.2)
	var corner := player.global_position
	_walk(rig, second_leg, 0.35)

	# A pergunta não é "a que distância do canto", é "de que lado dele". Logo
	# após a virada ela ainda tem de estar **antes** do canto, vindo pela perna
	# anterior — projetar no eixo da primeira perna responde isso direto.
	var from_corner := companion.global_position - corner
	from_corner.y = 0.0
	_check_true("logo apos a curva ela ainda nao dobrou o canto",
		from_corner.dot(first_leg) < 0.0,
		"%.2f m antes dele no eixo da 1a perna" % -from_corner.dot(first_leg))

	# E não cortou a diagonal: se tivesse cortado, já estaria deslocada no eixo
	# da segunda perna, encurtando caminho em direção ao jogador.
	_check_true("nem cortou a diagonal para o jogador",
		absf(from_corner.dot(second_leg)) < 0.15,
		"desvio lateral de %.3f m" % absf(from_corner.dot(second_leg)))

	_teardown(rig)


func _test_own_facing() -> void:
	print("orientacao propria:")
	var rig := _rig()
	var player := rig[0] as Node3D
	var companion := rig[1] as CompanionActor

	# O jogador encara uma direção e anda para outra. Uma companheira que copia
	# `rotation.y` dele acabaria olhando para onde ele olha; uma que se orienta
	# pela própria marcha, para onde ela anda.
	player.rotation.y = TAU * 0.25
	_walk(rig, Vector3.FORWARD, 2.0)

	var facing := -companion.global_transform.basis.z
	facing.y = 0.0
	var moving := Vector3.FORWARD

	_check_true("encara a propria direcao de marcha",
		facing.normalized().dot(moving) > 0.9,
		"dot = %.3f" % facing.normalized().dot(moving))
	_check_true("e nao a do jogador",
		absf(companion.rotation.y - player.rotation.y) > 0.2,
		"dela %.2f rad, dele %.2f rad" % [companion.rotation.y, player.rotation.y])

	# Parada, vira para o domador.
	_idle(rig, 3.0)
	var to_player := player.global_position - companion.global_position
	to_player.y = 0.0
	var facing_rest := -companion.global_transform.basis.z
	facing_rest.y = 0.0
	_check_true("parada, encara o domador",
		facing_rest.normalized().dot(to_player.normalized()) > 0.9,
		"dot = %.3f" % facing_rest.normalized().dot(to_player.normalized()))

	_teardown(rig)


func _test_creature_swap_keeps_place() -> void:
	print("troca de criatura ativa:")
	var rig := _rig()
	var companion := rig[1] as CompanionActor

	_walk(rig, Vector3.FORWARD, 2.0)
	var before := companion.global_position

	companion.set_creature(_db, "CRT-023")
	_check("trocou de especie", companion.creature_code, "CRT-023")
	_check_true("quem entra assume o lugar de quem saiu",
		_flat_distance(companion.global_position, before) < 0.01,
		"pulou %.3f m" % _flat_distance(companion.global_position, before))

	# E continua seguindo, sem reiniciar o rastro.
	_walk(rig, Vector3.FORWARD, 1.0)
	_check_true("e segue andando depois da troca",
		_flat_distance(companion.global_position, before) > 0.5,
		"andou %.2f m" % _flat_distance(companion.global_position, before))

	_teardown(rig)


## `_ground_y` segue o relevo cru (`height_at`) sem exceção — sem física, a
## companheira nunca teve motivo para não fazer isso. Passou brevemente por um
## desvio (`surface_or_ground`, prendendo na cota da água fora da terra firme)
## enquanto o mar tinha profundidade de verdade e a trilha podia levá-la
## mergulhando de vez em quando no Mar Profundo (removido). Encolher o mar até
## não ter mais profundidade que justifique isso (`MapTerrain.SEA_HEIGHT`)
## tornou o desvio desnecessário — ela volta a seguir o leito cru em mar
## aberto, exatamente como em terra firme.
##
## Este teste, ao contrário dos outros da suíte, injeta um `MapTerrain` de
## verdade (com bioma, para ter uma cota) — os outros usam o fallback plano
## (`GROUND_Y`) de propósito, porque o que medem é a lei de seguimento, não o
## relevo.
func _test_follows_seabed_over_open_water() -> void:
	print("segue o leito raso em mar aberto:")
	var rig := _rig()
	var companion := rig[1] as CompanionActor
	var terrain := MapTerrain.create({})
	terrain.water_line = MapDressing.PZ01_WATER_LINE
	companion.terrain = terrain

	# O mesmo ponto que `test_playable.gd` usa como sonda de "o mar profundo" —
	# mar aberto, longe de qualquer terra firme declarada.
	var half := float(MapTerrain.SIZE) * 0.5
	companion.global_position = Vector3(half * 0.5, 0.0, half * 0.67)
	companion._process(STEP)

	var ground := terrain.height_at(companion.global_position)
	_check_true("o leito ali e SEA_HEIGHT, nao terra firme",
		not terrain.on_dry_land(companion.global_position), "chao %.2f" % ground)
	_check_true("a companheira segue o leito, nao prende na cota",
		absf(companion.global_position.y - ground) < 0.01,
		"y %.2f, cota %.2f, leito %.2f" % [companion.global_position.y, terrain.water_line, ground])

	terrain.free()
	_teardown(rig)


# ---------------------------------------------------------------------------

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
