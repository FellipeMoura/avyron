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
## A transição entre os dois níveis só é andável na COSTA, no PLATÔ GLACIAL
## (os dois são rampa na borda inteira) e nos `ACCESS_RAMPS` — hoje só a
## ILHA usa isso, e só ela continua com parede fora do ponto de acesso (a
## diferença de altura, mesmo pequena, ainda é íngreme demais num único metro
## de grade pro `CharacterBody3D` escalar — é isso que faz o degrau
## continuar funcionando como portão pra ela). Corpos com física (jogador,
## criaturas selvagens) seguem o
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
## `SIZE` saiu de 60 para 120 m em 2026-08-28, de 120 para 350 m em
## 2026-09-06 e **voltou para 175 m em 2026-09-16** (lado pela metade, ¼ da
## área). A regra dos 350 m era "30 s de travessia por bioma"; ela deu um mapa
## em que cruzar levava 67 s e a ida e volta à vila ~52 s — tempo de
## deslocamento vazio, que nem a fauna (que nasce ao redor do jogador) nem o
## cenário enchiam. A regra de hoje é **cruzar o mapa de lado a lado em ~35 s**
## a 5,2 m/s (175 m = 33,7 s), o que põe a ida e volta à vila abaixo de 30 s.
##
## O resize de 175 m foi o primeiro a ser, de fato, "uma linha": só `SIZE` e
## as contagens de scatter do `MapDressing` (que não seguem a área, ver lá)
## mudaram. Se o próximo pedir mais que isso, algo voltou a ser metro escrito
## à mão.
##
## **As formas em planta são frações de `_HALF`, não metros literais.** Até o
## resize de 350 elas eram números absolutos recalibrados à mão a cada
## mudança de tamanho — e eram, sem exceção, o valor normalizado do CATÁLOGO
## multiplicado pelo meio-lado da vez (`COAST_LOBE_R` 27,6 = 0,46 × 60;
## `GLACIAL_Z1` 60 = 1,0 × 60, a borda). Escrever a fração explícita fez duas
## coisas: o próximo resize passa a ser uma linha só, e o relevo deixa de
## poder divergir em silêncio da partição de bioma (que já é normalizada ±1 e
## já escalava sozinha) — que é exatamente o buraco descrito no comentário da
## costa, logo abaixo.
##
## O que NÃO escala, e por quê: a ILHA (é do tamanho de caber uma arena e um
## duelista — o mar em volta crescer não muda isso), as duas cotas
## (`SEA_HEIGHT`/`LAND_HEIGHT`, constantes fixas desde 2026-09-01), as larguras
## de rampa (`COAST_RAMP_WIDTH`/`GLACIAL_RAMP_WIDTH`, `ACCESS_RAMP_*` — conta
## de inclinação, não de área), `COAST_CORNER_RADIUS`/`GLACIAL_CORNER_RADIUS`
## (suavização visual) e `BOUNDS_MARGIN` (raio de cápsula). Trocar uma
## constante de grupo por engano é o que quebra o mapa.
##
## Lado do mapa em metros (grade de 1 m — célula igual à do HeightMapShape3D,
## que fixa o espaçamento em 1 unidade; a 175 m são 30.976 vértices).
const SIZE := 175
## Meio-lado, em metros. As formas em planta abaixo são FRAÇÕES deste número,
## nunca metros escritos à mão — ver "O tamanho do mapa" no cabeçalho.
const _HALF := float(SIZE) * 0.5
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
##
## ## Corte de ~72,5% (2026-09-17, pedido original era 90%)
##
## Pedido do usuário: encolher BIO-002 em 90% e empurrar os NPCs (vila da
## costa) para o que restar. Primeira tentativa (`COAST_RECT_HALF_W` a
## 0,114286 · `_HALF`, ~13 m) batia perto de 90% de corte, mas quebrou DOIS
## invariantes medidos por `test_biome_dressing.gd`, não só a folga de
## `CLEAR_RADIUS` da vila:
## - a largura livre de rampa (`half_w - COAST_RAMP_WIDTH`) é o teto de
##   quanto `coast_inland_at` consegue crescer para dentro do platô antes de
##   baralhar com a borda LATERAL em vez da borda da água — com 13 m de
##   largura isso saturava em 4 m, e nem o gradiente úmido/seco
##   (`PZ01_COAST_WET_WIDTH` = 7 m) cabia sem faixa dupla;
## - o mesmo teto precisa passar de `COAST_RAMP_WIDTH · 2` (12 m) pro ponto
##   mais fundo do platô não ler como "beira d'água" por engano.
## `COAST_RECT_HALF_W` subiu para 0,251429 · `_HALF` (22 m) — o mínimo medido
## que deixa os dois invariantes com folga (16 m de largura livre) sem
## reabrir a lacuna que o comentário de `COAST_RAMP_START` já registra. Corte
## final ~72,5% (de ~4.241 m² para ~1.166 m²) em vez dos ~90% pedidos —
## aprofundar mais exigiria encolher `COAST_RAMP_WIDTH` (constante de
## inclinação física, não de área) ou reescrever `coast_inland_at`, os dois
## fora do escopo de um corte de proporção. O círculo (`COAST_LOBE_R`)
## encolheu junto e ficou inteiramente contido no retângulo — ele não soma
## área nova a BIO-002. Até 2026-09-18 isso também importava pro shader (o
## raio zero desligava um gate que apagava a costa inteira, não só a
## barriga) — deixou de valer quando `terrain_ground.gdshader` passou a ler
## uma máscara bakeada (`coast_mask_tex`) em vez de recalcular a forma em
## GLSL, ver `_build_coast_mask_tex`. Nenhum ponto do `WorldPopulator`
## (`VILLAGE_ANCHOR` e derivados) precisou mudar: o retalho novo foi
## desenhado em volta deles, com margem,
## então já nascem dentro do que sobrou. O espaço liberado não tem geometria
## de nenhum outro bioma que o alcance perto da borda -Z — vira Mar Raso
## (`BIO-001`, catch-all) por padrão, sem precisar de região nova; o orçamento
## de scatter da costa (`PZ01_COAST_ROCK_COUNT`/`PZ01_COAST_PEBBLE_COUNT`) e o
## geral (`PZ01_SCATTER_COUNT`, o anel cresceu de território elegível) foram
## reproporcionados junto em `map_dressing.gd`.
##
## ## Cantos arredondados (2026-09-18)
##
## Pedido do usuário: "arredonde as formas... hoje são quadrados" — a costa e
## o platô glacial (abaixo). `_rounded_rect_sdf` substitui o par `band`/`side`
## (ou `fx`/`fz` no glacial): aquilo desenhava um retângulo com esmaecimento
## nas BORDAS, mas os CANTOS continuavam retos (só anti-aliased); o SDF
## arredonda o canto de verdade. Achado no caminho, por `test_biome_dressing`
## quebrar já na primeira amostra: um SDF de retângulo precisa de bordas
## simétricas nos dois lados de cada eixo, mas a costa (e o platô) só têm
## fronteira real de UM lado — o outro já era aberto pro mar/rim, sem limite
## nenhum (o `band`/`side` antigo nunca testava o lado de fora, só o de
## dentro). Espelhar isso ingenuamente pôs o lado "de fora" do SDF EXATAMENTE
## na borda visível do mapa (`-_HALF`), fechando um canto que nunca deveria
## existir e fazendo a costa "acabar" já no primeiro metro. `_OFFSCREEN_PAD`
## empurra esse lado bem além da malha (nunca visível, sempre atrás do rim)
## sem mexer no lado que de fato importa — o mesmo raciocínio vale pro platô
## glacial, que usava DOIS lados assim antes de 2026-09-18 (ocupava um canto
## do mapa); desde que encolheu ao tamanho da costa e virou banda de UMA
## borda só (`GLACIAL_RECT_CENTER_Z`/`_HALF_H`), tem exatamente o mesmo lado
## falso que a costa, só do lado oposto do mapa (`+_HALF`, não `-_HALF`).
const _OFFSCREEN_PAD := 50.0
const COAST_CENTER_X := 0.08 * _HALF
const COAST_LOBE_R := 0.068571 * _HALF
## Centro e meia-largura do retângulo, em metros — independentes do centro
## do círculo acima. Até 2026-08-31 os dois usavam a MESMA constante porque
## os dados do catálogo coincidiam por acaso (retângulo simétrico ao redor
## do mesmo x do círculo); a reautoria de `RGN-001` (só o lado +X) quebrou
## essa coincidência, e o retângulo passou a precisar do próprio centro. Hoje
## (corte de área) os dois centros voltam a coincidir por coincidência nova —
## o retalho é pequeno o bastante para não valer a pena descentralizar.
const COAST_RECT_CENTER_X := 0.08 * _HALF
const COAST_RECT_HALF_W := 0.251429 * _HALF
const COAST_RECT_Z := -0.697143 * _HALF
## Centro e meia-altura do retângulo no eixo Z, derivados de `COAST_RECT_Z`
## (a borda de dentro, a que importa) e de `-_HALF - _OFFSCREEN_PAD` (a borda
## de fora, empurrada bem além do mapa — ver "Cantos arredondados" acima).
const COAST_RECT_CENTER_Z := (-_HALF - _OFFSCREEN_PAD + COAST_RECT_Z) * 0.5
const COAST_RECT_HALF_H := (COAST_RECT_Z + _HALF + _OFFSCREEN_PAD) * 0.5
## Raio do canto arredondado (2026-09-18, pedido do usuário: "arredonde as
## formas... hoje são quadrados"). Só o canto voltado pro mar abre (o lado
## `-_HALF`, entre o retângulo e a parede do rim) nunca aparece — está fora
## da malha visível. Tem de ser menor que `COAST_RECT_HALF_H` (13,25 m) ou o
## SDF "encolhe" para um retângulo negativo e a forma inteira desaparece;
## 8 m deixa uma faixa reta de 5,25 m no meio de cada lado, suficiente pra não
## ler como diamante.
const COAST_CORNER_RADIUS := 8.0

## Largura do esmaecimento da forma da costa — ao contrário da ilha, a COSTA
## é rampa andável na borda INTEIRA com o mar, não só em pontos de acesso
## (pedido do usuário, 2026-09-01: é o adro da vila, precisa de acesso
## amplo). O platô glacial se juntou a essa regra em 2026-09-18 (mesmo
## pedido, "como na costa" — ver `GLACIAL_RAMP_WIDTH`/`_land_profile`, hoje a
## MESMA constante da costa); só a ilha continua com acesso em ponto fixo
## (`ACCESS_RAMPS`). Chegou a subir
## pra 12 m no mesmo dia, calibrada
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

## O alcance MÁXIMO da costa mar adentro, na linha de centro (`x =
## COAST_CENTER_X = COAST_RECT_CENTER_X`) — o ponto mais fundo entre lobo E
## retângulo, não só o lobo. Antes do corte de 90% (2026-09-17) o círculo
## sempre vencia esse máximo (raio de 40,25 m contra um retângulo mais raso) e
## `-_HALF + COAST_LOBE_R` sozinho bastava; encolher o círculo pra caber
## dentro do retângulo inverteu quem alcança mais longe nessa linha — hoje é o
## retângulo (`COAST_RECT_Z`, -61 m) que chega mais fundo que o círculo
## (-81,5 m). `test_data.gd` mede essa fronteira contra `biome_at` na mesma
## linha de centro; usar só o lobo aqui descolaria os dois em ~20 m e o teste
## acusaria (silenciosamente, se ninguém tivesse mexido nele) o mesmo buraco
## que este comentário já preveniu uma vez.
const COAST_RAMP_START := maxf(-_HALF + COAST_LOBE_R, COAST_RECT_Z)
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

## O platô glacial (`RGN-004` + `RGN-008`, BIO-014) — encolhido ao mesmo
## tamanho da costa e movido do CANTO -X/+Z para a borda +Z (2026-09-18,
## pedido do usuário: "reduza para o mesmo tamanho da costa... replique a
## costa... identicos"). Até aqui o platô ocupava um canto — dois lados reais
## contra o mar (`GLACIAL_X1`/`GLACIAL_Z0`, removidos) e dois lados falsos
## sobre a própria borda do mapa (`GLACIAL_X0`/`GLACIAL_Z1`, removidos), a
## MESMA topologia da ilha (fechada nos dois eixos). "Idênticos" pede a
## topologia da COSTA — uma banda perto de UMA borda só, com um único lado
## falso —, não só números parecidos, então os valores abaixo são
## literalmente `COAST_CENTER_X`/`COAST_RECT_*` com o sinal invertido (a
## costa fica em -Z, o platô em +Z) — e o raio do canto, a largura de rampa e
## as amplitudes de ruído passaram a ser as MESMAS constantes da costa (ver
## `_edge_band_profile`), não cópias com o mesmo valor: duas formas não
## divergem silenciosamente se são o mesmo número.
const GLACIAL_CENTER_X := -COAST_CENTER_X
const GLACIAL_LOBE_R := COAST_LOBE_R
const GLACIAL_RECT_CENTER_X := -COAST_RECT_CENTER_X
const GLACIAL_RECT_HALF_W := COAST_RECT_HALF_W
const GLACIAL_RECT_Z := -COAST_RECT_Z
## Centro e meia-altura do retângulo no eixo Z — espelho de
## `COAST_RECT_CENTER_Z`/`COAST_RECT_HALF_H`: o lado falso agora é `+_HALF +
## _OFFSCREEN_PAD` (a costa usa `-_HALF - _OFFSCREEN_PAD`), porque o platô
## trocou de borda.
const GLACIAL_RECT_CENTER_Z := (_HALF + _OFFSCREEN_PAD + GLACIAL_RECT_Z) * 0.5
const GLACIAL_RECT_HALF_H := (_HALF + _OFFSCREEN_PAD - GLACIAL_RECT_Z) * 0.5
const GLACIAL_CORNER_RADIUS := COAST_CORNER_RADIUS
const GLACIAL_RAMP_WIDTH := COAST_RAMP_WIDTH

## Margem entre a borda do terreno e o limite em que um corpo ainda pode ser
## posto. Além dos ±`_HALF` da malha não há chão nenhum — nem visual, nem
## colisão, nem resposta de `height_at` que signifique alguma coisa —, e um
## corpo posto lá simplesmente cai. Dois metros cobrem o maior raio de cápsula
## do elenco (1,2 m) com folga, e por isso não escalam com o mapa.
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
## níveis vira rampa andável de verdade. Só a ILHA usa isto hoje: fora de um
## raio `ACCESS_RAMP_OUTER` deste ponto, a borda dela é parede. COSTA e
## PLATÔ GLACIAL são rampa na borda INTEIRA (`COAST_RAMP_WIDTH`/
## `GLACIAL_RAMP_WIDTH`, usados direto em `_land_profile`, sem endurecer) — a
## ilha continua sendo a única exceção "controlada" (pedido original,
## 2026-09-01: leitura de platô fechado, não coast/adro).
##
## Coordenada medida por sonda direta contra `_land_profile` (descartada),
## não calculada à mão — voltada pra costa, de onde o jogador nada de
## verdade pra chegar lá.
##
## **Até 2026-09-18 este array também tinha 2 pontos no platô glacial** — a
## exceção "controlada" valia pros dois, com o glacial hardenado a degrau
## reto fora deles (mesmo tratamento da ilha). Pedido do usuário, mesmo dia:
## "as bordas virarem rampas, como na costa" — o platô deixou de ser
## hardenado (ver `_land_profile`), e os dois pontos saíram por não terem
## mais função (a borda inteira já é andável, não só ali). Um dos dois
## (-80, 23) tinha sido reautorado horas antes especificamente pra escapar
## do círculo do recife que isolava a rampa antiga numa ilhota — essa lição
## (posição em território de outro bioma) fica registrada aqui porque
## qualquer ponto FUTURO nesta borda (se a ilha um dia precisar de um
## análogo) tem de repetir a mesma checagem contra `biome_at`.
const ACCESS_RAMPS: Array[Vector2] = [
	Vector2(0.0, -ISLAND_BASE_RADIUS),
]
## Vão da rampa da ilha: raio "totalmente terra" (`INNER`) e raio "de volta
## ao mar aberto" (`OUTER`) — NÃO é o esmaecimento da forma dela
## (`ISLAND_TOP_RADIUS`/`ISLAND_BASE_RADIUS`, que não entra na altura fora
## deste ponto — a ilha é hardenada, ver `_land_profile`). O vão certo pra
## ≤45° é `1,5 · diferença / vão`; com a diferença de hoje entre os dois
## níveis (2,0 m — ver `SEA_HEIGHT`), precisa de só 3 m. 6 m de vão
## (`OUTER - INNER`) dá folga de sobra e ainda lê como rampa de verdade, não
## uma diferença imperceptível.
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


## 1 em terra firme, 0 em mar aberto. Dois tratamentos diferentes, um por
## geografia:
##
## - COSTA e PLATÔ GLACIAL: os dois já SÃO rampa suave na borda inteira
##   (`COAST_RAMP_WIDTH`/`GLACIAL_RAMP_WIDTH`, calibrados pra ≤45° na diferença
##   cheia de hoje) — usados direto, sem degrau. O glacial se juntou à costa
##   nisso em 2026-09-18 (pedido do usuário: "as bordas virarem rampas, como
##   na costa"); antes disso era hardenado como a ilha, com dois
##   `ACCESS_RAMPS` fazendo o papel de único acesso andável.
## - ILHA: degrau reto (`island_hard`) — leitura "controlada" pedida no lugar
##   de relevo contínuo (2026-09-01, ainda vale só pra ela) — EXCETO onde o
##   `ACCESS_RAMPS` (hoje um ponto só) levanta rampa própria, com vão
##   calibrado à parte (`ACCESS_RAMP_INNER`/`OUTER`), porque o esmaecimento
##   natural da forma dela (`ISLAND_TOP_RADIUS`/`BASE_RADIUS`) é estreito
##   demais pra diferença de altura de hoje.
##
## O resultado é o máximo dos três: a rampa (de qualquer origem) levanta o
## mar até virar terra onde ela alcança, e o resto do mapa continua parede.
func _land_profile(x: float, z: float) -> float:
	var coast := _coast_profile(x, z)
	var glacial := _glacial_profile(x, z)
	var island_hard := 1.0 if _island_profile(x, z) > 0.0 else 0.0
	return maxf(coast, maxf(glacial, maxf(island_hard, _access_ramp_profile(x, z))))


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
## formas. Fica como o AMPLITUDE PADRÃO de `_warp` — só a ilha usa este valor
## hoje; costa e platô glacial pedem mais (ver as constantes próprias abaixo),
## e escalar os três em bloco reabriria o problema que motivou 2,0 m em
## primeiro lugar.
const EDGE_NOISE_AMPLITUDE := 2.0
## Segunda oitava, mais FINA, de irregularidade de borda (2026-09-18, pedido
## do usuário: costa e platô liam "quadrados" mesmo com o warp de uma oitava
## só — uma única frequência baixa produz uma ondulação suave e previsível,
## não uma borda irregular de verdade). Amostra o MESMO `_edge_noise` numa
## escala maior (equivalente a uma frequência ~7× mais alta) em vez de um
## segundo `FastNoiseLite` — mais barato, e não precisa de semente própria
## porque o deslocamento de domínio já evita repetir o padrão da oitava larga.
const EDGE_NOISE_FINE_SCALE := 7.0

## Amplitude de `_warp` pra COSTA — mais que o dobro do padrão da ilha:
## `COAST_RECT_HALF_W` (22 m) tem margem pra uma borda visivelmente mais
## quebrada sem arriscar o retalho inteiro (ao contrário da ilha, de 9 m de
## raio). Some com `COAST_EDGE_NOISE_FINE_AMPLITUDE` pro deslocamento máximo
## que `test_biome_dressing.gd` precisa descontar da largura livre de rampa.
const COAST_EDGE_NOISE_AMPLITUDE := 4.0
const COAST_EDGE_NOISE_FINE_AMPLITUDE := 1.5
## O platô glacial usa as MESMAS duas constantes acima, não um par próprio
## (removido em 2026-09-18, quando o platô encolheu ao tamanho da costa e
## passou a ter o mesmo meio-lado dela — ver `_edge_band_profile`). Tinha um
## par maior (11/5) enquanto o retângulo era bem maior que o da costa; hoje
## os dois retalhos têm a mesma margem disponível, e reaproveitar a mesma
## constante é o que impede a costa e o platô de divergirem de novo sem
## ninguém decidir isso de propósito.

var _edge_noise: FastNoiseLite


## `amplitude` desloca com uma oitava larga (a mesma de sempre); `fine_amplitude`
## > 0 soma uma segunda oitava mais fina (ver `EDGE_NOISE_FINE_SCALE`) — 0.0
## (padrão) desliga essa segunda oitava sem custo, mesmo comportamento de
## antes de 2026-09-18 pra quem não passar o parâmetro (a ilha).
func _warp(x: float, z: float, amplitude: float = EDGE_NOISE_AMPLITUDE, fine_amplitude: float = 0.0) -> Vector2:
	if _edge_noise == null:
		_edge_noise = FastNoiseLite.new()
		_edge_noise.seed = EDGE_NOISE_SEED
		_edge_noise.frequency = EDGE_NOISE_FREQUENCY
	# Duas amostras do mesmo ruído, deslocadas no domínio (não em frequência
	# nem semente), pra x e z desalinharem em direções diferentes — um único
	# valor aplicado aos dois eixos só esticaria a forma na diagonal, sem
	# quebrar a regularidade da borda.
	var wx := _edge_noise.get_noise_2d(x, z) * amplitude
	var wz := _edge_noise.get_noise_2d(x + 731.0, z - 731.0) * amplitude
	if fine_amplitude > 0.0:
		# Mesmo truque de deslocamento de domínio, com offsets DIFERENTES dos
		# de cima (91/917, não 731) — senão a oitava fina repetiria a mesma
		# quebra da larga no mesmo lugar, e a soma só escalaria a amplitude
		# sem acrescentar irregularidade nova.
		wx += _edge_noise.get_noise_2d(x * EDGE_NOISE_FINE_SCALE + 91.0, z * EDGE_NOISE_FINE_SCALE) \
			* fine_amplitude
		wz += _edge_noise.get_noise_2d(x * EDGE_NOISE_FINE_SCALE + 917.0, z * EDGE_NOISE_FINE_SCALE - 917.0) \
			* fine_amplitude
	return Vector2(x + wx, z + wz)


## SDF de retângulo com cantos arredondados (2D, técnica padrão de Inigo
## Quilez): negativo dentro da forma, positivo fora, zero exatamente na borda
## arredondada. Substitui o par `band`/`side` (ou `fx`/`fz`) que cada eixo
## desenhava sozinho — aquilo dava um retângulo com esmaecimento nas bordas,
## mas os CANTOS continuavam retos (só ficavam anti-aliased, nunca
## arredondados de verdade, porque multiplicar duas faixas 1D não é a mesma
## conta que arredondar o canto onde elas se cruzam).
##
## `corner_r` tem de ser ≤ `min(half_w, half_h)` — acima disso o "retângulo
## encolhido" que a fórmula arredonda vira negativo e a forma inverte.
func _rounded_rect_sdf(
	x: float, z: float, cx: float, cz: float, half_w: float, half_h: float, corner_r: float
) -> float:
	var dx := absf(x - cx) - (half_w - corner_r)
	var dz := absf(z - cz) - (half_h - corner_r)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length() + minf(maxf(dx, dz), 0.0) - corner_r


## Quanto da ilha existe neste ponto: 1 dentro do raio da base, 0 fora. Antes
## do corte de relevo contínuo, media um platô com rampa própria (topo até
## `ISLAND_TOP_RADIUS`, descendo até `ISLAND_BASE_RADIUS`); agora é só a
## forma que alimenta `_land_profile`/`on_island` — a altura real vem de lá,
## mas o esmaecimento continua usando o mesmo vão de sempre.
func _island_profile(x: float, z: float) -> float:
	var w := _warp(x, z)
	var d := Vector2(w.x - ISLAND_CENTER.x, w.y - ISLAND_CENTER.y).length()
	return 1.0 - smoothstep(ISLAND_TOP_RADIUS, ISLAND_BASE_RADIUS, d)


## Núcleo geométrico comum à costa e ao platô glacial: retângulo com cantos
## arredondados (`_rounded_rect_sdf`) UNIDO a um lobo (círculo pendurado numa
## borda do mapa), os dois com o mesmo warp de duas oitavas por cima —
## extraído em 2026-09-18 (pedido do usuário: os dois biomas têm de ficar
## IDÊNTICOS, exceto assets/NPCs/texturas) pra impedir as duas formas de
## divergirem em silêncio — antes cada bioma tinha sua própria cópia da
## fórmula, e foi assim que o platô glacial acumulou constantes de warp e
## raio de canto próprios (11/5, 15 m) sem que ninguém tivesse decidido isso
## de propósito. `lobe_center_z`/`rect_center_z` já incluem o sinal — quem
## chama passa `+half` ou `-half` conforme a borda do mapa que o bioma
## encosta, e todo o resto (rampa, warp, arredondamento) é idêntico por
## construção.
func _edge_band_profile(
	x: float, z: float,
	center_x: float, lobe_center_z: float, lobe_r: float,
	rect_center_x: float, rect_center_z: float, rect_half_w: float, rect_half_h: float,
	corner_r: float, ramp_width: float, noise_amp: float, noise_fine: float
) -> float:
	var warped := _warp(x, z, noise_amp, noise_fine)
	var d := Vector2(warped.x - center_x, warped.y - lobe_center_z).length()
	var lobe := 1.0 - smoothstep(lobe_r - ramp_width, lobe_r, d)
	var sdf := _rounded_rect_sdf(
		warped.x, warped.y, rect_center_x, rect_center_z, rect_half_w, rect_half_h, corner_r)
	var rect := 1.0 - smoothstep(0.0, ramp_width, sdf)
	return maxf(lobe, rect)


## Quanto da costa existe neste ponto: 1 no platô seco, 0 em mar aberto.
##
## `margin` infla o lobo e o retângulo ao mesmo tempo (não o raio do canto,
## que fica fixo) — é o que deixa o keep-out do spawner cobrir a deriva de
## patrulha sem precisar de uma segunda forma.
func _coast_profile(x: float, z: float, margin: float = 0.0) -> float:
	var half := float(SIZE) * 0.5
	return _edge_band_profile(
		x, z, COAST_CENTER_X, -half, COAST_LOBE_R + margin,
		COAST_RECT_CENTER_X, COAST_RECT_CENTER_Z, COAST_RECT_HALF_W + margin, COAST_RECT_HALF_H + margin,
		COAST_CORNER_RADIUS, COAST_RAMP_WIDTH, COAST_EDGE_NOISE_AMPLITUDE, COAST_EDGE_NOISE_FINE_AMPLITUDE)


## Quanto do platô glacial existe neste ponto — mesma fórmula da costa
## (`_edge_band_profile`), espelhada pra borda +Z em vez de -Z (2026-09-18).
##
## O retângulo (`RGN-004`) bate com o catálogo em metros, mas o círculo do
## recife (`RGN-002`, sortOrder mais alto) ainda podia se sobrepor a um canto
## dele — nessa cunha, o PRÓPRIO JOGO responde recife quando consultado
## (`biome_at`), não glacial (pedido do usuário, 2026-09-02: essa cunha vira
## água de verdade, relevo e cor). `_map_biomes` (quando presente) só zera o
## platô onde o recife REALMENTE reivindica o ponto — checar "não é BIO-014"
## em vez de "é BIO-003" (versão anterior a 2026-09-18) também apagava a
## rampa/lobo/warp inteiros fora do retângulo reto do catálogo, que é
## justamente onde essa forma tem de existir; confirmado por sonda
## (`probe_glacial_ramp.gd`, descartada) — a versão errada derrubava 2 m de
## altura em 2 m de distância bem na borda reta do catálogo, parede em vez
## de rampa.
func _glacial_profile(x: float, z: float, margin: float = 0.0) -> float:
	var half := float(SIZE) * 0.5
	var profile := _edge_band_profile(
		x, z, GLACIAL_CENTER_X, half, GLACIAL_LOBE_R + margin,
		GLACIAL_RECT_CENTER_X, GLACIAL_RECT_CENTER_Z, GLACIAL_RECT_HALF_W + margin, GLACIAL_RECT_HALF_H + margin,
		GLACIAL_CORNER_RADIUS, GLACIAL_RAMP_WIDTH, COAST_EDGE_NOISE_AMPLITUDE, COAST_EDGE_NOISE_FINE_AMPLITUDE)
	if profile > 0.0 and _map_biomes and _map_biomes.biome_at(Vector3(x, 0.0, z)) == "BIO-003":
		return 0.0
	return profile


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
## minério próprio (ver `CLAUDE.md`, minério glacial exclusivo) lendo como
## fundo de mar contradizia o resto do design.
##
## **O platô NÃO tem fauna** (corrigido em 2026-09-07). Este comentário dizia o
## contrário — "é bioma de fauna, não adro de NPC" — e contradizia a nota do
## próprio BIO-014 no catálogo, que declara em letras maiúsculas "SEM FAUNA:
## nenhuma criatura nasce nem patrulha aqui" e chama o BIO-004 (Mar Profundo)
## de par de vazio. A contradição só apareceu quando `biomes.spawnChance`
## passou a existir e alguém teve de escrever um número: o catálogo venceu, os
## dois estão em 0,00, e é o CATÁLOGO que manda nessa pergunta.
##
## Sem `margin` mesmo assim: o keep-out de spawn não é mais geografia escrita
## aqui — `CreatureSpawner` rejeita qualquer ponto cujo BIOMA tenha chance
## zero, o que cobre o platô, o mar profundo e qualquer bioma sem fauna que
## venha depois, sem um predicado novo por bioma. É a saída que o `CLAUDE.md`
## já apontava como a boa entre as duas possíveis.
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
## `_glacial_profile`) que `_land_profile` usa pra levantar a rampa do
## platô glacial — reaproveitada por `terrain_ground.gdshader` pra alinhar a
## textura de gelo pixel a pixel com a geografia real. Um retângulo
## recalculado no shader, sem o warp/filtro da malha, foi a causa de defeitos
## que pareciam coisas diferentes (marrom por cima de gelo andável, borda
## quadrada demais, textura em chão que o painel rotula doutro bioma): todos
## eram o mesmo descompasso entre a borda que a COR desenhava e a borda que
## `_glacial_profile` já desenhava. Mesma técnica do `heightmap_tex` da água
## — bake da grade em textura em vez de reformular a fórmula no shader.
func _build_glacial_mask_tex() -> ImageTexture:
	return bake_mask(func(wx: float, wz: float) -> float:
		return 1.0 if _glacial_profile(wx, wz) > 0.0 else 0.0)


## Bakeia `profile(x, z)` na MESMA grade da malha (1 célula = 1 m, mesma UV
## `(mundo + meio-lado) / lado` que todo mask do shader usa), como textura de
## um canal float. Público desde 2026-09-20: o `MapDressing` bakeia por aqui a
## máscara da praça da vila — vestimenta, não relevo, mas a técnica é a mesma
## dos masks de geografia, e ter um caminho só garante que qualquer máscara
## nova chega ao shader na mesma UV.
func bake_mask(profile: Callable) -> ImageTexture:
	var half := float(SIZE) * 0.5
	var mask := PackedFloat32Array()
	mask.resize(_dim * _dim)
	for z in _dim:
		for x in _dim:
			mask[z * _dim + x] = float(profile.call(float(x) - half, float(z) - half))
	var img := Image.create_from_data(_dim, _dim, false, Image.FORMAT_RF, mask.to_byte_array())
	return ImageTexture.create_from_image(img)


## Escreve um uniform no material do chão depois de a malha existir. É a
## porta por onde a vestimenta (`MapDressing`, que roda DEPOIS de `create`)
## entrega o que é dela — hoje, a máscara da praça da vila — sem que o terreno
## precise conhecer a vila.
func set_ground_uniform(uniform_name: StringName, value: Variant) -> void:
	var mi := get_node_or_null("Mesh") as MeshInstance3D
	if mi == null or mi.mesh == null:
		push_warning("MapTerrain: sem malha para receber o uniform %s" % uniform_name)
		return
	var material := mi.mesh.surface_get_material(0) as ShaderMaterial
	if material:
		material.set_shader_parameter(uniform_name, value)


## Os dois blocos geométricos do relevo, expostos para o `MapDressing`
## desenhar a praça da vila com a MESMA irregularidade de borda (ver
## `MapDressing.plaza_profile`): um retângulo liso ao lado de uma costa com
## warp leria como adesivo.
func edge_warp(x: float, z: float, amplitude: float = EDGE_NOISE_AMPLITUDE) -> Vector2:
	return _warp(x, z, amplitude)


func rounded_rect_sdf(
	x: float, z: float, cx: float, cz: float, half_w: float, half_h: float, corner_r: float
) -> float:
	return _rounded_rect_sdf(x, z, cx, cz, half_w, half_h, corner_r)


## MESMA técnica de `_build_glacial_mask_tex`, pra costa — desde 2026-09-18,
## quando o retângulo dela ganhou canto arredondado (`_rounded_rect_sdf`) e
## uma segunda oitava de warp (`COAST_EDGE_NOISE_FINE_AMPLITUDE`). Antes disso
## o shader recalculava lobo+retângulo em GLSL a partir de 6 uniforms
## (`coast_center_x`, `coast_lobe_r`, `coast_rect_*`) — reproduzir o SDF
## arredondado E as duas oitavas de ruído em GLSL duplicaria a MESMA
## geometria em dois lugares, exatamente a classe de erro que o comentário de
## `glacial_mask_tex` já registra. Ler a máscara pronta garante concordância
## pixel a pixel sem duplicar nada, e apaga de vez o gate `coast_lobe_r > 0.0`
## que o shader antigo precisava (a armadilha documentada no changelog do
## corte de 90% — zerar o raio da barriga apagava a costa inteira, não só
## ela).
func _build_coast_mask_tex() -> ImageTexture:
	return bake_mask(func(wx: float, wz: float) -> float:
		return 1.0 if _coast_profile(wx, wz) > 0.0 else 0.0)


## Até onde a distância da costa é medida (m). Além disto o valor satura: o
## shader só precisa distinguir "perto da água" de "longe", e o platô inteiro
## cabe com folga (lobo de ~40 m de raio).
## Até onde a distância de borda é medida (m). Além disto o valor satura: o
## shader só precisa distinguir "perto da borda" de "no miolo", e os dois
## platôs cabem com folga.
const INLAND_MAX := 48.0

var _coast_inland: PackedFloat32Array
var _glacial_inland: PackedFloat32Array


## Distância, em metros, de cada ponto de um platô até a borda de CIMA da
## rampa dele — 0 na rampa e na água, crescendo para dentro da terra.
##
## Existe porque os platôs são planos: o relevo tem só dois níveis, então a
## altura não diz se um ponto está junto da água ou no fundo do platô. O
## shader usa a medida para trocar de camada de textura conforme se entra —
## lama úmida → terra seca na costa, rocha exposta → neve no glacial.
##
## Bakeada do MESMO perfil que levanta a malha, warp incluso — pela lição do
## `glacial_mask_tex`: uma borda recalculada no shader por fórmula própria
## desenharia a faixa fora do lugar de verdade.
##
## Chamfer de duas passadas (1 nos eixos, √2 na diagonal): erro máximo de ~8%
## sobre a distância euclidiana, invisível numa transição que o shader ainda
## desalinha com ruído. Vizinho fora da grade não conta como borda — sem isso,
## a borda do MAPA atrás da vila viraria "beira d'água".
func _bake_inland(profile: Callable) -> PackedFloat32Array:
	var half := float(SIZE) * 0.5
	var dist := PackedFloat32Array()
	dist.resize(_dim * _dim)
	for z in _dim:
		for x in _dim:
			var plateau: float = profile.call(float(x) - half, float(z) - half)
			dist[z * _dim + x] = INLAND_MAX if plateau >= 1.0 else 0.0

	var diag := sqrt(2.0)
	for z in _dim:
		for x in _dim:
			var i := z * _dim + x
			var d := dist[i]
			if d == 0.0:
				continue
			if x > 0:
				d = minf(d, dist[i - 1] + 1.0)
			if z > 0:
				d = minf(d, dist[i - _dim] + 1.0)
				if x > 0:
					d = minf(d, dist[i - _dim - 1] + diag)
				if x < _dim - 1:
					d = minf(d, dist[i - _dim + 1] + diag)
			dist[i] = d
	for z in range(_dim - 1, -1, -1):
		for x in range(_dim - 1, -1, -1):
			var i := z * _dim + x
			var d := dist[i]
			if d == 0.0:
				continue
			if x < _dim - 1:
				d = minf(d, dist[i + 1] + 1.0)
			if z < _dim - 1:
				d = minf(d, dist[i + _dim] + 1.0)
				if x < _dim - 1:
					d = minf(d, dist[i + _dim + 1] + diag)
				if x > 0:
					d = minf(d, dist[i + _dim - 1] + diag)
			dist[i] = d
	return dist


static func _inland_tex(values: PackedFloat32Array, dim: int) -> ImageTexture:
	var img := Image.create_from_data(dim, dim, false, Image.FORMAT_RF, values.to_byte_array())
	return ImageTexture.create_from_image(img)


## A mesma medida que o shader lê, no ponto da grade mais próximo. Para teste e
## para quem precisar decidir "beira ou miolo" por código — é o que faz o
## `MapDressing` plantar matacão na linha da água da costa.
func coast_inland_at(world_pos: Vector3) -> float:
	return _inland_at(_coast_inland, world_pos)


func glacial_inland_at(world_pos: Vector3) -> float:
	return _inland_at(_glacial_inland, world_pos)


func _inland_at(values: PackedFloat32Array, world_pos: Vector3) -> float:
	if values.is_empty():
		return 0.0
	var half := float(SIZE) * 0.5
	var x := clampi(roundi(world_pos.x + half), 0, _dim - 1)
	var z := clampi(roundi(world_pos.z + half), 0, _dim - 1)
	return values[z * _dim + x]


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
	# e passou a ser a MESMA forma composta que levanta a malha — desde
	# 2026-09-18, via máscara bakeada (`coast_mask_tex`, mesma técnica de
	# `glacial_mask_tex`), não mais 6 uniforms recalculados em GLSL. Ver
	# comentário de `_build_coast_mask_tex`.
	material.set_shader_parameter("coast_mask_tex", _build_coast_mask_tex())
	material.set_shader_parameter("map_half", float(SIZE) * 0.5)
	material.set_shader_parameter("island_center", ISLAND_CENTER)
	material.set_shader_parameter("island_top_radius", ISLAND_TOP_RADIUS)
	material.set_shader_parameter("island_base_radius", ISLAND_BASE_RADIUS)
	# Textura de chão do platô glacial (BIO-014) e da costa (BIO-002) — mesma
	# geografia que já levanta o relevo (`GLACIAL_*`/`COAST_*`), só espelhada
	# pro shader como fez a costa antes: geografia é deste arquivo, cor é do
	# `.gdshader`.
	# O platô glacial em duas camadas (Snow Ground 4 na borda, Snow 8 no
	# miolo), mesma receita da costa — ver o trecho glacial do
	# `terrain_ground.gdshader`. Substituiu a textura de gelo única em
	# 2026-09-18.
	material.set_shader_parameter("snow_tex", load("res://textures/terrain/snow_diffuse.png"))
	material.set_shader_parameter("snow_height_tex", load("res://textures/terrain/snow_height.png"))
	material.set_shader_parameter("snow_rock_tex", load("res://textures/terrain/snow_rock_diffuse.png"))
	material.set_shader_parameter("snow_rock_height_tex", load("res://textures/terrain/snow_rock_height.png"))
	material.set_shader_parameter("glacial_mask_tex", _build_glacial_mask_tex())
	_glacial_inland = _bake_inland(_glacial_profile)
	material.set_shader_parameter("glacial_inland_tex", _inland_tex(_glacial_inland, _dim))
	# A costa em duas camadas do mesmo tema (Mud 4 na beira, Mud 10 no platô),
	# cada uma com o mapa de altura que o shader usa para misturar — ver o
	# trecho da costa em `terrain_ground.gdshader`. A largura da faixa úmida
	# NÃO vem daqui: é `MapDressing.PZ01_COAST_WET_WIDTH`, que chega pela
	# paleta, porque quem planta pedra naquela linha é o `MapDressing` e os
	# dois têm de concordar.
	material.set_shader_parameter("mud_tex", load("res://textures/terrain/mud_diffuse.png"))
	material.set_shader_parameter("mud_height_tex", load("res://textures/terrain/mud_height.png"))
	material.set_shader_parameter("mud_dry_tex", load("res://textures/terrain/mud_dry_diffuse.png"))
	material.set_shader_parameter("mud_dry_height_tex", load("res://textures/terrain/mud_dry_height.png"))
	# A terceira camada da costa, as lajes da praça da vila (Stone Wall 1 do
	# mesmo pack): a textura entra aqui com as outras duas; a MÁSCARA de onde
	# ela aparece é vestimenta e chega depois, pelo `MapDressing`
	# (`set_ground_uniform("village_mask_tex", …)`).
	material.set_shader_parameter("paved_tex", load("res://textures/terrain/paved_diffuse.png"))
	material.set_shader_parameter("paved_height_tex", load("res://textures/terrain/paved_height.png"))
	_coast_inland = _bake_inland(_coast_profile)
	material.set_shader_parameter("coast_inland_tex", _inland_tex(_coast_inland, _dim))
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


## Direção da corrente do mapa, em XZ de mundo. Escrita no material da água
## (arrasto de UV da superfície) e lida pelo `MapDressing` para o balanço dos
## props do leito — as duas têm de concordar, ou a imagem mostra duas águas.
##
## Constante em GDScript, não default do shader: até 2026-09-17 ela só existia
## como default de `water_flow_dir` no `.gdshader`, e ler default de shader
## pelo `RenderingServer` devolve `null` sem renderizador real (headless) —
## medido pela `test_biome_dressing`. Uma fonte que some conforme o modo de
## execução não é fonte.
const WATER_FLOW_DIR := Vector2(0.6, 1.0)


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
	material.set_shader_parameter("water_flow_dir", WATER_FLOW_DIR)

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
