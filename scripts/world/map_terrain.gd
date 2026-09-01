class_name MapTerrain
extends StaticBody3D

## O chão do mapa com relevo: malha, colisão e a consulta de altura que os
## sistemas de chão plano usam para continuar corretos.
##
## O desenho do relevo é deliberado: a PLANÍCIE CENTRAL é plana (altura 0) até
## `FLAT_RADIUS`, e é lá que vive todo o gameplay que assume plano — pontos do
## `WorldPopulator`, encenação de duelo. As colinas só crescem dali para fora,
## e a borda sobe num rim de contenção que fecha a leitura do mapa na câmera
## ortográfica. Relevo é apresentação com colisão, não labirinto: nada aqui
## deve criar rota bloqueada.
##
## Três exceções ao plano, as três de propósito e as três com rampa andável: a
## COSTA na borda -Z, a ILHA no miolo (que carrega a arena) e, desde
## 2026-09-01, o PLATÔ GLACIAL no canto -X/+Z (`on_glacial`). Quem assume chão
## plano perto da origem (spawn, encenação) tem de perguntar a altura, não
## presumir zero — a origem do mapa hoje é o topo da ilha, a 2,6 m.
##
## Corpos com física (jogador, criaturas selvagens — `CharacterBody3D` com
## gravidade) seguem o relevo pela colisão, sem consulta — DENTRO da geografia
## seca (`on_dry_land`). Fora dela é sempre mar, por design (`submerged`), e o
## jogador (`PlayerController._floating`) flutua na cota em vez de seguir a
## colisão até o leito — sem isso, o Mar Profundo (`ABYSS_*`, 15 m abaixo da
## cota) vira poço sem saída: a rampa dele é íngreme demais para escalar de
## volta andando. Quem NÃO tem física (companheira, props do `MapDressing`,
## spawner sorteando posição) pergunta a altura via `height_at` — a resposta é
## interpolada da MESMA grade que gera malha e colisão, então visual, física e
## consulta nunca discordam.
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
## Por isso o que importa aqui não é o número, é a REGRA de quem o acompanha.
## Cada constante deste arquivo cai em um de dois grupos, e trocar de grupo
## por engano é o que quebra o mapa:
##
## **Escalam com o mapa** (proporção do lado — mexer no `SIZE` exige mexer
## nelas na mesma razão): `FLAT_RADIUS`, `COAST_RAMP_START`. São feições
## cujo PAPEL é ocupar uma fração do mapa — a planície central e a faixa da
## costa são biomas, e bioma que não cresce com o mapa encolhe até sumir.
##
## **Têm tamanho próprio** (não escalam): `HILL_HEIGHT`, `RIM_HEIGHT`,
## `COAST_HEIGHT`, a LARGURA da rampa da costa, a ilha inteira e o
## `BOUNDS_MARGIN`. Altura não escala com área — uma colina de 2,5 m num mapa
## maior continua sendo uma colina de 2,5 m. A largura da rampa é conta de
## inclinação, não de estética. E a ilha cabe uma arena: dobrá-la daria um
## platô de 36 m de diâmetro para um duelista só.
##
## O terceiro grupo é implícito e já estava certo: o que é escrito em função
## de `SIZE` (o rim, o limite externo das colinas) acompanha sozinho.
##
## Lado do mapa em metros (grade de 1 m — célula igual à do HeightMapShape3D,
## que fixa o espaçamento em 1 unidade; a 120 m são 14.641 vértices).
const SIZE := 120
## Raio (em métrica de quadrado, max(|x|,|z|)) da zona plana central.
## ESCALA com o mapa — era 16 num mapa de 60.
## A zona central foi ampliada para deixar mais ar no mar raso e reforçar a
## leitura do abismo à direita sem transformar o centro em massa rochosa.
const FLAT_RADIUS := 38.0
## Altura máxima das colinas na zona externa.
const HILL_HEIGHT := 2.5
## Altura extra do rim de borda, somada por cima das colinas.
const RIM_HEIGHT := 3.5
## Semente do relevo — fixa pelo mesmo motivo do `spawn_seed` do spawner.
const TERRAIN_SEED := 20260824

## A costa: um platô raso na borda -Z — solo firme para NPCs e portais, sem
## bioma natural e sem spawn de criatura (spawner e MapDressing consultam
## `on_coast`). O leito sobe em rampa e assenta plano em `COAST_HEIGHT`; as
## colinas são suprimidas nela (o platô é limpo de propósito) e o rim de borda
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

## Largura da rampa, em metros. NÃO escala com o mapa: junto com
## `COAST_HEIGHT` ela é a inclinação que o corpo sobe — 1,5 · 1,6 / 5 dá 26°,
## dentro dos 45° que o `CharacterBody3D` aceita como piso. Encurtar sem
## refazer a conta transforma a praia em degrau.
const COAST_RAMP_WIDTH := 5.0
const COAST_HEIGHT := 1.6

## O alcance MÁXIMO da costa mar adentro — o ponto mais fundo do lobo, na
## linha de centro dele. Continua existindo porque o shader, os testes e as
## notas do catálogo precisam de um número único para conferir contra; deixou
## é de ser a fronteira em toda largura, porque agora só vale no meio.
const COAST_RAMP_START := -60.0 + COAST_LOBE_R
const COAST_TOP := COAST_RAMP_START - COAST_RAMP_WIDTH

## A ilha: o único chão seco fora da costa — um platô pequeno no MEIO do mapa,
## que emerge da planície central e carrega a arena (`WorldPopulator`). É
## também onde o domador abre o jogo, de pé, antes de descer para o mar.
##
## O topo é plano até `ISLAND_TOP_RADIUS` e desce em rampa até morrer em
## `ISLAND_BASE_RADIUS`. A largura dessa rampa não é estética: a inclinação
## máxima de um `smoothstep` é `1,5 · altura / vão`, e com 2,6 m em 5 m de vão
## dá 38°, abaixo dos 45° que o `CharacterBody3D` do Godot aceita como piso.
## Encurtar o vão (ou levantar a ilha) sem refazer essa conta transforma a
## ilha em parede — e uma parede aqui tranca a arena, que é justamente o que
## o cabeçalho proíbe.
##
## A ilha NÃO escala com o mapa: o tamanho dela é o de caber uma arena e um
## duelista, e isso não muda porque o mar em volta cresceu. O efeito de manter
## o número enquanto o mapa dobra é justamente o certo — uma ilha deve ser
## pequena em relação ao mar, e a de 60 m era grande demais para isso.
##
## `ISLAND_CENTER` é (x, z) no plano — o `y` do Vector2 é o Z do mundo.
const ISLAND_CENTER := Vector2(0.0, 0.0)
const ISLAND_TOP_RADIUS := 4.0
const ISLAND_BASE_RADIUS := 9.0
const ISLAND_HEIGHT := 2.6

## Relevo macro do PZ-01, um por bioma do catálogo (menos a costa e a ilha,
## que têm bloco próprio acima). Até 2026-08-31 estas quatro formas vinham de
## uma leitura livre de concept art, sem relação com `map_biome_regions` — o
## relevo visível e a partição que a mineração consulta apontavam para
## lugares diferentes do mapa. A partir da reautoria de geografia macro desta
## data, cada forma é a MESMA região do catálogo, convertida para metros
## (normalizado × meio-lado do mapa): `REEF_*` é `RGN-002` (BIO-003, Jardins
## Recifais), `GLACIAL_*` é `RGN-004` (BIO-014, Plataforma Glacial),
## `ABYSS_*` é `RGN-007` (BIO-004, Mar Profundo). Mudar uma sem reautorar a
## região correspondente reabre exatamente esse furo.
##
## A altura de cada forma (`REEF_HEIGHT`, `GLACIAL_HEIGHT`, `ABYSS_DEPTH`)
## continua sendo decisão só deste arquivo — o catálogo não descreve relevo,
## só a partição em planta (x/z). É apresentação (Camada A na terminologia
## do plano de refinamento), livre para ajustar sem tocar em dado — com a
## MESMA ressalva já registrada para `REEF_HEIGHT`: `GLACIAL_HEIGHT` também
## responde por `on_glacial`/`submerged` (ver abaixo), então não é livre de
## baixar sem checar a folga sobre `PZ01_WATER_LINE`.
const REEF_CENTER := Vector2(-24.0, 0.0)
const REEF_RADIUS := 28.2
## Era 4,8 até 2026-08-31. O novo centro do recife (aprovado, `RGN-002`) fica
## a 24 m da origem — dentro do próprio raio, então a franja do recife agora
## alcança a orla da ilha (a 9 m da origem). `submerged()` trata recife como
## sempre molhado FORA de costa/ilha, então a altura do recife nunca decide
## nada por si só — só nos pontos que também são `on_island`/`on_coast`, onde
## a altura crua é o que resolve `submerged`. 4,8 m ali empurrava a orla da
## ilha para cima da linha d'água por acidente; 3,0 m mantém a folga que
## `test_world.gd` cobra (a orla continua molhada) sem mudar o alcance em
## planta do recife, que é o que o catálogo define.
const REEF_HEIGHT := 3.0
## Início (em x) e largura da transição do abismo, mais a cota abaixo da qual
## ele passa a valer — os três batem com `RGN-007`: `x0 = 0.3 · 60 = 18`,
## `z0 = -0.6 · 60 = -36`. O gate em `z` é novo: sem ele, o abismo (função só
## de x até 2026-08-31) descia a faixa seca da costa onde ela cruza x > 18 —
## um corte que já existia por baixo do platô antes desta rodada, e que o
## alargamento da costa (`COAST_RECT_HALF_W`) só pioraria se não fosse
## corrigido junto.
const ABYSS_X0 := 18.0
const ABYSS_Z0 := -36.0
const ABYSS_FEATHER := 10.0
const ABYSS_DEPTH := 15.0
## Retângulo com cantos suavizados — `RGN-004` é `rect`, não `circle`; até
## 2026-08-31 este relevo usava um círculo que não correspondia à forma real
## da região. `GLACIAL_X0`/`GLACIAL_Z1` caem exatamente na borda do mapa
## (±60), então o esmaecimento ali é só estética de canto, não fronteira de
## bioma.
const GLACIAL_X0 := -60.0
const GLACIAL_X1 := -18.0
const GLACIAL_Z0 := 13.2
const GLACIAL_Z1 := 60.0
const GLACIAL_FEATHER := 10.0
## Era 1,5 até 2026-09-01, quando o platô glacial passou a ser terra firme
## declarada (`on_glacial`, ver abaixo) em vez de relevo só decorativo. Medido
## por sonda real (`probe_glacial_height.gd`, descartada): no NÚCLEO da região
## (fora da pena de esmaecimento das quatro bordas) a altura mínima é
## exatamente `GLACIAL_HEIGHT` — `hills` nunca subtrai, só soma — então a
## folga sobre `PZ01_WATER_LINE` (1,25) é `GLACIAL_HEIGHT - 1,25` garantida,
## não estatística. 1,5 dava só 0,25 m; 1,8 dá 0,55 m, mesma ordem de grandeza
## da folga da costa (`COAST_HEIGHT` 1,6 sobre a mesma cota).
const GLACIAL_HEIGHT := 1.8

## Margem entre a borda do terreno e o limite em que um corpo ainda pode ser
## posto. Além dos ±30 m da malha não há chão nenhum — nem visual, nem colisão,
## nem resposta de `height_at` que signifique alguma coisa —, e um corpo posto
## lá simplesmente cai. Dois metros cobrem o maior raio de cápsula do elenco
## (1,2 m) com folga.
const BOUNDS_MARGIN := 2.0

## Cota da superfície da água, injetada por quem veste o mapa
## (`MapDressing.water_line`). `-INF` = mapa seco, e aí nada está submerso —
## o padrão das bancadas de teste, que montam terreno sem bioma.
var water_line := -INF

## Profundidade abaixo da cota a partir da qual o leito conta como fundo
## demais para "seguir o relevo" continuar parecendo natural — ver
## `should_float`, que combina isto com inclinação.
##
## O valor cobre a variação máxima do relevo "sempre molhado" sem geografia
## especial — `hills` nunca passa de `HILL_HEIGHT` (2,5) acima de uma base 0,
## então o pior caso raso é ~1,25 m abaixo da cota (`PZ01_WATER_LINE`, 1,25).
## 3,0 m dá folga sem chegar perto do Mar Profundo, que passa dos 10 m.
const SHALLOW_DEPTH := 3.0

## Tangente do maior ângulo que ainda conta como piso — os mesmos 45° que o
## `CharacterBody3D` aceita por padrão (`floor_max_angle`), e que toda rampa
## deste mapa foi desenhada para respeitar (ver os comentários de
## `ISLAND_HEIGHT`/`COAST_RAMP_WIDTH`/`GLACIAL_FEATHER`). `tan(45°) = 1`.
const MAX_WALKABLE_SLOPE := 1.0
## Distância da amostra usada para medir inclinação em `should_float` — o
## espaçamento da própria grade do relevo (a malha e a colisão nascem em
## células de 1 m, ver o comentário de `SIZE`), então a inclinação medida é a
## MESMA que separa dois vértices vizinhos da malha, sem suavizar nem
## exagerar o degrau real.
const SLOPE_SAMPLE := 1.0

var _heights: PackedFloat32Array
var _dim: int


static func create(palette: Dictionary) -> MapTerrain:
	var t := MapTerrain.new()
	t._build(palette)
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


## O leito aqui está fundo demais pra "seguir o relevo" continuar parecendo
## andar em vez de mergulhar? Só profundidade — ver `should_float` para a
## pergunta completa (profundidade OU inclinação), que é a que os dois
## consumidores de fato fazem.
func is_deep(world_pos: Vector3) -> bool:
	if is_inf(water_line):
		return false
	return water_line - height_at(world_pos) > SHALLOW_DEPTH


## Este ponto é água funda ou íngreme demais para seguir o relevo — o corpo
## deveria estar flutuando na superfície, não andando/caindo no leito?
##
## ## Histórico: já foram DUAS versões erradas antes desta
##
## 1ª (`PlayerController` até 2026-09-01, geografia declarada
## `on_dry_land`): flutuava a caminho fixo até a BEIRA DA FORMA da
## costa/ilha/platô glacial e só então caía o resto da distância até o leito
## real, quase sempre bem mais raso ali. Lia como "parar de flutuar antes de
## subir".
##
## 2ª (`PlayerController`, só `is_deep`/`SHALLOW_DEPTH`): a rampa do Mar
## Profundo é tão íngreme (`ABYSS_FEATHER`/`ABYSS_DEPTH`) que fica
## intransitável ANTES de a profundidade cruzar `SHALLOW_DEPTH` — nesse
## intervalo o corpo caía de verdade em vez de flutuar. Lia como "desce um
## pouco e depois sobe", como se a superfície do Mar Profundo fosse mais alta
## que o resto.
##
## 3ª (`PlayerController`, só `not is_on_floor()`): parecia a resposta certa —
## o motor de física já calcula inclinação. Mas `is_on_floor()` reflete o
## QUADRO atual do motor, não só o terreno: um corpo momentaneamente no ar por
## qualquer motivo (cair de um teleporte, um `y` de partida acima do chão em
## teste) fica `not is_on_floor()` mesmo sobre leito raso e comum — e como
## `submerged()` já é incondicionalmente verdadeiro fora de `on_dry_land`
## (regra "recife não é ilhota"), isso bastava para flutuar em vez de cair
## até o chão raso ali do lado, que nunca chegava a ser tocado.
##
## Esta versão junta profundidade (`is_deep`) E inclinação — as duas
## calculadas do MESMO campo de altura que gera a malha e a colisão, então a
## resposta é sempre a mesma em qualquer quadro, parada ou em movimento, no ar
## ou não. Sem lacuna: em água aberta (fora de `on_dry_land`, onde
## `submerged()` já é sempre verdadeiro) só falta o leito realmente permitir
## andar — raso E de inclinação suave — para não flutuar.
func should_float(world_pos: Vector3) -> bool:
	if is_inf(water_line) or not submerged(world_pos):
		return false
	if is_deep(world_pos):
		return true
	var h := height_at(world_pos)
	var hx := height_at(world_pos + Vector3(SLOPE_SAMPLE, 0.0, 0.0))
	var hz := height_at(world_pos + Vector3(0.0, 0.0, SLOPE_SAMPLE))
	var slope := maxf(absf(hx - h), absf(hz - h)) / SLOPE_SAMPLE
	return slope > MAX_WALKABLE_SLOPE


## A altura em que um corpo SEM física (`CompanionActor`, que só consulta,
## nunca colide) deveria estar: o próprio relevo, ou a cota da água onde ele é
## fundo ou íngreme demais (`should_float`) para "andar no leito" continuar
## parecendo natural.
func surface_or_ground(world_pos: Vector3) -> float:
	if should_float(world_pos):
		return water_line
	return height_at(world_pos)


func _build(palette: Dictionary) -> void:
	_dim = SIZE + 1
	_heights = PackedFloat32Array()
	_heights.resize(_dim * _dim)

	var noise := FastNoiseLite.new()
	noise.seed = TERRAIN_SEED
	noise.frequency = 0.055

	var half := float(SIZE) * 0.5
	for z in _dim:
		for x in _dim:
			var wx := float(x) - half
			var wz := float(z) - half
			_heights[z * _dim + x] = _height_formula(wx, wz, noise)

	_add_mesh(palette)
	_add_collision()


## A fórmula do relevo. `r` em métrica de quadrado porque o mapa é quadrado:
## a distância ao centro tem de crescer igual em direção a lado e a canto,
## senão o rim afunda nos cantos.
func _height_formula(x: float, z: float, noise: FastNoiseLite) -> float:
	var r := maxf(absf(x), absf(z))
	var coast := _coast_profile(x, z)
	var amp := smoothstep(FLAT_RADIUS, float(SIZE) * 0.5 - 2.0, r)
	var hills := (noise.get_noise_2d(x, z) * 0.5 + 0.5) * HILL_HEIGHT * amp
	var h := hills * (1.0 - coast) + COAST_HEIGHT * coast
	h += smoothstep(float(SIZE) * 0.5 - 5.0, float(SIZE) * 0.5, r) * RIM_HEIGHT
	# A ilha soma em vez de misturar porque nasce dentro da planície (h = 0
	# ali) e não alcança nem a costa nem o rim — não há segundo relevo para
	# negociar no caminho.
	h += _island_profile(x, z) * ISLAND_HEIGHT
	# Relevo por bioma (ver docstring de REEF_CENTER acima): o recife ganha
	# volume, o abismo abre à direita só onde o catálogo diz Mar Profundo, e o
	# canto glacial sobe na região que o catálogo reserva pra ele.
	h += _reef_profile(x, z) * REEF_HEIGHT
	h -= _abyss_profile(x, z) * ABYSS_DEPTH
	h += _glacial_profile(x, z) * GLACIAL_HEIGHT
	return h


## Quanto da ilha existe neste ponto: 1 no topo plano, 0 fora da base.
func _island_profile(x: float, z: float) -> float:
	var d := Vector2(x - ISLAND_CENTER.x, z - ISLAND_CENTER.y).length()
	return 1.0 - smoothstep(ISLAND_TOP_RADIUS, ISLAND_BASE_RADIUS, d)


func _reef_profile(x: float, z: float) -> float:
	var d := Vector2(x - REEF_CENTER.x, z - REEF_CENTER.y).length()
	return 1.0 - smoothstep(REEF_RADIUS * 0.72, REEF_RADIUS, d)


## Rampa em x a partir de `ABYSS_X0`, com um portão em z: só vale a partir de
## `ABYSS_Z0` — fora disso é 0, mesmo com x grande. É o portão que impede o
## abismo de morder o platô seco da costa (ver docstring de `ABYSS_X0`).
func _abyss_profile(x: float, z: float) -> float:
	var fx := smoothstep(ABYSS_X0, ABYSS_X0 + ABYSS_FEATHER, x)
	var fz := smoothstep(ABYSS_Z0, ABYSS_Z0 + ABYSS_FEATHER, z)
	return fx * fz


## Retângulo com cantos suavizados: mínimo de duas rampas por eixo, cada uma
## subindo de um lado e descendo do outro — a mesma forma de um `rect` do
## catálogo, com esmaecimento (`GLACIAL_FEATHER`) nas quatro bordas em vez de
## corte reto.
func _glacial_profile(x: float, z: float) -> float:
	var fx := minf(
		smoothstep(GLACIAL_X0, GLACIAL_X0 + GLACIAL_FEATHER, x),
		1.0 - smoothstep(GLACIAL_X1 - GLACIAL_FEATHER, GLACIAL_X1, x))
	var fz := minf(
		smoothstep(GLACIAL_Z0, GLACIAL_Z0 + GLACIAL_FEATHER, z),
		1.0 - smoothstep(GLACIAL_Z1 - GLACIAL_FEATHER, GLACIAL_Z1, z))
	return fx * fz


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
## `PlayerController._floating` é o primeiro consumidor externo: fora daqui o
## corpo flutua na cota em vez de afundar até o leito.
func on_dry_land(world_pos: Vector3) -> bool:
	return on_coast(world_pos) or on_island(world_pos) or on_glacial(world_pos)


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
