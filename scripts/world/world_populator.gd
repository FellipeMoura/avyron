class_name WorldPopulator
extends RefCounted

## Instancia tudo que existe no mapa na abertura: comerciantes, posto do
## Relicário, arenas, guardião do portal, a companheira e o relicário inicial
## do jogador. Roda uma vez, a partir de `WorldRoot._ready()`, e não guarda
## estado depois de povoar — por isso é `RefCounted` com métodos `static`,
## mesmo padrão de `MiningTable`/`LootTable`: função pura de entrada e saída,
## sem instância para carregar.
##
## Quem decide o que fazer quando um desses atores é engatado continua sendo
## `WorldRoot` (ou `EncounterDirector`) — este arquivo só cria e devolve; a
## conexão do sinal `engaged` é passada de fora via `Callable`.

## Onde o comerciante fica: na COSTA — o platô da borda -Z que o `MapTerrain`
## reserva para NPCs e portais, sem bioma natural e sem spawn de criatura.
## Posição de cena, não de bestiário: o catálogo diz quem existe e em que
## mapa, o layout do mundo diz onde. O `y` das consts é 0 de propósito: quem
## resolve a altura é o terreno, na hora de spawnar.
const MERCHANT_SPOT := Vector3(4.0, 0.0, -23.0)

## Idem, pro posto do Relicário — depositar/retirar do storage e trocar de
## modelo só funcionam perto daqui (documento `relicario`: "exige estar em
## um ponto fixo"). Vizinho do comerciante na costa: os serviços do mapa
## ficam na mesma "vila" de praia.
const RELIC_STATION_SPOT := Vector3(8.5, 0.0, -23.0)

## Idem, pra arena e pro guardião do portal (documento `glifos-e-portais`).
## Guardião fica mais longe dos outros pontos de interação — ele marca a
## borda do mapa, não um serviço no meio dele.
##
## A arena fica no topo da ILHA (`MapTerrain.ISLAND_*`), o único chão seco
## fora da vila da costa: um platô de 8 m de diâmetro cercado de mar, que é a
## imagem que "arena" pede e que a costa — adro de loja e portal — não dava.
## O `x`/`z` tem de caber no topo plano (raio 4 m); o `y` continua 0 porque
## quem resolve altura é o terreno, na hora de spawnar.
const ARENA_SPOT := Vector3(0.0, 0.0, -2.8)
const PORTAL_SPOT := Vector3(-6.0, 0.0, -14.0)

## Conteúdo da arena única desta era: contra quem o jogador luta, em que
## nível, e qual Glifo a vitória concede. Fixo em código pelo mesmo motivo
## de `starter_code` em `WorldRoot` — o catálogo descreve que existe um
## duelista (`role = duelist`), não qual criatura específica ele usa.
## `CRT-021` (Inostrancevia) é `hero`/Theria, um dos predadores de topo já
## cadastrados — leitura natural de "campeão da arena" dentre o elenco
## existente.
const ARENA_OPPONENT_CODE := "CRT-021"
const ARENA_OPPONENT_LEVEL := 18
const ARENA_GRANTS_GLYPH := "DALETH"

## O que o guardião exige e para onde ele levaria — só a exibição, ver
## `PortalGuardianActor.can_pass()` para a checagem em si.
const PORTAL_REQUIRED_GLYPH := "DALETH"
const PORTAL_DESTINATION_LABEL := "Titanor"


## Instancia os comerciantes que o bestiário coloca neste mapa. Zero é estado
## normal — um mapa sem comerciante é um mapa sem comerciante, não um erro.
static func spawn_merchants(
	parent: Node3D, db: BestiaryData, map_code: String, on_engaged: Callable,
	terrain: MapTerrain = null
) -> Array[MerchantActor]:
	var merchants: Array[MerchantActor] = []
	if db == null:
		return merchants
	var spot := MERCHANT_SPOT
	for data in db.merchants_in_map(map_code):
		if terrain:
			spot.y = terrain.height_at(spot)
		var actor := MerchantActor.create(data, spot)
		actor.name = "Merchant_%s" % str(data.get("code", ""))
		actor.engaged.connect(on_engaged)
		parent.add_child(actor)
		merchants.append(actor)
		# Segundo comerciante no mesmo mapa fica ao lado do primeiro em vez de
		# dentro dele. Provisório até haver vilarejo com posições próprias.
		spot += Vector3(2.5, 0.0, 0.0)
	return merchants


## Um posto só por mapa, sempre presente — ao contrário do comerciante, não é
## dado do bestiário (não existe `npc_role` pra isso ainda), então não há
## "zero é normal" aqui: sem storage não há como esvaziar slots pra trocar de
## modelo, e essa regra do design doc precisa de um lugar pra valer.
static func spawn_relic_station(
	parent: Node3D, on_engaged: Callable, terrain: MapTerrain = null
) -> RelicStationActor:
	var spot := RELIC_STATION_SPOT
	if terrain:
		spot.y = terrain.height_at(spot)
	var station := RelicStationActor.create(spot)
	station.name = "RelicStation"
	station.engaged.connect(on_engaged)
	parent.add_child(station)
	return station


## Instancia os duelistas de arena que o bestiário coloca neste mapa
## (`role = duelist`, documento `glifos-e-portais`). Zero é normal, mesmo
## raciocínio de `spawn_merchants` — hoje só existe um nesta era.
static func spawn_arenas(
	parent: Node3D, db: BestiaryData, map_code: String, on_engaged: Callable,
	terrain: MapTerrain = null
) -> Array[ArenaActor]:
	var arenas: Array[ArenaActor] = []
	if db == null:
		return arenas
	var spot := ARENA_SPOT
	for data in db.duelists_in_map(map_code):
		# A altura vem do terreno como já vinha para o comerciante. Deixou de
		# ser opcional quando a arena subiu na ilha: `ground_on_spot()` SOMA
		# meia altura ao `y` do spot, então com `y = 0` o duelista nasceria
		# 2,6 m dentro do platô.
		if terrain:
			spot.y = terrain.height_at(spot)
		var actor := ArenaActor.create(
			data, spot, ARENA_OPPONENT_CODE, ARENA_OPPONENT_LEVEL, ARENA_GRANTS_GLYPH)
		actor.name = "Arena_%s" % str(data.get("code", ""))
		actor.engaged.connect(on_engaged)
		parent.add_child(actor)
		arenas.append(actor)
		spot += Vector3(2.5, 0.0, 0.0)
	return arenas


## Um guardião só, sempre presente — igual ao posto do Relicário, não é dado
## do bestiário (sem `npc_role` que sirva ainda). Fixo nesta era: é ele quem
## bloqueia a progressão até Titanor.
static func spawn_portal_guardian(
	parent: Node3D, progress: PlayerProgress, on_engaged: Callable,
	terrain: MapTerrain = null
) -> PortalGuardianActor:
	# Hoje o posto dele está em chão de altura zero e o terreno não muda nada;
	# entra pelo mesmo caminho da arena porque o ROADMAP prevê mudá-lo para a
	# costa, e lá a altura deixa de ser zero.
	var spot := PORTAL_SPOT
	if terrain:
		spot.y = terrain.height_at(spot)
	var guardian := PortalGuardianActor.create(
		spot, PORTAL_REQUIRED_GLYPH, PORTAL_DESTINATION_LABEL, progress)
	guardian.name = "PortalGuardian"
	guardian.engaged.connect(on_engaged)
	parent.add_child(guardian)
	return guardian


## Sem player não faz sentido spawnar quem segue; sem bestiário não temos
## como resolver o código do starter em cor/tamanho.
static func spawn_companion(
	parent: Node3D, db: BestiaryData, roster: PlayerRoster, player: Node3D
) -> CompanionActor:
	if player == null or db == null:
		return null
	var companion := CompanionActor.create(db, roster.active(), player)
	if companion == null:
		return null
	companion.name = "Companion"
	parent.add_child(companion)
	return companion


## Procura no bundle um modelo de Relicário neutro — sem `element`, sem
## `class` — para equipar o jogador de saída. `null` sem bestiário.
##
## Hoje **nenhum modelo assim existe no catálogo**: RLC-001/002/003 têm
## elemento e classe fixos (e `slotCapacity = 3`, não 2). Isto não é algo que
## este jogo deva resolver inventando um código local — o bundle exportado é
## a fonte de verdade (ver cabeçalho de `BestiaryData`), e duplicar o modelo
## aqui divergiria dele na primeira reexportação.
##
## O que falta do lado do avyron-bestiary, para desbloquear isto:
##   1. Schema: `relics.elementId`/`relics.classId` hoje são `NOT NULL`
##      (`packages/db/src/schema/relics.ts`) — precisam aceitar ausência,
##      mesmo padrão que `abilities.elementCode` já usa para golpe sem
##      afinidade.
##   2. API: `CreateRelicBodySchema` (`RelicsTypes.ts`) exige
##      `elementCode`/`classCode` como string — precisam virar opcionais.
##   3. Um novo relic model via `POST /relics` + `POST /relic-stats`, com:
##        code, name          — únicos, como qualquer relic
##        elementCode         — ausente (null)
##        classCode           — ausente (null)
##        slotCapacity        — 2
##        baseCaptureRate, captureRatePerLevel, maxLevel
##                            — tuning em aberto, qualquer valor razoável serve
##   4. `pnpm game:export` para o bundle pegar o modelo novo.
##
## Até isso existir, o jogador entra sem relicário equipado — captura fica
## indisponível (mesmo tratamento que já existe para "nenhum relicario
## equipado" em `DuelScreen._try_capture`), e o aviso abaixo torna o motivo
## visível no log em vez de falhar em silêncio.
static func pick_starter_relic(db: BestiaryData) -> PlayerRelic:
	if db == null:
		return null
	for code in db.relic_codes():
		var r := db.relic(code)
		if BestiaryData.relic_element_code(r) == "" and BestiaryData.relic_class_code(r) == "":
			return PlayerRelic.from_bestiary(db, code)
	push_warning(
		"WorldPopulator: sem relicario neutro (sem elemento/classe) no catalogo — " +
		"o starter precisa ser criado no avyron-bestiary (ver comentario de " +
		"pick_starter_relic). Jogador comeca sem relicario equipado."
	)
	return null
