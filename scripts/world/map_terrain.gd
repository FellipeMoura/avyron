class_name MapTerrain
extends StaticBody3D

## O chão do mapa com relevo: malha, colisão e a consulta de altura que os
## sistemas de chão plano usam para continuar corretos.
##
## O desenho do relevo é deliberado: o mapa inteiro é plano, num de dois
## níveis fixos (mar ou terra firme — ver "Dois níveis" abaixo), e a borda
## sobe num rim de contenção que fecha a leitura do mapa na câmera
## ortográfica. Relevo é apresentação com colisão, não labirinto: nada aqui
## deve criar rota bloqueada.
##
## Três exceções ao plano, as três de propósito: a COSTA na borda -Z, a ILHA
## no miolo (que carrega a arena) e o PLATÔ GLACIAL no canto -X/+Z
## (`on_glacial`). Quem assume chão plano perto da origem (spawn, encenação)
## tem de perguntar a altura, não presumir zero — a origem do mapa hoje é o
## topo da ilha.
##
## ## Dois níveis, não relevo contínuo (desde 2026-09-01)
##
## O mapa inteiro é só `SEA_HEIGHT` (mar) ou `LAND_HEIGHT` (terra firme) — sem
## ruído, sem colina, sem recife nem abismo com profundidade própria. Decisão
## deliberada do usuário: sacrificar a leitura de profundidade que o relevo
## contínuo dava, em troca de um gráfico mais controlado e (não por acaso) de
## cortar de raiz a classe de bug que o relevo contínuo produzia a sessão
## inteira — o Mar Profundo (`ABYSS_*`, removido) foi literalmente um poço sem
## saída por causa da própria rampa dele.
##
## ## O mar é raso de propósito (desde 2026-09-01, mesmo dia, segunda vez)
##
## `SEA_HEIGHT` fica só um pouco abaixo de `LAND_HEIGHT` — o bastante pra dar
## sensação de descer ao entrar na água, raso demais pra qualquer corpo
## precisar de empuxo pra não afundar. Isso substitui um sistema inteiro
## (`should_float`, o gatilho de flutuação do jogador e da companheira) que
## existiu só porque o leito tinha profundidade de verdade — três versões
## sucessivas do gatilho, cada uma consertando uma lacuna que a anterior
## abria (geografia sem altura, altura sem geografia, e por fim a mesma
## dissonância reaparecendo na rampa larga da costa). Com o leito sempre raso,
## a pergunta que o gatilho respondia deixa de fazer sentido — não existe leito
## fundo demais pra andar, então ninguém precisa flutuar. O jogador
## (`PlayerController`) e a companheira (`CompanionActor`) seguem o relevo
## pela colisão/consulta o tempo todo, dentro ou fora da terra firme —
## "nadar" no PZ-01 é a criatura andando no fundo raso do mar, quase na
## superfície, não um corpo boiando por cima dele.
##
## A transição entre os dois níveis só é andável nos `ACCESS_RAMPS` — fora
## deles, a borda de terra firme é parede (a diferença de altura, mesmo
## pequena, ainda é íngreme demais num único metro de grade pro
## `CharacterBody3D` escalar — é isso que faz o degrau continuar funcionando
## como portão). Corpos com física (jogador, criaturas selvagens) seguem o
## relevo pela colisão; "molhado" ou "seco" pra fins de mineração/bioma
## continua sendo geografia declarada (`on_dry_land`/`submerged`), não altura
## — ver os dois abaixo. Quem NÃO tem física (companheira, props do
## `MapDressing`, spawner sorteando posição) pergunta a altura via
## `height_at` — a resposta é interpolada da MESMA grade que gera malha e
## colisão, então visual, física e consulta nunca discordam.
##
## Substitui o `Ground` chapado de `main.tscn` em runtime (`WorldRoot`), com o
## mesmo nome de nó — `test_world` confere a existência de "Ground" e o clique
## de mundo continua batendo num StaticBody.

## ## O tamanho do mapa, e o que escala junto com ele
##
## `SIZE` saiu de 60 para 120 m em 2026-08-28, e a conta que decidiu o alvo
## está no ROADMAP: **30 s de travessia por bioma** a 5,2 m/s dão 156 m por
## bioma, que com cinco biomas pedem um mapa de 350 m. Os 120 m são a etapa
## intermediária — a maior que o acervo de props atual consegue vestir sem o
## mapa ler como deserto. O alvo continua sendo 350.
##
## Desde o corte pra dois níveis (2026-09-01), a regra de "o que escala com o
## mapa" ficou mais simples: as FORMAS em planta (`COAST_*`, `ISLAND_*`,
## `GLACIAL_*`) continuam proporção do lado, exatamente como antes — são
## bioma, e bioma que não cresce com o mapa encolhe até sumir. Altura não
## escala mais com nada, porque só existem duas (`SEA_HEIGHT`/`LAND_HEIGHT`) e
## as duas são constante fixa, não fração de área.
##
## Lado do mapa em metros (grade de 1 m — célula igual à do HeightMapShape3D,
## que fixa o espaçamento em 1 unidade; a 120 m são 14.641 vértices).
const SIZE := 120
## Altura extra do rim de borda, somada por cima do nível base — paredão
## visual na borda do mapa, independente de terra ou mar.
const RIM_HEIGHT := 3.5

## A costa: um platô raso na borda -Z — solo firme para NPCs e portais, sem
## bioma natural e sem spawn de criatura (spawner e MapDressing consultam
## `on_coast`). É um dos dois níveis fixos (`LAND_HEIGHT`); o rim de borda
## continua subindo atrás, como paredão de fundo.
##
## ## Por que a costa é um LOBO e não uma faixa
##
## Até 2026-08-28 a costa era faixa cheia: `smoothstep` puro sobre z, a
## largura inteira do mapa. O desenho espacial aprovado a redesenhou como um
## lobo — largo no topo, descendo só no meio —, e a forma daqui teve de
## acompanhar porque a partição de bioma e o relevo descrevem o MESMO lugar.
## Com a faixa mantida, 47% do chão SECO responderia "mar raso": o jogador de
## pé na areia dos cantos, e a mineração dizendo que ele está nadando.
##
## As constantes abaixo são a tradução, em metros, das duas regiões que o
## catálogo usa para a costa do PZ-01 — `RGN-001` (o retângulo que dá a
## largura) e `RGN-006` (o círculo que dá a barriga). Elas são o par em
## metros de coordenadas normalizadas, e é por isso que mudar uma sem
## reautorar a outra recria exatamente o buraco que esta rodada fechou.
##
## O centro do lobo fica na BORDA -Z, fora do mapa: é o que faz um círculo
## produzir margem de praia em vez de ilha redonda.
const COAST_CENTER_X := -4.2
const COAST_LOBE_R := 27.6
## Centro e meia-largura do retângulo, em metros — independentes do centro
## do círculo acima. Até 2026-08-31 os dois usavam a MESMA constante porque
## os dados do catálogo coincidiam por acaso (retângulo simétrico ao redor
## do mesmo x do círculo); a reautoria de `RGN-001` (só o lado +X) quebrou
## essa coincidência, e o retângulo passou a precisar do próprio centro.
const COAST_RECT_CENTER_X := 1.5
const COAST_RECT_HALF_W := 49.5
const COAST_RECT_Z := -43.2

## Largura do esmaecimento da forma da costa — ao contrário da ilha e do
## platô glacial, a COSTA é rampa andável na borda INTEIRA com o mar, não só
## em pontos de acesso (pedido do usuário, 2026-09-01: é o adro da vila,
## precisa de acesso amplo). Chegou a subir pra 12 m no mesmo dia, calibrada
## pra uma diferença de altura de 6,6 m entre os dois níveis — só que uma
## rampa larga sobre um leito com profundidade de verdade deixava boa parte
## do trajeto ainda "fundo demais" mesmo perto da areia (o gatilho de
## flutuação disparava a 5–6 m da terra seca). A correção de verdade não foi
## afinar a rampa — foi encolher `SEA_HEIGHT` até o mar não ter profundidade
## que justifique flutuação nenhuma (ver "O mar é raso de propósito" no
## cabeçalho). Com a diferença de hoje (2,0 m), 6 m de vão já dá folga de
## sobra pela mesma conta (`1,5 · diferença / vão ≤ 1`, precisa de só 3 m) e
## ainda lê como subida perceptível — 12 m ficaria quase plano.
const COAST_RAMP_WIDTH := 6.0

## O alcance MÁXIMO da costa mar adentro — o ponto mais fundo do lobo, na
## linha de centro dele. Continua existindo porque o shader, os testes e as
## notas do catálogo precisam de um número único para conferir contra; deixou
## é de ser a fronteira em toda largura, porque agora só vale no meio.
const COAST_RAMP_START := -60.0 + COAST_LOBE_R
const COAST_TOP := COAST_RAMP_START - COAST_RAMP_WIDTH

## A ilha: o único chão seco fora da costa e do platô glacial — um platô
## pequeno no MEIO do mapa, que carrega a arena (`WorldPopulator`). É também
## onde o domador abre o jogo, de pé, antes de descer para o mar.
##
## A ilha NÃO escala com o mapa: o tamanho dela é o de caber uma arena e um
## duelista, e isso não muda porque o mar em volta cresceu. `ISLAND_TOP_RADIUS`
## sobrevive ao corte de relevo contínuo (2026-09-01) só porque a arena
## (`WorldPopulator.ARENA_SPOT`) ainda precisa de um raio "topo plano" pra se
## confinar — não descreve mais rampa nenhuma, é raio inteiro de terra firme.
##
## `ISLAND_CENTER` é (x, z) no plano — o `y` do Vector2 é o Z do mundo.
const ISLAND_CENTER := Vector2(0.0, 0.0)
const ISLAND_TOP_RADIUS := 4.0
const ISLAND_BASE_RADIUS := 9.0

## O platô glacial (`RGN-004`, BIO-014) — terceira geografia declarada seca.
## Retângulo com cantos suavizados, batendo com a forma `rect` do catálogo.
## `GLACIAL_X0`/`GLACIAL_Z1` caem exatamente na borda do mapa (±60).
const GLACIAL_X0 := -60.0
const GLACIAL_X1 := -18.0
const GLACIAL_Z0 := 13.2
const GLACIAL_Z1 := 60.0
const GLACIAL_FEATHER := 10.0

## Margem entre a borda do terreno e o limite em que um corpo ainda pode ser
## posto. Além dos ±30 m da malha não há chão nenhum — nem visual, nem colisão,
## nem resposta de `height_at` que signifique alguma coisa —, e um corpo posto
## lá simplesmente cai. Dois metros cobrem o maior raio de cápsula do elenco
## (1,2 m) com folga.
const BOUNDS_MARGIN := 2.0

## Os dois níveis. `LAND_HEIGHT` mantém o valor que `COAST_HEIGHT` já usava —
## folga testada e aprovada sobre `PZ01_WATER_LINE` (1,25).
##
## `SEA_HEIGHT` era -5,0 (6,6 m abaixo da terra) até este mesmo dia pela
## segunda vez: fundo o bastante pra exigir um sistema de flutuação inteiro
## (`should_float`, removido) só pra ninguém afundar nele. Pedido do usuário:
## profundidade mínima, só a sensação de descer ao entrar na água — 2,0 m dá
## essa leitura (a cota fica pouco mais de 1,6 m acima do leito, raso o
## bastante pra qualquer corpo continuar em pé) sem sustentar mais nada que
## justifique empuxo. "Nadar" no PZ-01 virou andar no fundo raso do mar, quase
## na superfície — não boiar por cima dele.
const SEA_HEIGHT := -0.4
const LAND_HEIGHT := 1.6

## Pontos de acesso — [Vector2(x,z), ...] — onde a transição entre os dois
## níveis vira rampa andável de verdade. Só ILHA e PLATÔ GLACIAL usam isto: a
## COSTA é rampa na borda inteira (`COAST_RAMP_WIDTH`, acima), por pedido do
## usuário — é o adro da vila, precisa de acesso amplo, não só dois pontos.
## Fora de um raio `ACCESS_RAMP_RADIUS` de um destes pontos (ilha/glacial), a
## borda de terra firme é parede.
##
## 2 no platô glacial (as duas bordas que fazem fronteira com mar aberto), 1
## na ilha da arena (voltado pra costa — de onde o jogador nada de verdade
## pra chegar lá). Coordenadas medidas por sonda direta contra
## `_land_profile` (descartada), não calculadas à mão.
const ACCESS_RAMPS: Array[Vector2] = [
	Vector2(-22.0, 35.0),
	Vector2(-40.0, 16.0),
	Vector2(0.0, -9.0),
]
## Vão da rampa: raio "totalmente terra" (`INNER`) e raio "de volta ao mar
## aberto" (`OUTER`) — NÃO é o esmaecimento da forma da ilha/glacial
## (`GLACIAL_FEATHER` etc.), que não entra na altura (é hardenado, ver
## `_land_profile`). O vão certo pra ≤45° é `1,5 · diferença / vão`; com a
## diferença de hoje entre os dois níveis (2,0 m — ver `SEA_HEIGHT`), precisa
## de só 3 m. 6 m de vão (`OUTER - INNER`) dá folga de sobra e ainda lê como
## rampa de verdade, não uma diferença imperceptível.
const ACCESS_RAMP_INNER := 2.0
const ACCESS_RAMP_OUTER := 8.0

## Cota da superfície da água, injetada por quem veste o mapa
## (`MapDressing.water_line`). `-INF` = mapa seco, e aí nada está submerso —
## o padrão das bancadas de teste, que montam terreno sem bioma.
var water_line := -INF

var _heights: PackedFloat32Array
var _dim: int
## Guardado (não só repassado) porque `_glacial_profile` precisa dele em
## TODA chamada, não só na bakeada de malha/textura — inclusive consultas
## avulsas em runtime (`on_glacial`, via `on_dry_land`/`submerged`). Ver
## comentário de `_glacial_profile`.
var _map_biomes: MapBiomes


## `map_biomes`, quando fornecido, encolhe a área do platô glacial (relevo E
## cor) pra onde `biome_at` também responde BIO-014 — ver `_glacial_profile`.
## Omitido, o platô usa só o retângulo geométrico, inclusive onde uma região
## de sortOrder mais alto (o recife, hoje) reivindica o mesmo espaço primeiro.
static func create(palette: Dictionary, map_biomes: MapBiomes = null) -> MapTerrain:
	var t := MapTerrain.new()
	t._build(palette, map_biomes)
	return t


## Altura do terreno no ponto (bilinear sobre a grade). Fora do mapa devolve a
## altura da borda mais próxima — quem perguntar de fora não cai no vazio.
func height_at(world_pos: Vector3) -> float:
	var half := float(SIZE) * 0.5
	var gx := clampf(world_pos.x + half, 0.0, float(SIZE) - 0.001)
	var gz := clampf(world_pos.z + half, 0.0, float(SIZE) - 0.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - float(x0)
	var fz := gz - float(z0)
	var h00 := _heights[z0 * _dim + x0]
	var h10 := _heights[z0 * _dim + x0 + 1]
	var h01 := _heights[(z0 + 1) * _dim + x0]
	var h11 := _heights[(z0 + 1) * _dim + x0 + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


## Removido em 2026-09-01 (mesmo dia, segunda vez): o mar ficou raso demais
## pra qualquer corpo precisar de empuxo (ver "O mar é raso de propósito" no
## cabeçalho). Companheira (`CompanionActor._ground_y`) e jogador
## (`PlayerController`) agora seguem `height_at`/a colisão sem exceção,
## dentro ou fora da terra firme.


func _build(palette: Dictionary, map_biomes: MapBiomes = null) -> void:
	_map_biomes = map_biomes
	_dim = SIZE + 1
	_heights = PackedFloat32Array()
	_heights.resize(_dim * _dim)

	var half := float(SIZE) * 0.5
	for z in _dim:
		for x in _dim:
			var wx := float(x) - half
			var wz := float(z) - half
			_heights[z * _dim + x] = _height_formula(wx, wz)

	_add_mesh(palette)
	_add_collision()


## A fórmula do relevo. `r` em métrica de quadrado porque o mapa é quadrado:
## a distância ao centro tem de crescer igual em direção a lado e a canto,
## senão o rim afunda nos cantos.
func _height_formula(x: float, z: float) -> float:
	var r := maxf(absf(x), absf(z))
	var land := _land_profile(x, z)
	var h := lerpf(SEA_HEIGHT, LAND_HEIGHT, land)
	h += smoothstep(float(SIZE) * 0.5 - 5.0, float(SIZE) * 0.5, r) * RIM_HEIGHT
	return h


## 1 em terra firme, 0 em mar aberto. Três tratamentos diferentes, um por
## geografia:
##
## - COSTA: `_coast_profile` já É rampa suave na borda inteira
##   (`COAST_RAMP_WIDTH`, calibrado pra ≤45° na diferença cheia de hoje) —
##   usada direto, sem degrau. É o adro da vila, acesso amplo por pedido do
##   usuário.
## - ILHA e PLATÔ GLACIAL: degrau reto (`other_hard`) — leitura "controlada"
##   pedida no lugar de relevo contínuo — EXCETO onde um `ACCESS_RAMPS`
##   levanta rampa própria, com vão calibrado à parte (`ACCESS_RAMP_INNER`/
##   `OUTER`), porque o esmaecimento natural das formas delas (`GLACIAL_FEATHER`
##   etc.) também é estreito demais pra diferença de altura de hoje.
##
## O resultado é o máximo dos três: a rampa (de qualquer origem) levanta o
## mar até virar terra onde ela alcança, e o resto do mapa continua parede.
func _land_profile(x: float, z: float) -> float:
	var coast := _coast_profile(x, z)
	var other_raw := maxf(_island_profile(x, z), _glacial_profile(x, z))
	var other_hard := 1.0 if other_raw > 0.0 else 0.0
	return maxf(coast, maxf(other_hard, _access_ramp_profile(x, z)))


## A rampa própria de cada ponto de acesso: 1 dentro de `ACCESS_RAMP_INNER`
## do ponto (terra firme cheia), esmaecendo pra 0 em `ACCESS_RAMP_OUTER`
## (mar aberto de novo). Máximo entre todos os pontos.
func _access_ramp_profile(x: float, z: float) -> float:
	var v := 0.0
	for p in ACCESS_RAMPS:
		var d := Vector2(x, z).distance_to(p)
		v = maxf(v, 1.0 - smoothstep(ACCESS_RAMP_INNER, ACCESS_RAMP_OUTER, d))
	return v


## Ruído usado só pra desalinhar a BORDA das três formas de terra firme — não
## mais pra variar altura (ver "Dois níveis" no cabeçalho, essa função nunca
## entra na altura em si). Pedido do usuário, 2026-09-01: um círculo/retângulo
## matemático perfeito, amostrado numa grade de 1 m com transição íngreme (a
## diferença cheia entre os dois níveis, não mais um degrau suave de vários
## metros), lê como serrilhado/blocado — cada célula da grade decide sozinha
## "dentro" ou "fora" quase sem meio-termo, e o resultado tem cara de pixel
## art em vez de costa. Deformar o ESPAÇO (não a forma em si) antes de medir
## distância/limiar quebra essa regularidade sem desenhar geografia nova —
## um círculo vira uma mancha, mas continua reconhecível como a mesma região.
##
## Só entra nas TRÊS formas de terra firme (`_coast_profile`/`_island_profile`/
## `_glacial_profile`); `_access_ramp_profile` fica de fora de propósito — os
## pontos de acesso são posição deliberada, calibrada por sonda, e desalinhar
## a borda deles desalinharia a rampa que a mesma sonda mediu como andável.
const EDGE_NOISE_SEED := 20260901
const EDGE_NOISE_FREQUENCY := 0.05
## Era 3,5 na primeira tentativa — grande demais pra ilha (raio de base 9 m):
## quase 40% de distorção deixava a forma irreconhecível como círculo. 2,0 m
## ainda quebra a regularidade da borda sem descaracterizar a menor das três
## formas.
const EDGE_NOISE_AMPLITUDE := 2.0

var _edge_noise: FastNoiseLite


func _warp(x: float, z: float) -> Vector2:
	if _edge_noise == null:
		_edge_noise = FastNoiseLite.new()
		_edge_noise.seed = EDGE_NOISE_SEED
		_edge_noise.frequency = EDGE_NOISE_FREQUENCY
	# Duas amostras do mesmo ruído, deslocadas no domínio (não em frequência
	# nem semente), pra x e z desalinharem em direções diferentes — um único
	# valor aplicado aos dois eixos só esticaria a forma na diagonal, sem
	# quebrar a regularidade da borda.
	var wx := _edge_noise.get_noise_2d(x, z) * EDGE_NOISE_AMPLITUDE
	var wz := _edge_noise.get_noise_2d(x + 731.0, z - 731.0) * EDGE_NOISE_AMPLITUDE
	return Vector2(x + wx, z + wz)


## Quanto da ilha existe neste ponto: 1 dentro do raio da base, 0 fora. Antes
## do corte de relevo contínuo, media um platô com rampa própria (topo até
## `ISLAND_TOP_RADIUS`, descendo até `ISLAND_BASE_RADIUS`); agora é só a
## forma que alimenta `_land_profile`/`on_island` — a altura real vem de lá,
## mas o esmaecimento continua usando o mesmo vão de sempre.
func _island_profile(x: float, z: float) -> float:
	var w := _warp(x, z)
	var d := Vector2(w.x - ISLAND_CENTER.x, w.y - ISLAND_CENTER.y).length()
	return 1.0 - smoothstep(ISLAND_TOP_RADIUS, ISLAND_BASE_RADIUS, d)


## Retângulo com cantos suavizados: mínimo de duas rampas por eixo, cada uma
## subindo de um lado e descendo do outro — a mesma forma de um `rect` do
## catálogo, com esmaecimento (`GLACIAL_FEATHER`) nas quatro bordas em vez de
## corte reto.
##
## O retângulo (`RGN-004`) bate com o catálogo em metros, mas o círculo do
## recife (`RGN-002`, sortOrder mais alto) se sobrepõe geometricamente a um
## canto dele — nessa cunha, o PRÓPRIO JOGO responde recife quando consultado
## (`biome_at`), não glacial. Pedido do usuário, 2026-09-02: essa cunha vira
## água de verdade (relevo E cor), não só cor — o platô recua pra onde o
## bioma realmente é dele. `_map_biomes` (quando presente) filtra por cima do
## retângulo geométrico em vez de substituí-lo, então a borda nova é a
## INTERSECÇÃO das duas formas — o mesmo arco que já cortava a textura,
## agora cortando a malha também, sem duplicar geometria do recife aqui
## (mesma lição de sempre: geografia não se recalcula em dois lugares).
func _glacial_profile(x: float, z: float) -> float:
	var w := _warp(x, z)
	var fx := minf(
		smoothstep(GLACIAL_X0, GLACIAL_X0 + GLACIAL_FEATHER, w.x),
		1.0 - smoothstep(GLACIAL_X1 - GLACIAL_FEATHER, GLACIAL_X1, w.x))
	var fz := minf(
		smoothstep(GLACIAL_Z0, GLACIAL_Z0 + GLACIAL_FEATHER, w.y),
		1.0 - smoothstep(GLACIAL_Z1 - GLACIAL_FEATHER, GLACIAL_Z1, w.y))
	var profile := fx * fz
	if profile > 0.0 and _map_biomes and _map_biomes.biome_at(Vector3(x, 0.0, z)) != "BIO-014":
		return 0.0
	return profile


## Quanto da costa existe neste ponto: 1 no platô seco, 0 em mar aberto.
##
## É o MÁXIMO de duas formas, e as duas vêm do catálogo: o círculo da barriga
## e o retângulo da largura. Máximo e não soma porque as duas se sobrepõem no
## meio, e somar levantaria o platô ao dobro da altura justamente onde a vila
## fica.
##
## `margin` infla as três medidas ao mesmo tempo — é o que deixa o keep-out do
## spawner cobrir a deriva de patrulha sem precisar de uma segunda forma.
func _coast_profile(x: float, z: float, margin: float = 0.0) -> float:
	var warped := _warp(x, z)
	x = warped.x
	z = warped.y
	var half := float(SIZE) * 0.5
	var lobe_r := COAST_LOBE_R + margin
	var d := Vector2(x - COAST_CENTER_X, z + half).length()
	var lobe := 1.0 - smoothstep(lobe_r - COAST_RAMP_WIDTH, lobe_r, d)

	var rect_z := COAST_RECT_Z + margin
	var band := 1.0 - smoothstep(rect_z, rect_z + COAST_RAMP_WIDTH, z)
	var half_w := COAST_RECT_HALF_W + margin
	var side := 1.0 - smoothstep(half_w - COAST_RAMP_WIDTH, half_w,
		absf(x - COAST_RECT_CENTER_X))
	return maxf(lobe, band * side)


## O lobo da costa, rampa incluída. `margin` estende a checagem mar adentro —
## o spawner usa para o keep-out cobrir também a deriva de patrulha.
##
## Deixou de ser `z <= COAST_RAMP_START` quando a costa virou lobo: aquele
## teste respondia "costa" para a largura inteira do mapa, e passaria a mentir
## nos dois cantos do topo, que agora são mar. Quem responde é a mesma forma
## que levanta a malha — não há segunda descrição da costa para divergir.
func on_coast(world_pos: Vector3, margin: float = 0.0) -> bool:
	return _coast_profile(world_pos.x, world_pos.z, margin) > 0.0


## A ilha, saia submersa incluída — o par de `on_coast`, e usado pelos mesmos
## sistemas: o spawner mantém criatura fora dela, o `MapDressing` não espalha
## coral em terra seca, e `submerged` a deixa negociar com a cota.
##
## O raio é o da BASE, não o da linha d'água: o trecho entre a base e a praia
## está debaixo d'água e continua respondendo pela altura, exatamente como o
## pé da rampa da costa. `margin` estende o keep-out mar adentro.
func on_island(world_pos: Vector3, margin: float = 0.0) -> bool:
	var d := Vector2(world_pos.x - ISLAND_CENTER.x, world_pos.z - ISLAND_CENTER.y).length()
	return d <= ISLAND_BASE_RADIUS + margin


## O platô glacial (`RGN-004`, BIO-014) — terceira geografia declarada seca,
## desde 2026-09-01. Até então `GLACIAL_*` só levantava relevo decorativo
## sobre um leito que `submerged()` continuava tratando como sempre molhado
## (a mesma regra "recife não é ilhota"); a partir de agora o platô negocia
## com a cota como a costa e a ilha — pedido do usuário, porque um bioma com
## fauna e minério próprios (ver `CLAUDE.md`, minério glacial exclusivo) lendo
## como fundo de mar contradizia o resto do design.
##
## Sem `margin`: ao contrário de `on_coast`/`on_island`, ainda não existe
## consumidor pedindo keep-out mar adentro aqui — spawner e `MapDressing`
## continuam livres para usar o platô (é bioma de fauna, não adro de NPC).
## Adicionar o parâmetro sem chamador é complexidade especulativa.
func on_glacial(world_pos: Vector3) -> bool:
	return _glacial_profile(world_pos.x, world_pos.z) > 0.0


## Toda geografia seca declarada — o funil único que `submerged()` consulta e
## que qualquer outro sistema com a mesma pergunta ("aqui é sempre molhado,
## não importa a altura?") deve usar em vez de repetir a lista à mão.
##
## Inclui `_access_ramp_profile`, não só as três formas: sem isso, o relevo já
## levantava o chão até `LAND_HEIGHT` na rampa (`_land_profile` já soma a
## rampa), mas `on_dry_land` continuava dizendo "não é terra firme" ali — a
## mineração leria o jogador como submerso em pé em chão seco de verdade. O
## corpo em si nunca flutuou por causa disso (`should_float`, removido, não
## consultava geografia) — mas geografia e altura ainda precisam concordar
## aqui, porque `submerged()` (mineração, bioma) depende só desta função.
func on_dry_land(world_pos: Vector3) -> bool:
	if on_coast(world_pos) or on_island(world_pos) or on_glacial(world_pos):
		return true
	return _access_ramp_profile(world_pos.x, world_pos.z) > 0.0


## Este ponto está debaixo d'água?
##
## **Fora da costa, da ilha e do platô glacial a resposta é sempre sim**,
## independentemente da altura: o PZ-01 é o leito de um mar, e um recife que
## sobe 2,5 m continua sendo recife, não ilhota. Só esses três lugares
## negociam com a cota — são os três em que a rampa atravessa a superfície no
## meio da subida, exatamente como a névoa já conta.
##
## Testar só a altura seria a outra leitura possível, e foi descartada: 315 das
## células do anel externo passam da cota por causa das colinas, e o jogador
## emergiria de pé no meio do recife em cada uma delas. Terra firme de verdade
## é geografia declarada (`on_dry_land`), não altura que calhou de passar da
## cota — foi essa distinção que fez a ilha (e agora o platô glacial)
## precisar de predicado próprio em vez de afrouxar a regra para todo mundo.
func submerged(world_pos: Vector3) -> bool:
	if is_inf(water_line):
		return false
	if not on_dry_land(world_pos):
		return true
	return world_pos.y < water_line



## Traz um ponto para dentro do terreno, no plano. Quem move corpo por conta
## própria — hoje só a `BattleStaging`, que empurra os três combatentes com a
## física pausada — passa por aqui antes de escrever a posição.
##
## Existe porque o posto do domador é derivado para FORA do par (atrás da
## própria criatura, no sentido oposto ao adversário): um duelo engatado perto
## da borda de spawn projetava esse posto além da malha, e o jogador ia junto.
## O Y passa intocado — quem chama decide a altura, e a regra de apoio é de
## cada corpo.
func clamp_to_bounds(world_pos: Vector3) -> Vector3:
	var limit := float(SIZE) * 0.5 - BOUNDS_MARGIN
	return Vector3(
		clampf(world_pos.x, -limit, limit),
		world_pos.y,
		clampf(world_pos.z, -limit, limit),
	)


## Bakeia a MESMA máscara (com `_warp` E o filtro de bioma inclusos — ver
## `_glacial_profile`) que `_land_profile` usa pra decidir o degrau reto do
## platô glacial — reaproveitada por `terrain_ground.gdshader` pra alinhar a
## textura de gelo pixel a pixel com a geografia real. Um retângulo
## recalculado no shader, sem o warp/filtro da malha, foi a causa de defeitos
## que pareciam coisas diferentes (marrom por cima de gelo andável, borda
## quadrada demais, textura em chão que o painel rotula doutro bioma): todos
## eram o mesmo descompasso entre a borda que a COR desenhava e a borda que
## `_glacial_profile` já desenhava. Mesma técnica do `heightmap_tex` da água
## — bake da grade em textura em vez de reformular a fórmula no shader.
func _build_glacial_mask_tex() -> ImageTexture:
	var half := float(SIZE) * 0.5
	var mask := PackedFloat32Array()
	mask.resize(_dim * _dim)
	for z in _dim:
		for x in _dim:
			var wx := float(x) - half
			var wz := float(z) - half
			mask[z * _dim + x] = 1.0 if _glacial_profile(wx, wz) > 0.0 else 0.0
	var img := Image.create_from_data(_dim, _dim, false, Image.FORMAT_RF, mask.to_byte_array())
	return ImageTexture.create_from_image(img)


func _add_mesh(palette: Dictionary) -> void:
	var half := float(SIZE) * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(_dim * _dim)
	normals.resize(_dim * _dim)

	for z in _dim:
		for x in _dim:
			var i := z * _dim + x
			vertices[i] = Vector3(float(x) - half, _heights[i], float(z) - half)
			# Normal por diferenças centrais na própria grade — suave e
			# consistente com a colisão, sem depender de generate_normals
			# (que em malha não indexada sairia facetado).
			var hl := _grid_height(x - 1, z)
			var hr := _grid_height(x + 1, z)
			var hd := _grid_height(x, z - 1)
			var hu := _grid_height(x, z + 1)
			normals[i] = Vector3(hl - hr, 2.0, hd - hu).normalized()

	for z in SIZE:
		for x in SIZE:
			var i := z * _dim + x
			# Ordem HORÁRIA vista de cima: é a frente no Godot (ao contrário
			# do padrão OpenGL). Na ordem inversa o chão inteiro é culled e o
			# mapa aparece flutuando sobre o fundo.
			indices.append_array([i, i + 1, i + _dim, i + 1, i + _dim + 1, i + _dim])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = FastNoiseLite.new()
	noise_tex.seamless = true
	noise_tex.width = 256
	noise_tex.height = 256

	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain_ground.gdshader")
	material.set_shader_parameter("noise_tex", noise_tex)
	# A geografia vai para o shader daqui, e não como default do `.gdshader`,
	# porque ela é do terreno: a faixa seca pintada tem de ser a MESMA que a
	# malha levantou.
	# As bandas da costa deixaram de viver como default do `.gdshader` no
	# resize de 2026-08-28, e o comentário abaixo já previa o momento: elas são
	# GEOGRAFIA, e geografia é deste arquivo. Deixadas lá, a faixa de areia
	# seca continuaria pintada a 14–19 m da borda enquanto o platô real subiu
	# para 32 — a tinta ficaria no meio do mar, e o mapa acusaria em imagem um
	# lugar que a malha não tem.
	#
	# A costa virou lobo, então a tinta da areia seca deixou de ser banda de Z
	# e passou a ser a MESMA forma composta que levanta a malha. Mandar as
	# quatro medidas em vez de dois limiares é o preço de a praia ter contorno.
	material.set_shader_parameter("coast_center_x", COAST_CENTER_X)
	material.set_shader_parameter("coast_lobe_r", COAST_LOBE_R)
	material.set_shader_parameter("coast_rect_z", COAST_RECT_Z)
	material.set_shader_parameter("coast_rect_center_x", COAST_RECT_CENTER_X)
	material.set_shader_parameter("coast_rect_half_w", COAST_RECT_HALF_W)
	material.set_shader_parameter("coast_feather", COAST_RAMP_WIDTH)
	material.set_shader_parameter("map_half", float(SIZE) * 0.5)
	material.set_shader_parameter("island_center", ISLAND_CENTER)
	material.set_shader_parameter("island_top_radius", ISLAND_TOP_RADIUS)
	material.set_shader_parameter("island_base_radius", ISLAND_BASE_RADIUS)
	# Textura de chão do platô glacial (BIO-014) e da costa (BIO-002) — mesma
	# geografia que já levanta o relevo (`GLACIAL_*`/`COAST_*`), só espelhada
	# pro shader como fez a costa antes: geografia é deste arquivo, cor é do
	# `.gdshader`.
	material.set_shader_parameter("ice_tex", load("res://textures/terrain/ice_diffuse.png"))
	material.set_shader_parameter("glacial_mask_tex", _build_glacial_mask_tex())
	material.set_shader_parameter("mud_tex", load("res://textures/terrain/mud_diffuse.png"))
	material.set_shader_parameter("beach_tex", load("res://textures/terrain/beach_diffuse.png"))
	for key in palette:
		material.set_shader_parameter(key, palette[key])
	mesh.surface_set_material(0, material)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	add_child(mi)


func _grid_height(x: int, z: int) -> float:
	return _heights[clampi(z, 0, _dim - 1) * _dim + clampi(x, 0, _dim - 1)]


func _add_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = _dim
	shape.map_depth = _dim
	shape.map_data = _heights
	var col := CollisionShape3D.new()
	col.name = "Collision"
	col.shape = shape
	add_child(col)


## Espelho d'água na cota do bioma — plano único cobrindo o mapa inteiro, com
## a MESMA grade de altura do relevo levada ao shader como textura (ver
## `shaders/terrain_water.gdshader`), pra profundidade/espuma lerem o leito
## real sem precisar de depth-buffer de tela (que não se dá bem com câmera
## ortográfica).
##
## Chamado por quem injeta `water_line` (`WorldRoot`, logo depois de
## `MapDressing.water_line`) — não dentro de `_build()`, porque a cota ainda
## não existe nesse ponto (`water_line` começa em `-INF` e só é escrita por
## fora, depois de `create()`). Mapa sem água não ganha malha nenhuma.
func build_water_mesh() -> void:
	if is_inf(water_line):
		return

	var heightmap := Image.create_from_data(_dim, _dim, false, Image.FORMAT_RF, _heights.to_byte_array())
	var heightmap_tex := ImageTexture.create_from_image(heightmap)

	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain_water.gdshader")
	material.set_shader_parameter("heightmap_tex", heightmap_tex)
	material.set_shader_parameter("map_half", float(SIZE) * 0.5)
	material.set_shader_parameter("map_size", float(SIZE))
	material.set_shader_parameter("water_line", water_line)
	material.set_shader_parameter("water_tex", load("res://textures/terrain/water_diffuse.png"))

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(SIZE, SIZE)
	mesh.subdivide_width = 40
	mesh.subdivide_depth = 40
	mesh.material = material

	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = mesh
	mi.position = Vector3(0.0, water_line, 0.0)
	# Lâmina fina, sem sombra própria — sombra projetada numa superfície
	# semitransparente lê como mancha escura flutuando, não como volume.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Sem `CollisionShape3D` de propósito: é malha visual, não física. Clique
	# e movimento continuam decidindo "molhado" por `on_dry_land`/`submerged`
	# (geografia + altura), nunca pela existência desta lâmina — ela só
	# desenha o que aqueles predicados já decidiram.
	add_child(mi)
