extends SceneTree

## Prova a encenação do duelo: os dois combatentes se encaram e convergem para
## a distância de duelo, venham de longe ou de cima um do outro.
##
## A pergunta que esta suíte responde é "a imagem mostra o que o overlay
## narra?". O combate acontece no mesmo espaço do mapa, então o par que aparece
## na luta é o par que a exploração deixou ali — de costas, colado ou a oito
## metros. Não é um teste de aritmética de vetor: é o teste de que a cena de
## abertura do duelo existe.
##
## O que mais importa aqui é a **simetria**. A correção é metade para cada
## lado, e é isso que preserva o ponto do encontro; se um dia um dos dois passar
## a fazer todo o trabalho, a briga escorrega para o lado do mais lento e a
## asserção do ponto médio é a que pega.
##
##     godot --headless --script res://scripts/dev/test_staging.gd

const STARTER := "CRT-002"
const LEVEL := 10

## Passo de simulação. Um sexagésimo, como o motor — a encenação é limitada por
## velocidade, e medir convergência com passo grosso esconderia ultrapassagem.
const STEP := 1.0 / 60.0
## Teto de quadros para convergir. Dez segundos de simulação; o que precisar de
## mais que isso está travado, não lento.
const MAX_STEPS := 600

## Teto de quadros para a convergência dirigida pelo motor. Muito mais alto que
## `MAX_STEPS` porque `--headless` roda o laço solto: cada quadro avança um
## delta pequeno, então convergir custa mais quadros do que na simulação de
## passo fixo. Existe para o teste falhar em vez de rodar para sempre.
const ENGINE_FRAME_CAP := 20000

## Raio do corpo do domador, o mesmo da cápsula do `Player` em `main.tscn`.
const TRAINER_RADIUS := 0.35

## Quadros extras para o domador assentar depois que o par já parou. Ele parte
## de um canto qualquer da bancada e anda a `TRAINER_SPEED`; isto é folga, não
## medida.
const TRAINER_SETTLE_STEPS := 500

var _world: WorldRoot
var _db: BestiaryData
var _frames := 0
var _settle_frames := 0
## A criatura engajada, guardada porque a fase de espera precisa dela e o
## `WorldRoot` não expõe quem está em campo.
var _staged_foe: CreatureActor
var _phase := "init"
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_world = load("res://scenes/main.tscn").instantiate() as WorldRoot
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	match _phase:
		"init":
			_db = root.get_node_or_null("/root/Bestiary") as BestiaryData
			if _db == null:
				_db = BestiaryData.new()
				var err := _db.load_bundle()
				if err != "":
					_check_true("bundle carregou", false, err)
					_finish()
					return true
			_test_standoff_formula()
			_test_convergence()
			_test_facing()
			_test_symmetry()
			_test_trainer()
			_test_degenerate()
			_test_world_wiring()
			_phase = "settling"
			_settle_frames = 0
		"settling":
			# Aqui ninguém chama `step`: quem tem de mover os dois é o `_process`
			# do motor, com o mundo pausado. É a única asserção da suíte que
			# prova a fiação em vez da geometria — sem ela, `PROCESS_MODE_ALWAYS`
			# poderia ter caído e todo o resto continuaria verde.
			#
			# Conta quadros, não segundos: `--headless` roda o laço solto, então
			# o delta de cada quadro é pequeno e imprevisível. O teto é generoso
			# de propósito — o que se mede é "converge?", não "em quanto tempo".
			_settle_frames += 1
			var s := _world.staging()
			if s == null:
				_check_true("a encenacao sobreviveu ate o quadro do motor", false)
				_phase = "done"
			elif absf(s.current_distance() - s.standoff()) <= BattleStaging.TOLERANCE \
					and s.trainer_error() <= BattleStaging.TOLERANCE:
				_test_engine_driven(s, true)
				_phase = "done"
			elif _settle_frames > ENGINE_FRAME_CAP:
				_test_engine_driven(s, false)
				_phase = "done"
		"done":
			_finish()
			return true
	return false


# ---------------------------------------------------------------------------
# a distância
# ---------------------------------------------------------------------------

func _test_standoff_formula() -> void:
	print("distancia de duelo:")

	# O vão entre as BORDAS é o que se vê. Medir de centro a centro sem somar os
	# raios daria bichos grandes sobrepostos com o mesmo número que separa dois
	# pequenos — é o erro que a soma dos raios existe para evitar.
	var small := BattleStaging.standoff_for(0.15, 0.15)
	var big := BattleStaging.standoff_for(2.5, 2.5)
	_check_true("par grande fica mais longe que par pequeno", big > small,
		"%.2f vs %.2f" % [big, small])

	var gap_small := small - CreatureActor.capsule_radius(0.15) * 2.0
	var gap_big := big - CreatureActor.capsule_radius(2.5) * 2.0
	_check_true("e o vao entre as bordas cresce junto", gap_big > gap_small,
		"%.2f vs %.2f" % [gap_big, gap_small])
	_check_true("nenhum par se sobrepoe", gap_small > 0.0, "%.2f m de vao" % gap_small)

	# Assimétrico: um trilobita contra um Arthropleura fica entre os dois casos.
	var mixed := BattleStaging.standoff_for(0.15, 2.5)
	_check_true("par misto fica entre os dois", mixed > small and mixed < big,
		"%.2f" % mixed)

	_check_true("o teto segura o par gigante",
		BattleStaging.standoff_for(50.0, 50.0) <= BattleStaging.MAX_STANDOFF)
	_check_true("o piso segura o par minusculo",
		BattleStaging.standoff_for(0.01, 0.01) >= BattleStaging.MIN_STANDOFF)

	# O multiplicador de enquadramento vale para o par inteiro, não só para a
	# folga: aplicá-lo à folga sozinha faria o par grande crescer
	# proporcionalmente menos que o pequeno — o oposto do que se quer.
	var geometric := CreatureActor.capsule_radius(1.8) * 2.0 \
		+ BattleStaging.BASE_GAP + 3.6 * BattleStaging.GAP_PER_METER
	_check_true("a distancia e o multiplo cenico da geometrica",
		is_equal_approx(BattleStaging.standoff_for(1.8, 1.8),
			geometric * BattleStaging.DUEL_SPREAD),
		"%.2f = %.2f x %.1f" % [BattleStaging.standoff_for(1.8, 1.8),
			geometric, BattleStaging.DUEL_SPREAD])
	_check_true("e sobra bem mais que o encosto dos corpos",
		BattleStaging.standoff_for(1.8, 1.8) > geometric,
		"%.2f vs %.2f" % [BattleStaging.standoff_for(1.8, 1.8), geometric])


# ---------------------------------------------------------------------------
# convergência
# ---------------------------------------------------------------------------

func _test_convergence() -> void:
	print("longe se aproximam, perto se afastam:")

	# Longe demais.
	var far := _bench(Vector3(-6.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0))
	var far_before: float = far["staging"].current_distance()
	var far_steps := _settle(far["staging"])
	var far_after: float = far["staging"].current_distance()
	_check_true("de 12 m eles convergem", far_steps < MAX_STEPS,
		"%d quadros" % far_steps)
	_check_true("e param na distancia de duelo",
		absf(far_after - far["staging"].standoff()) <= BattleStaging.TOLERANCE,
		"%.2f -> %.2f (alvo %.2f)" % [far_before, far_after, far["staging"].standoff()])

	# Perto demais.
	var near := _bench(Vector3(-0.2, 0.0, 0.0), Vector3(0.2, 0.0, 0.0))
	var near_before: float = near["staging"].current_distance()
	var near_steps := _settle(near["staging"])
	var near_after: float = near["staging"].current_distance()
	_check_true("de 40 cm eles se afastam", near_after > near_before,
		"%.2f -> %.2f" % [near_before, near_after])
	_check_true("e tambem param na distancia de duelo",
		absf(near_after - near["staging"].standoff()) <= BattleStaging.TOLERANCE,
		"%.2f (alvo %.2f)" % [near_after, near["staging"].standoff()])
	_check_true("sem estourar o teto de quadros", near_steps < MAX_STEPS,
		"%d quadros" % near_steps)

	# Já na distância certa: ninguém se mexe. Sem a zona morta os dois
	# corrigiriam frações de milímetro para sempre, e o resultado seria um
	# tremor a dois.
	var s := BattleStaging.standoff_for(1.8, 1.8)
	var ok := _bench(Vector3(-s * 0.5, 0.0, 0.0), Vector3(s * 0.5, 0.0, 0.0))
	var pos_before: Vector3 = (ok["a"] as Node3D).global_position
	for _i in 30:
		(ok["staging"] as BattleStaging).step(STEP)
	var drift := pos_before.distance_to((ok["a"] as Node3D).global_position)
	_check_true("na distancia certa ninguem se mexe", drift < 0.01,
		"%.4f m de deriva" % drift)

	# Nunca ultrapassa: passar do ponto num quadro produziria o vaivém de quem
	# persegue com passo fixo. Um passo longo é o caso que expõe isso.
	var overshoot := _bench(Vector3(-6.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0))
	(overshoot["staging"] as BattleStaging).step(10.0)
	var d: float = (overshoot["staging"] as BattleStaging).current_distance()
	_check_true("um quadro longo nao ultrapassa o alvo",
		d >= (overshoot["staging"] as BattleStaging).standoff() - BattleStaging.TOLERANCE,
		"%.2f" % d)


func _test_facing() -> void:
	print("encaram um ao outro:")
	# Nascem de costas, no eixo X.
	var b := _bench(Vector3(-5.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0))
	var a: Node3D = b["a"]
	var c: Node3D = b["b"]
	a.rotation.y = 0.0
	c.rotation.y = 0.0
	_settle(b["staging"])

	# A frente de um nó é -Z: `basis.z` é a retaguarda, então a frente é o
	# oposto dela. Usar `atan2(x, z)` no lugar de `atan2(-x, -z)` passaria nesta
	# medida com o sinal invertido — por isso o teste mede o corpo, não o yaw.
	var a_front := -a.global_transform.basis.z
	var c_front := -c.global_transform.basis.z
	# Achatado: a bancada põe os dois em alturas diferentes de propósito, e um
	# `dot` em 3D mediria a inclinação de 1,4 m entre eles em vez do
	# encaramento. Encarar é no plano — os corpos não olham para cima.
	var a_to_c := _flat(c.global_position - a.global_position).normalized()

	_check_true("a encara b", a_front.normalized().dot(a_to_c) > 0.99,
		"dot %.3f" % a_front.normalized().dot(a_to_c))
	_check_true("b encara a", c_front.normalized().dot(-a_to_c) > 0.99,
		"dot %.3f" % c_front.normalized().dot(-a_to_c))
	_check_true("e nao ficam de costas",
		a_front.normalized().dot(c_front.normalized()) < -0.99)


func _test_symmetry() -> void:
	print("cada um anda metade:")
	var b := _bench(Vector3(-6.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0))
	var a: Node3D = b["a"]
	var c: Node3D = b["b"]
	var mid_before := (a.global_position + c.global_position) * 0.5

	_settle(b["staging"])
	var mid_after := (a.global_position + c.global_position) * 0.5

	# O ponto médio é onde os dois se encontraram. Se um dia um dos lados passar
	# a fazer todo o trabalho, a briga escorrega para o lado do mais lento — e é
	# esta asserção que pega.
	_check_true("o ponto do encontro nao escorrega",
		mid_before.distance_to(mid_after) < 0.02,
		"%.4f m" % mid_before.distance_to(mid_after))

	var walked_a := absf(a.global_position.x - (-6.0))
	var walked_c := absf(c.global_position.x - 6.0)
	_check_true("os dois andam o mesmo tanto", absf(walked_a - walked_c) < 0.02,
		"%.2f vs %.2f" % [walked_a, walked_c])

	# O Y de cada corpo segue regra própria — a selvagem sobe meia cápsula, a
	# companheira fica no chão com o mesh deslocado. A encenação trabalha no
	# plano e não pode desfazer nenhuma das duas.
	_check_true("a altura de a nao foi tocada", is_equal_approx(a.global_position.y, 0.0),
		"%.3f" % a.global_position.y)
	_check_true("a altura de b nao foi tocada", is_equal_approx(c.global_position.y, 1.4),
		"%.3f" % c.global_position.y)


func _test_trainer() -> void:
	print("o domador atras da propria criatura:")
	var bench := _bench(Vector3(-6.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0))
	var a: Node3D = bench["a"]
	var b: Node3D = bench["b"]
	var t: Node3D = bench["trainer"]
	var s: BattleStaging = bench["staging"]

	_settle(s)
	# O domador parte de um canto qualquer e persegue um posto que se move junto
	# com a criatura; assentar leva mais que o par.
	for _i in TRAINER_SETTLE_STEPS:
		if s.trainer_error() <= BattleStaging.TOLERANCE:
			break
		s.step(STEP)
	_check_true("o domador assenta no posto",
		s.trainer_error() <= BattleStaging.TOLERANCE, "%.3f m" % s.trainer_error())

	var axis := _flat(b.global_position - a.global_position).normalized()
	var to_trainer := _flat(t.global_position - a.global_position)

	# Atrás é o sentido oposto ao do adversário. Um `dot` positivo aqui seria a
	# plateia dentro do ringue.
	_check_true("fica do lado oposto ao adversario",
		to_trainer.normalized().dot(axis) < -0.99,
		"dot %.3f" % to_trainer.normalized().dot(axis))
	_check_true("na distancia derivada dos dois corpos",
		absf(to_trainer.length() - s.trainer_offset()) <= BattleStaging.TOLERANCE,
		"%.2f (alvo %.2f)" % [to_trainer.length(), s.trainer_offset()])

	# O multiplicador de enquadramento do recuo vale para o par de raios
	# inteiro, como o do duelo — sem isso o domador ficaria proporcionalmente
	# mais colado quanto maior a criatura dele.
	var geometric := CreatureActor.capsule_radius(1.8) + TRAINER_RADIUS \
		+ BattleStaging.TRAINER_GAP
	_check_true("o recuo e o multiplo cenico do geometrico",
		is_equal_approx(s.trainer_offset(), geometric * BattleStaging.TRAINER_SPREAD),
		"%.2f = %.2f x %.1f" % [s.trainer_offset(), geometric,
			BattleStaging.TRAINER_SPREAD])

	# Encara o mesmo lado que a criatura dele: os dois olham para o adversário.
	var front := -t.global_transform.basis.z
	_check_true("e encara o adversario junto com ela",
		_flat(front).normalized().dot(axis) > 0.99,
		"dot %.3f" % _flat(front).normalized().dot(axis))
	_check_true("na mesma direcao que a criatura",
		_flat(front).normalized().dot(_flat(-a.global_transform.basis.z).normalized()) > 0.99)

	# Nunca entre os dois: quem assiste não ocupa o lugar de quem luta.
	_check_true("nunca entre os combatentes",
		_flat(t.global_position - b.global_position).length()
			> _flat(a.global_position - b.global_position).length(),
		"%.2f vs %.2f" % [_flat(t.global_position - b.global_position).length(),
			_flat(a.global_position - b.global_position).length()])

	# A altura do domador é o centro da cápsula dele. A encenação trabalha no
	# plano e não pode achatá-lo no chão.
	_check_true("a altura dele nao foi tocada", is_equal_approx(t.global_position.y, 0.9),
		"%.3f" % t.global_position.y)

	# O posto é derivado, não negociado: o domador não entra na correção
	# simétrica, então a presença dele não pode mover o ponto do encontro.
	var solo := _bench(Vector3(-6.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), false)
	_settle(solo["staging"])
	var mid_solo := ((solo["a"] as Node3D).global_position
		+ (solo["b"] as Node3D).global_position) * 0.5
	var mid_with := (a.global_position + b.global_position) * 0.5
	_check_true("a presenca dele nao move o ponto do encontro",
		mid_solo.distance_to(mid_with) < 0.02,
		"%.4f m" % mid_solo.distance_to(mid_with))

	# Sem domador a encenação continua valendo para o par que luta.
	(solo["staging"] as BattleStaging).step(STEP)
	_check_true("sem domador nao estoura",
		absf((solo["staging"] as BattleStaging).current_distance()
			- (solo["staging"] as BattleStaging).standoff()) <= BattleStaging.TOLERANCE)


func _test_degenerate() -> void:
	print("casos degenerados:")

	# Exatamente sobrepostos: a direção entre os dois não existe. Sem a memória
	# do eixo, o afastamento escolheria um rumo diferente a cada quadro e os
	# dois vibrariam no lugar em vez de se separarem.
	var b := _bench(Vector3.ZERO, Vector3.ZERO)
	var s: BattleStaging = b["staging"]
	_settle(s)
	_check_true("corpos sobrepostos se separam",
		absf(s.current_distance() - s.standoff()) <= BattleStaging.TOLERANCE,
		"%.2f" % s.current_distance())

	# Um lado sumiu no meio da luta (criatura capturada, cena liberada). Não
	# pode estourar — só parar de encenar.
	var gone := _bench(Vector3(-5.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0))
	(gone["b"] as Node3D).free()
	(gone["staging"] as BattleStaging).step(STEP)
	_check("sem um dos lados nao ha distancia",
		(gone["staging"] as BattleStaging).current_distance(), -1.0)

	# Delta zero ou negativo é no-op, não um passo ao contrário.
	var zero := _bench(Vector3(-5.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0))
	var before: float = (zero["staging"] as BattleStaging).current_distance()
	(zero["staging"] as BattleStaging).step(0.0)
	(zero["staging"] as BattleStaging).step(-1.0)
	_check("delta nao positivo nao mexe em nada",
		(zero["staging"] as BattleStaging).current_distance(), before)


# ---------------------------------------------------------------------------
# mundo
# ---------------------------------------------------------------------------

func _test_world_wiring() -> void:
	print("no WorldRoot:")
	_check_true("fora do duelo nao ha encenacao", _world.staging() == null)

	var spawner: CreatureSpawner = _world.get_node_or_null("CreatureSpawner")
	var target: CreatureActor = spawner.actors()[0] if spawner and not spawner.actors().is_empty() else null
	if target == null:
		_check_true("ha criatura no mapa para engajar", false)
		return

	# Põe a selvagem longe, para a encenação ter trabalho de verdade.
	var companion: Node3D = _world.get_node_or_null("Companion")
	if companion == null:
		_check_true("a companheira existe", false)
		return
	# Bem além da distância de duelo, para a encenação ter trabalho de verdade.
	target.global_position = companion.global_position + Vector3(25.0, 0.0, 0.0)
	target.global_position.y = 1.4
	_staged_foe = target

	_world.handle_click_on(target)
	_world.handle_click_on(target)

	var s := _world.staging()
	_check_true("engajar cria a encenacao", s != null)
	if s == null:
		root.get_tree().paused = false
		return

	# A encenação tem de rodar com o mundo parado — é o mesmo motivo de a câmera
	# precisar de PROCESS_MODE_ALWAYS. Sem isto ela congela junto com o que
	# deveria encenar, e o duelo abre exatamente como a exploração deixou.
	_check("roda com o mundo pausado", s.process_mode, Node.PROCESS_MODE_ALWAYS)
	_check_true("o mundo esta mesmo pausado", root.get_tree().paused)
	_check_true("o duelo comeca com os dois longe",
		s.current_distance() > s.standoff() * 2.0,
		"%.2f (alvo %.2f)" % [s.current_distance(), s.standoff()])

	# A distância sai dos tamanhos reais das duas criaturas, não de um número
	# fixo: um trilobita contra um Arthropleura não se mede como dois iguais.
	_check_true("a distancia veio dos tamanhos do bundle",
		is_equal_approx(s.standoff(),
			BattleStaging.standoff_for(_companion_size(), target.size_meters)),
		"%.2f" % s.standoff())

	# **Não** assenta à mão daqui em diante: o resto é com o motor, na fase
	# "settling". O duelo fica aberto de propósito.


## As asserções que só o motor pode provar. `converged` diz se a fase de espera
## viu a distância assentar sozinha, sem nenhum `step` manual.
func _test_engine_driven(s: BattleStaging, converged: bool) -> void:
	print("dirigido pelo motor, com o mundo pausado:")
	_check_true("os dois convergem sem ninguem chamar step", converged,
		"%.2f (alvo %.2f) em %d quadros" % [s.current_distance(), s.standoff(), _settle_frames])

	var companion: Node3D = _world.get_node_or_null("Companion")
	var foe: Node3D = _staged_foe
	var trainer: Node3D = _world.get_node_or_null("Player")
	if companion and foe and is_instance_valid(foe):
		var axis := _flat(foe.global_position - companion.global_position).normalized()
		var front := -companion.global_transform.basis.z
		_check_true("e a companheira encara o adversario",
			_flat(front).normalized().dot(axis) > 0.99,
			"dot %.3f" % _flat(front).normalized().dot(axis))

		# O domador é o `Player` da cena de verdade, com o raio lido da forma de
		# colisão — não de uma constante do teste.
		if trainer:
			var behind := _flat(trainer.global_position - companion.global_position)
			_check_true("o domador ficou atras da criatura dele",
				behind.normalized().dot(axis) < -0.99,
				"dot %.3f" % behind.normalized().dot(axis))
			_check_true("na distancia derivada dos dois corpos",
				absf(behind.length() - s.trainer_offset()) <= BattleStaging.TOLERANCE,
				"%.2f (alvo %.2f)" % [behind.length(), s.trainer_offset()])
			var trainer_front := -trainer.global_transform.basis.z
			_check_true("e virado para o adversario",
				_flat(trainer_front).normalized().dot(axis) > 0.99,
				"dot %.3f" % _flat(trainer_front).normalized().dot(axis))

	var layer := _world.get_node_or_null("DuelLayer")
	if layer:
		var duel: DuelScreen = layer.get_child(0)
		duel.closed.emit(Battle.Outcome.FLED)
	root.get_tree().paused = false
	# Sair do duelo tem de soltar a encenação antes de o mundo voltar a andar,
	# senão perseguição e trilha disputam o mesmo `global_position` com ela.
	_check_true("fechar o duelo solta a encenacao", _world.staging() == null)


## Achata no plano do chão. Os três corpos da cena estão em alturas diferentes
## de propósito — companheira no chão, selvagem meia cápsula acima, domador no
## centro da própria cápsula — então toda medida de direção ou distância entre
## eles tem de descartar o Y antes, ou mede o desnível junto.
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _companion_size() -> float:
	var c: CompanionActor = _world.get_node_or_null("Companion")
	return c.size_meters if c else 0.0


# ---------------------------------------------------------------------------

## Bancada mínima: dois `Node3D` nas posições dadas, com a encenação montada
## sobre eles. Node3D solto em vez dos atores reais de propósito — o que está
## sob teste é a geometria do afastamento, e um `CharacterBody3D` traria física,
## gravidade e colisão para dentro de uma medida que não é sobre nada disso.
##
## As alturas são as dos corpos de verdade (companheira no chão, selvagem meia
## cápsula acima) justamente para provar que a encenação não as toca.
func _bench(at_a: Vector3, at_b: Vector3, with_trainer := true) -> Dictionary:
	var a := Node3D.new()
	var b := Node3D.new()
	root.add_child(a)
	root.add_child(b)
	a.global_position = Vector3(at_a.x, 0.0, at_a.z)
	b.global_position = Vector3(at_b.x, 1.4, at_b.z)
	var s := BattleStaging.create(a, 1.8, b, 1.8)

	# O domador nasce num canto qualquer, e no Y do centro da cápsula dele
	# (0,9 m). A altura errada é o defeito que a encenação não pode introduzir,
	# então ela precisa estar certa e diferente das outras duas desde o começo.
	var t: Node3D = null
	if with_trainer:
		t = Node3D.new()
		root.add_child(t)
		t.global_position = Vector3(3.0, 0.9, -4.0)
		s.set_trainer(t, TRAINER_RADIUS)

	root.add_child(s)
	# `set_process(false)` porque a bancada chama `step` à mão: sem isto o motor
	# também chamaria, e cada passo contaria dobrado.
	s.set_process(false)
	return {"a": a, "b": b, "staging": s, "trainer": t}


## Roda até assentar. Devolve quantos quadros levou — `MAX_STEPS` significa que
## não convergiu.
func _settle(staging: BattleStaging) -> int:
	for i in MAX_STEPS:
		var error := absf(staging.current_distance() - staging.standoff())
		if error <= BattleStaging.TOLERANCE:
			return i
		staging.step(STEP)
	return MAX_STEPS


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
