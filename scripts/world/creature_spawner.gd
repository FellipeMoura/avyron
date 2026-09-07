class_name CreatureSpawner
extends Node3D

## Mantém a fauna selvagem ao redor do JOGADOR — nasce fora do quadro conforme
## ele anda, some quando fica para trás.
##
## Lê o bundle — nada de lista de criaturas escrita em cena. Acrescentar uma
## espécie ao PZ-01 no bestiário e re-exportar já a coloca no mundo, sem tocar
## em código nem em cena. É o mesmo contrato que vale para stats e golpes.
##
## ## População local, não contagem fixa (desde 2026-09-06)
##
## Até o mapa de 350 m isto era um pool FIXO: 24 criaturas nascidas de uma vez
## na abertura, num raio ao redor da ORIGEM, cada morte agendando um timer de
## respawn individual. Funcionava porque o raio cobria quase todo o mapa de
## 120 m. A 350 m a mesma densidade pediria ~270 corpos rigados simultâneos, e
## o número não é questão de ajustar um campo — é o modelo que muda.
##
## Hoje o ciclo é outro, e tem duas pontas:
##
##   NASCE — a cada `SPAWN_CHECK_INTERVAL_METERS` que o jogador percorre, rola
##   uma chance. A chance é do BIOMA em que ele está (`biome_spawn_chance`),
##   e é o que faz um recife fervilhar e um platô glacial parecer morto. Dando
##   certo, a espécie sai de um sorteio PONDERADO pelo peso de cada uma
##   (`creature_spawn_weight`), e o corpo aparece fora do campo de visão.
##
##   MORRE — quem fica fora do frustum da câmera por `OFFSCREEN_GRACE_SEC`
##   contínuos é removido, sem agendar nada. A poda é o que mantém a população
##   limitada sem ninguém contar: o mapa inteiro nunca está povoado, só o
##   arredor do jogador.
##
## Os dois números que um designer ia querer mexer — com que frequência nasce,
## e o que nasce — são do BESTIÁRIO (regra 1). O que sobrou aqui é engenharia:
## de quanto em quanto metro perguntar, quanto tempo esperar antes de podar, e
## o teto de segurança.

## Mapa a povoar. Quando houver mais de um, vira parâmetro da cena.
@export var map_code := "PZ-01"

## Raio máximo de nascimento ao redor do jogador. Não é "onde a criatura pode
## estar" — é só onde ela pode APARECER; depois disso ela patrulha por conta.
## Longe demais e o jogador nunca alcança o que nasceu antes da poda levar;
## perto demais e não sobra anel fora do quadro para nascer.
@export var spawn_radius := 45.0
@export var min_separation := 4.0
@export var level := 10

## Teto de segurança, não densidade. Quem define a sensação de "cheio" é a
## chance por bioma mais a carência de poda; isto só impede que uma sequência
## de rolagens felizes empilhe corpos mais rápido do que o despawn os tira.
@export var local_population_cap := 40

## De quanto em quanto metro percorrido o mundo pergunta "nasce alguém?".
## Constante ÚNICA e global de propósito: o que varia por bioma é a CHANCE, na
## tabela do bestiário — ter também o intervalo por bioma daria dois botões
## para o mesmo efeito, e eles discordariam.
const SPAWN_CHECK_INTERVAL_METERS := 5.0

## Quanto tempo uma criatura precisa passar CONTINUAMENTE fora do quadro antes
## de ser removida. Sem essa carência, um corpo parado exatamente na borda da
## tela nasceria e morreria a cada quadro conforme a câmera oscila.
const OFFSCREEN_GRACE_SEC := 2.5

## Nem tão perto que o corpo apareça em cima do jogador se o frustum falhar.
## Herdou o número do keep-out antigo em volta do ponto de partida — a razão é
## vizinha: não empurrar um encontro na cara de quem acabou de chegar.
const MIN_SPAWN_DISTANCE := 6.0

## Folga, em metros, entre a borda do quadro e o ponto mais próximo em que uma
## criatura pode nascer.
##
## Existe porque a câmera PERSEGUE o jogador com suavização e antecipação
## (`IsoCamera.follow_smoothing`/`lookahead`): no instante do teste ela está
## sempre um pouco atrás de onde vai estar, então "fora do quadro agora" pode
## virar "dentro do quadro no próximo quadro" — a câmera varre por cima do
## corpo recém-nascido e o efeito, para quem joga, é exatamente o pop-in que
## este sistema existe para evitar. Medido: sem folga, 3 de 55 nascimentos
## caíram dentro do quadro numa sonda que andava rápido de propósito.
const FRUSTUM_MARGIN := 8.0

signal creature_engaged(actor: CreatureActor)
## Emitido quando o povoamento muda (spawn ou remoção). O WorldRoot escuta
## para atualizar o hint com a contagem corrente.
signal population_changed()

## Consulta de altura para spawnar apoiado no relevo. Nulo (bancadas de teste
## sem terreno) = comportamento antigo, chão em y = 0.
var terrain: MapTerrain
## Quem o povoamento segue. Sem ele nada nasce — é a referência que substituiu
## a origem do mapa como centro do mundo vivo.
var player: Node3D
## Quem responde "isto está na tela?". Sem ela o nascimento perde o teste de
## frustum e a poda não roda (bancada de teste sem câmera continua válida).
var camera: Camera3D
## Quem responde "que bioma é aqui?" — a chance de spawn sai dele.
var map_biomes: MapBiomes

var _rng := RandomNumberGenerator.new()
var _actors: Array[CreatureActor] = []
var _pool: Array = []
var _db: BestiaryData
## Contador incremental usado como sufixo de nome. Não reciclado ao remover —
## evita colisão de nome se dois actors do mesmo `creature_code` coexistirem.
var _seed_counter := 0

var _last_player_pos := Vector3.INF
var _distance_since_check := 0.0
## Ator -> segundos contínuos fora do frustum. Mora aqui, e não no
## `CreatureActor`, porque o ator é cego por design (só IDLE/PATROL, "ignora o
## jogador por completo") e dar câmera a cada um duplicaria a varredura que
## este nó já faz.
var _offscreen_time: Dictionary = {}


func _ready() -> void:
	# Sem semente fixa. Ela existia para duas execuções abrirem o mapa iguais e
	# poderem ser comparadas lado a lado num playtest — o que deixou de existir
	# quando o povoamento virou função do caminho que o jogador andou. Não há
	# mais "a mesma abertura": o mundo abre vazio e cada sessão o preenche
	# diferente por natureza.
	_rng.randomize()
	populate()


## Resolve o pool do mapa. NÃO spawna ninguém: o mundo abre sem fauna e é o
## deslocamento do jogador que o povoa.
func populate() -> void:
	_db = get_node_or_null("/root/Bestiary") as BestiaryData
	if _db == null:
		push_error("CreatureSpawner: autoload Bestiary indisponivel")
		return

	_pool = _db.creatures_in_map(map_code)
	if _pool.is_empty():
		push_warning("CreatureSpawner: nenhuma criatura no mapa %s" % map_code)


func _process(delta: float) -> void:
	_update_frustum_grace(delta)

	if player == null or not is_instance_valid(player):
		return

	var here := player.global_position
	if _last_player_pos == Vector3.INF:
		_last_player_pos = here
		return
	_distance_since_check += here.distance_to(_last_player_pos)
	_last_player_pos = here

	# Consome TODOS os intervalos vencidos, não só um por quadro. Um salto
	# grande de posição — teleporte de bancada, ou um quadro longo — não pode
	# fazer distância percorrida evaporar sem ter rolado nada.
	while _distance_since_check >= SPAWN_CHECK_INTERVAL_METERS:
		_distance_since_check -= SPAWN_CHECK_INTERVAL_METERS
		_roll_spawn()


## Uma rolagem: o bioma sob o jogador decide a chance, e o sorteio ponderado
## decide quem. Silenciosamente não faz nada quando a chance não sai, quando o
## teto está cheio ou quando não há ponto livre — todos são estado normal.
func _roll_spawn() -> void:
	if _pool.is_empty() or _db == null:
		return
	if _actors.size() >= local_population_cap:
		return
	if map_biomes == null:
		return

	var biome_code := map_biomes.biome_at(player.global_position)
	if _rng.randf() >= _db.biome_spawn_chance(biome_code):
		return

	var data := _pick_weighted_species()
	if data.is_empty():
		return
	_spawn_one(data)


## Sorteio ponderado dentro do pool do mapa. Devolve `{}` se o pool inteiro
## somar zero — que é bundle defeituoso, não estado normal, e é por isso que o
## export aborta antes de deixar um peso faltando chegar aqui.
func _pick_weighted_species() -> Dictionary:
	var total := 0.0
	for data in _pool:
		total += _db.creature_spawn_weight(str(data.get("code", "")))
	if total <= 0.0:
		return {}

	var roll := _rng.randf() * total
	for data in _pool:
		roll -= _db.creature_spawn_weight(str(data.get("code", "")))
		if roll <= 0.0:
			return data
	return _pool[_pool.size() - 1]


## Põe uma criatura no mundo. `data` vazio sorteia — é o atalho que as bancadas
## de teste usam para ter um corpo no mapa sem exercitar a rolagem inteira.
func _spawn_one(data: Dictionary = {}) -> bool:
	if data.is_empty():
		data = _pick_weighted_species()
		if data.is_empty():
			return false

	var origin := player.global_position if player and is_instance_valid(player) else Vector3.ZERO
	var spot := _find_spot_near_player(origin)
	if spot == Vector3.INF:
		return false

	var actor := CreatureActor.create(data, spot, _rng.randi())
	_seed_counter += 1
	actor.name = "%s_%d" % [str(data["code"]), _seed_counter]
	actor.engaged.connect(_on_engaged)
	add_child(actor)
	_actors.append(actor)
	population_changed.emit()
	return true


## Procura um ponto livre num anel ao redor do jogador. Sem a separação mínima,
## duas criaturas nascem sobrepostas e a física as arremessa no primeiro quadro.
func _find_spot_near_player(player_pos: Vector3) -> Vector3:
	for _attempt in 30:
		var angle := _rng.randf() * TAU
		var dist := sqrt(_rng.randf()) * spawn_radius
		var candidate := player_pos + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		if candidate.distance_to(player_pos) < MIN_SPAWN_DISTANCE:
			continue
		# A costa é solo de NPCs e portais — mob não nasce lá. A margem de
		# 3 m cobre a deriva de patrulha (HOME_LEASH) até a beira da rampa.
		if terrain and terrain.on_coast(candidate, 3.0):
			continue
		# A ilha, pela mesma razão: é o adro da arena, e criatura marinha de pé
		# no seco contradiz o mapa inteiro.
		if terrain and terrain.on_island(candidate, 2.0):
			continue
		# E nenhum bioma que o catálogo declara sem fauna. A chance da ROLAGEM
		# é lida onde o jogador está; o corpo nasce num raio que atravessa
		# fronteira, então sem este teste um jogador parado na beira do mar
		# raso semearia criaturas dentro do platô glacial — um bioma cuja nota
		# diz "nenhuma criatura nasce nem patrulha aqui".
		if _fauna_free(candidate):
			continue

		# A altura entra ANTES do teste de frustum, e a ordem importa: o
		# frustum é um volume 3D, e testar um ponto em y = 0 responderia pelo
		# lugar errado justamente perto de rampa e de borda, que é onde a
		# criatura apareceria na tela.
		if terrain:
			candidate.y = terrain.height_at(candidate)
		# O teste que impede o corpo de pipocar no quadro. É o frustum CORRENTE
		# da câmera, então continua certo se o zoom mudar — não há distância
		# mínima calibrada para um enquadramento específico para envelhecer.
		if _visible_with_margin(candidate):
			continue

		var ok := true
		for p in _current_positions():
			if candidate.distance_to(p) < min_separation:
				ok = false
				break
		if ok:
			return candidate
	return Vector3.INF


## Este ponto cai num bioma que o catálogo declara sem fauna?
##
## O keep-out deriva da PARTIÇÃO, não de um predicado geográfico novo — é a
## escolha que o `CLAUDE.md` deste repo já apontava como a boa entre as duas
## ("a segunda é a que não precisa de código novo a cada bioma"). Marcar um
## bioma como 0,00 no bestiário passa a bastar: o platô glacial e o mar
## profundo saíram assim, e o próximo sai sem tocar em GDScript.
##
## A margem cobre a DERIVA DE PATRULHA: uma criatura nascida rente à fronteira
## entra no bioma proibido sozinha em poucos segundos (`HOME_LEASH` é 8 m), e
## a nota do BIO-014 pede explicitamente "margem de keep-out cobrindo a deriva
## de patrulha". Mesmo número que o keep-out da costa já usa, pelo mesmo motivo.
const FAUNA_FREE_MARGIN := 3.0


func _fauna_free(point: Vector3) -> bool:
	if map_biomes == null or _db == null:
		return false
	if _db.biome_spawn_chance(map_biomes.biome_at(point)) <= 0.0:
		return true
	for offset in [
		Vector3(FAUNA_FREE_MARGIN, 0.0, 0.0), Vector3(-FAUNA_FREE_MARGIN, 0.0, 0.0),
		Vector3(0.0, 0.0, FAUNA_FREE_MARGIN), Vector3(0.0, 0.0, -FAUNA_FREE_MARGIN),
	]:
		if _db.biome_spawn_chance(map_biomes.biome_at(point + offset)) <= 0.0:
			return true
	return false


## O ponto está no quadro, OU perto o bastante da borda para a câmera alcançá-lo
## enquanto persegue o jogador? Infla o teste testando também quatro pontos a
## `FRUSTUM_MARGIN` ao redor — `is_position_in_frustum` responde sim/não sobre
## um ponto e não aceita folga, então a folga se constrói com mais pontos.
##
## Só os eixos X e Z: a margem é para cobrir deslocamento da câmera pelo mapa,
## que é horizontal. Sem câmera (bancada de teste) nada é visível, e o
## nascimento cai só nas outras regras.
func _visible_with_margin(point: Vector3) -> bool:
	if camera == null or not is_instance_valid(camera):
		return false
	if camera.is_position_in_frustum(point):
		return true
	for offset in [
		Vector3(FRUSTUM_MARGIN, 0.0, 0.0), Vector3(-FRUSTUM_MARGIN, 0.0, 0.0),
		Vector3(0.0, 0.0, FRUSTUM_MARGIN), Vector3(0.0, 0.0, -FRUSTUM_MARGIN),
	]:
		if camera.is_position_in_frustum(point + offset):
			return true
	return false


func _current_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for a in _actors:
		if is_instance_valid(a):
			out.append(a.global_position)
	return out


## Conta quanto cada criatura passou fora do quadro e poda quem estourou a
## carência. Voltar a aparecer zera o relógio — a conta é de tempo CONTÍNUO
## fora, não acumulado ao longo da vida.
func _update_frustum_grace(delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		return

	var expired: Array[CreatureActor] = []
	for a in _actors:
		if not is_instance_valid(a):
			continue
		if camera.is_position_in_frustum(a.global_position):
			_offscreen_time.erase(a)
			continue
		var t: float = float(_offscreen_time.get(a, 0.0)) + delta
		if t >= OFFSCREEN_GRACE_SEC:
			expired.append(a)
		else:
			_offscreen_time[a] = t

	for a in expired:
		remove_actor(a)


## Tira a criatura do mundo. Sem reposição agendada: quem repõe é o
## deslocamento do jogador, e um timer aqui seria uma segunda fonte de
## população discordando da primeira.
##
## Chamado tanto pela poda de frustum quanto pelo `EncounterDirector` no fim de
## um duelo — vitória e captura são a mesma operação daqui: o corpo sai. O que
## as diferencia (a captura entra no time) é assunto de lá.
func remove_actor(actor: CreatureActor) -> void:
	if actor == null:
		return
	_actors.erase(actor)
	_offscreen_time.erase(actor)
	if is_instance_valid(actor):
		actor.queue_free()
	population_changed.emit()


func _on_engaged(actor: CreatureActor) -> void:
	creature_engaged.emit(actor)


func actors() -> Array[CreatureActor]:
	return _actors
