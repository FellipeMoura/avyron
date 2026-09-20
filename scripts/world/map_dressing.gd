class_name MapDressing
extends RefCounted

## Veste o mapa: ambiente (névoa, luz, chão) e props de cenário por mapa.
##
## Mesmo padrão de `WorldPopulator` — `RefCounted` com funções `static`,
## chamado uma vez por `WorldRoot._ready()`, sem estado depois de vestir.
## Tudo aqui é apresentação pura: nenhum prop emite sinal, dá drop ou entra
## em fórmula. As constantes de cor/névoa são "constantes de apresentação"
## na exceção da regra 1 do CLAUDE.md, não tuning de gameplay.
##
## Layout é posição de cena, não de bestiário — mesmo raciocínio de
## `MERCHANT_SPOT`: o catálogo diz que o PZ-01 é o Mundo dos Mares; ONDE cada
## recife fica é decisão do mundo. Os landmarks são fixos à mão; a vegetação
## miúda é espalhada com semente FIXA, para o cenário sair igual em toda
## execução — é o que deixa duas capturas de tela do mesmo bioma comparáveis.
##
## O `CreatureSpawner` já teve uma semente fixa pelo mesmo motivo e a perdeu em
## 2026-09-06: o povoamento virou função do caminho que o jogador andou, e não
## existe mais "a mesma abertura" para comparar. A do cenário continua válida
## justamente porque cenário não depende de para onde ninguém andou.

const AQUA_KIT := "res://models/biomes/aquatic/"
## Kit próprio do mar raso, separado do `AQUA_KIT` em 2026-09-18: os dois
## biomas usavam o mesmo acervo de coral e por isso liam como um só (ver
## `BIOME_PROPS.md` §4, "usa o mesmo kit e por isso os dois se confundem").
## `AQUA_KIT` continua sendo o kit do recife (Jardins Recifais, BIO-003).
const MAR_RASO_KIT := "res://models/biomes/mar-raso/"

## Chave única pra colisão de prop de bioma (2026-09-01, temporário). Desligada
## enquanto a densidade/porte do preenchimento ainda está sendo ajustado a
## olho. Os valores de `col_radius` continuam nos dados (`PZ01_LANDMARKS`);
## ligar de volta é só virar isto pra `true`, sem reautorar nada.
const PZ01_PROPS_COLLIDABLE := false

## Placeholder aliases de apoio: o mapa deve poder trocar por GLBs finais sem
## recriar o layout. Cada nome explícito e canônico fica aqui e é resolvido para
## um asset de teste (coral/rocha/aquático) até que o modelo definitivo chegue.
##
## `PZ01_PLACEHOLDER_REEF_HERO_01` existiu até 2026-09-01 e apontava pra
## `scenes/props/pz01_reef_hero_01.tscn` — um `.tscn` de recurso embutido que
## nunca chegou a carregar nesta versão do Godot (`Color(r,g,b)` de 3
## argumentos em `sub_resource`, que o parser 4.7.1 rejeita) e cujo fallback
## em `_place` também falhava (o caminho reconstruído saía malformado). Esse
## landmark nunca existiu de verdade em jogo — sempre foi `push_warning` e
## nada instanciado. Removido junto com o arquivo — item mecânico do plano de
## refinamento do PZ-01, Fase 2.
const PZ01_PLACEHOLDER_ROCK_HERO_01 := "PZ01_PLACEHOLDER_ROCK_HERO_01"
const PZ01_PLACEHOLDER_GLAZE_01 := "PZ01_PLACEHOLDER_GLAZE_01"

## Ambiência subaquática validada visualmente (ver README, "Assets 3D"):
## densidade acima de ~0.02 afoga as cores dos corais.
const PZ01_WATER_BG := Color("#062C3B")
## Neutro desde 2026-09-02 — era `#48B7B1` (teal), e por ser GLOBAL (mesma
## intensidade em terra firme e sob a água) tingia até a cor dos props/chão
## seco, que deveriam ler na cor própria deles. O frio da água agora vem só
## da névoa de altura logo abaixo (`PZ01_FOG`), que já era fragmentada por
## cota — sem matiz, pra não mudar o TOM geral.
##
## Cinza médio (~58% de brilho). Foi clareado a `#C8C8C8` em 2026-09-08
## porque o elenco lia "apagado" perto do visualizador de modelo — mas a
## causa era a textura KTX2 chegando ~gamma 2,2 mais escura do decode do
## Godot (ver `godot-textures.mjs` no bestiário). Com a textura em PNG o
## clareamento estourava pele e cabelo, e voltou em 2026-09-09.
const PZ01_AMBIENT := Color("#959595")
## Subiu a 1.6 em 2026-09-08 compensando textura escura (ver `PZ01_AMBIENT`)
## e voltou a 1.35 em 2026-09-09 com a textura corrigida. O sol
## (`PZ01_SUN_ENERGY`) fez a mesma viagem nos mesmos dias.
const PZ01_AMBIENT_ENERGY := 1.35
const PZ01_FOG := Color("#163E61")
const PZ01_SUN := Color("#E9FFF8")
const PZ01_SUN_ENERGY := 1.35

## A iluminação é FRAGMENTADA por altura, não por região: a névoa fria é
## densa ABAIXO da linha d'água (névoa de altura do Environment) e rala acima
## dela — o leito fica imerso na murk e a costa emerge para um ar mais limpo,
## sem precisar de segundo Environment. A linha fica logo abaixo do topo do
## platô (`MapTerrain.LAND_HEIGHT` = 1,6) para os pontos de acesso atravessarem a
## superfície no meio da subida.
const PZ01_WATER_LINE := 1.25
## A base vale para o mapa inteiro (inclusive a costa — um resto de maresia);
## a densidade subaquática precisa ser alta porque, na câmera ortográfica
## inclinada, o raio de visão atravessa POUCO da camada baixa: a acumulação
## vem quase toda destes ~2,5 m de caminho dentro da murk.
const PZ01_FOG_BASE_DENSITY := 0.006
const PZ01_FOG_UNDERWATER_DENSITY := 1.0

## O tom quente do trecho seco vem de luzes de preenchimento locais sobre a
## vila da costa — luz posicional é naturalmente fragmentada, então dá pra
## aquecer só ali sem mexer no sol/ambiente globais (neutros desde
## 2026-09-02, ver `PZ01_AMBIENT`). Sem sombra: são banho de cor, não fonte
## de leitura.
##
## As posições são OFFSET a partir do comerciante (`WorldPopulator.MERCHANT_SPOT`,
## que é a âncora da vila), não coordenada de mundo. Até 2026-09-16 eram
## `(2, 5.5, -46)` e `(10, 5.5, -46.5)` — a vila do mapa de 120 m, onde a âncora
## ficava em `(4, 0, -46)` —, e nenhum dos dois resizes as moveu: a 350 m a
## vila foi para z ≈ -134 e as duas luzes ficaram acesas sobre mar aberto.
## Offset é medida de prédio, igual ao `VILLAGE_SPACING`: não escala.
##
## Desde 2026-09-20 ficam no meio dos dois vãos entre estruturas (metade do
## `VILLAGE_SPACING` para cada lado do comerciante) e 1,5 m à frente da linha
## das fachadas, que é onde os NPCs ficam de pé — a luz existe para ler o rosto
## deles, não o telhado. O alcance subiu de 13 para 14 m porque a vila
## alargou: a parede externa da bancada e a do posto ficam a ~11,9 m do
## comerciante.
const PZ01_COAST_LIGHT := Color("#FFD9A6")
const PZ01_COAST_LIGHT_ENERGY := 1.1
const PZ01_COAST_LIGHT_RANGE := 14.0
const PZ01_COAST_LIGHT_OFFSETS: Array = [
	Vector3(-WorldPopulator.VILLAGE_SPACING * 0.5, 5.5, 1.5),
	Vector3(WorldPopulator.VILLAGE_SPACING * 0.5, 5.5, 1.5),
]
## A ilha da arena recebe o mesmo banho quente pela mesma regra: chão que
## emerge sai da murk também na luz. Uma omni só, centrada — o platô inteiro
## cabe no alcance.
const PZ01_ISLAND_LIGHT_SPOT := Vector3(0.0, 6.0, 0.0)
const PZ01_ISLAND_LIGHT_RANGE := 12.0

## Paleta do solo, consumida pelo shader do `MapTerrain` (base/variação por
## ruído/inclinações).
##
## Era turquesa (`#67D0C0`/`#4DB4A4`) desde a Fase 1, lida da concept art de
## visão geral do mapa inteiro — mar raso turquesa, massa rochosa escura. Essa
## paleta nunca fechou com o kit de rocha real de BIO-002: postar prop marrom
## sobre chão turquesa lia como duas cenas coladas, e foi exatamente o que
## apareceu na captura de 2026-09-01 (chão claro, quase amarelo-esverdeado —
## a mistura de turquesa com a faixa seca antiga — contra rocha marrom-escura
## dos props). Trocada por uma rampa só, derivada da cor MÉDIA medida direto
## das texturas do kit (`Rocky_Plateau`/`Rocky_Outcrop`/`Cracked_*`, sonda
## direta: `#79674c`) — chão e rocha na mesma família de cor, de propósito.
## Isso também bate com um ponto já registrado em `BIOME_PROPS.md`: mar raso
## tem de ler mais simples que o recife, não igual — o mesmo kit visual dos
## dois biomas era parte do problema.
const PZ01_GROUND := {
	"color_base": Color("#8A7860"),
	"color_alt": Color("#6E5F49"),
	"color_slope": Color("#5A4E3C"),
	"color_coast": Color("#9C8868"),
}

## Landmarks fixos: [arquivo, posição, yaw, escala, raio de colisão].
## Raio 0 = atravessável (o arco é passagem por baixo de propósito). Os
## modelos do Meshy chegam normalizados em ~1×1×1 — a escala aqui é o porte.
## Posições evitam os pontos fixos do `WorldPopulator` e a origem do jogador.
##
## O MIOLO ficou vazio de coral quando a ilha subiu ali: seis peças que
## estavam entre 4 e 8 m do centro foram para o anel de 11–15 m, onde
## continuam sendo recife submerso. Coral apoiado na encosta seca da ilha
## seria a mesma contradição que a costa já não comete.
##
## No resize de 2026-08-28 as posições do MAR dobraram junto com o mapa e as
## DUAS da ilha não — a ilha não escalou, e uma pedra de silhueta que saísse
## de cima dela deixaria de ser silhueta de coisa nenhuma. O anel de recife
## foi de 11–15 m para 22–30 m, que é o raio que a região RGN-002 do catálogo
## descreve em coordenada normalizada (`r 0.5`) — e é por isso que aquela
## linha do catálogo não precisou ser reautorada.
## Fator que leva as posições de MAR do tamanho em que foram autoradas (o mapa
## de 120 m) para o tamanho corrente. Escrito assim — e não com os metros já
## multiplicados — para o número autorado continuar legível ao lado da peça:
## quem for remexer o layout mexe em `Vector3(14, 0, -26)`, não em
## `Vector3(40.8, 0, -75.8)`. As DUAS peças da ilha, no fim do array, não
## recebem o fator: a ilha não escala, e uma pedra de silhueta que saísse de
## cima dela deixaria de ser silhueta de coisa nenhuma.
const _SEA_SCALE := float(MapTerrain.SIZE) / 120.0

const PZ01_LANDMARKS: Array = [
	# Placeholders explícitos para a próxima iteração de GLBs do conceito.
	# Todos eles são resolvidos para um asset de teste equivalente sem mexer na
	# montagem do layout do mapa. O terceiro placeholder (hero do recife,
	# escala 8.0) saiu em 2026-09-01 junto com `pz01_reef_hero_01.tscn` — a
	# peça nunca renderizou nem uma vez (arquivo quebrado desde que foi
	# criado), então remover a linha não muda nada do que já estava em jogo.
	[PZ01_PLACEHOLDER_ROCK_HERO_01, Vector3(14, 0, -26) * _SEA_SCALE, 2.4, 6.0, 1.4],
	[PZ01_PLACEHOLDER_GLAZE_01, Vector3(-26, 0, 22) * _SEA_SCALE, 4.1, 5.0, 1.2],
	["Coralstone_Arch", Vector3(6, 0, -30) * _SEA_SCALE, 0.4, 9.0, 0.0],
	["Coralstone_Arch", Vector3(-36, 0, 28) * _SEA_SCALE, 2.0, 7.0, 0.0],
	["Turquoise_Reef_Stone", Vector3(-26, 0, -18) * _SEA_SCALE, 1.2, 5.0, 2.2],
	["Turquoise_Reef_Stone", Vector3(32, 0, 24) * _SEA_SCALE, 0.3, 4.0, 1.8],
	["Jade_Reef_Garden", Vector3(28, 0, -8) * _SEA_SCALE, 2.6, 4.0, 1.8],
	["Jade_Reef_Garden", Vector3(-40, 0, -4) * _SEA_SCALE, 5.0, 3.2, 1.5],
	["Terraced_Stone_Mounds", Vector3(-12, 0, 24) * _SEA_SCALE, 5.2, 3.8, 1.6],
	["Terraced_Stone_Mounds", Vector3(24, 0, -28) * _SEA_SCALE, 1.0, 3.0, 1.3],
	["Aqua_Bloom_Grove", Vector3(22, 0, 10) * _SEA_SCALE, 4.0, 3.5, 1.5],
	["Pastel_Tidepool_Treas", Vector3(-24, 0, 12) * _SEA_SCALE, 3.1, 3.0, 1.3],
	["Aqua_Coral_Garden", Vector3(6, 0, 24) * _SEA_SCALE, 0.9, 3.2, 0.0],
	["Aqua_Sponge_Cluster", Vector3(18, 0, 20) * _SEA_SCALE, 1.7, 2.6, 0.0],
	["Seafoam_Pipe_Coral", Vector3(20, 0, -16) * _SEA_SCALE, 0.0, 2.8, 0.0],
	["Reef_Cluster", Vector3(-22, 0, -8) * _SEA_SCALE, 0.6, 2.4, 0.0],
	# Na ilha: duas pedras miúdas no topo, uma de cada lado da arena. São
	# silhueta — sem elas o platô lê como bolha de terreno em vez de rochedo,
	# e é a silhueta que a câmera ortográfica dá ao jogador de longe. Porte
	# pequeno de propósito: peça grande aqui esconderia o duelista.
	# As duas são o MESMO modelo em porte e giro diferentes, e isso é escolha:
	# `Terraced_Stone_Mounds` é a única peça do kit que lê como rocha em vez de
	# coral. Um coral de pé em terra seca contradiz a ilha inteira — foi o que
	# a primeira captura mostrou, com um recife turquesa ao lado do duelista.
	["Terraced_Stone_Mounds", Vector3(3.4, 0, 1.6), 0.8, 2.2, 1.0],
	["Terraced_Stone_Mounds", Vector3(-3.4, 0, -1.2), 2.3, 2.6, 0.9],
]

## Vegetação miúda espalhada por semente: [arquivo, escala mín, escala máx].
## Nada aqui tem colisão — pisar numa alga é pisar numa alga.
##
## Trocado em 2026-09-18 pelo kit próprio do mar raso (`MAR_RASO_KIT`): as
## oito peças antigas eram todas do acervo de coral do recife (ver
## `BIOME_PROPS.md` §4) e por isso os dois biomas liam como um só. As
## escalas abaixo são ponto de partida — ainda não calibradas visualmente
## como as que substituem.
const PZ01_SCATTER_POOL: Array = [
	["Cratered_Sand_Mound", 1.6, 2.8],
	["Floating_Highlands", 2.2, 3.8],
	["Sandy_Furrows", 2.5, 4.2],
	["Stone_Plateau_Sands", 1.8, 3.2],
	["Terraced_Sandstone_Mo", 1.6, 3.0],
]

## Os RAIOS acompanham o mapa (é geografia: o anel tem de cobrir o mar que
## existe), mas a CONTAGEM é escrita à mão — e essa separação é deliberada,
## não descuido: a contagem é a única coisa deste arquivo que custa nó da
## árvore, então quem a define é o orçamento, não uma regra de três.
##
## A regra de referência é densidade constante, a do mapa de 120 m: contagem
## pela ÁREA do anel (28 props num anel de 4–27 m; 116 num de 8–55 m). A 350 m
## (2026-09-06) ela pedia ~990 aqui e ~1.190 no recife, sem `MultiMesh` para
## segurar isso, e a contagem ficou sub-escalada (350/420) — o mapa leu mais
## esparso que o de 120 m enquanto teve aquele tamanho.
##
## No resize de 175 m (2026-09-16) a mesma conta pede ~250 aqui e ~300 no
## recife, ABAIXO do que já rodava, então a densidade de 120 m voltou sem
## custo nenhum. Manter 350/420 num quarto da área teria deixado o mapa 4x
## mais denso de uma vez — mudança de leitura que não foi pedida junto com o
## resize.
##
## Subiu de 250 pra 284 em 2026-09-18, quando o platô glacial encolheu ao
## tamanho da costa (`map_terrain.gd`): a área elegível pro passe geral (mar
## raso + recife, tudo que não é costa/ilha/glacial/abismo) cresceu ~13,5%
## porque o território que o platô liberou vira majoritariamente Mar Raso
## (medido por sonda, `probe_scatter_ratio.gd`, descartada) — mesma
## contagem, área maior, teria lido mais esparso sem ninguém ter pedido isso.
## `test_biome_dressing.gd` foi quem acusou (mar raso passou de ~5% pra 12,3%
## de telas com no máximo uma peça, contra um teto de 12%).
const PZ01_SCATTER_COUNT := 284
const PZ01_SCATTER_SEED := 20260824
## Separação prop-a-prop do passe geral. Tem o mesmo valor de `CLEAR_RADIUS`
## mas não é o mesmo papel: aquele afasta cenário dos serviços, este espaça as
## peças entre si. Separados desde 2026-09-17 para poderem mudar sozinhos.
##
## O espaçamento uniforme que 3,5 m produz é o que garante que toda tela do mar
## raso tenha peça. Foi medido ao tentar trocá-lo por aglomerados (ver
## `_scatter`): com o orçamento de 250 peças, qualquer aglomeração por posição
## deixava de 24% a 34% das telas com no máximo uma peça, contra 6% deste.
const PZ01_SCATTER_MIN_SEP := 3.5
## Manchas de espécie do passe geral (ver `_scatter`).
##
## - `radius`: raio típico de uma mancha (m). 10 m numa tela de ~24 m de
##   largura põe duas a quatro manchas em quadro: dá para ler "campo de alga"
##   sem que a tela inteira vire uma peça só.
## - `dominance`: chance de a peça ser a espécie da mancha; o resto é sorteio
##   livre, que é o que deixa intrusas dentro do campo.
##
## Medido em 2026-09-17 (`test_biome_dressing`): o vizinho mais próximo é da
## mesma espécie em 47% das peças — 3,7× o sorteio livre, que é o que o layout
## anterior fazia (~11% medido por sonda). 5,3% das telas do mar raso ficam
## com no máximo uma peça, a mesma ordem do layout anterior (~6% na sonda).
## `dominance` 0,85 media ~62% na sonda — mais "canteiro", menos variedade
## por quadro; é o número a subir se as manchas lerem fracas.
const PZ01_PATCH := {
	"radius": 10.0,
	"dominance": 0.7,
}
const SCATTER_RADIUS_MIN := 0.133333 * float(MapTerrain.SIZE) * 0.5
const SCATTER_RADIUS_MAX := 0.916667 * float(MapTerrain.SIZE) * 0.5

## Preenchimento denso do recife (BIO-003), pedido do usuário em 2026-09-02:
## o kit aquático inteiro era temático de mar raso/recife (nenhuma peça é
## glacial ou de mar profundo), e o recife deve ler MUITO mais cheio que o
## resto do mar raso — metade da escala normal, pra caber em quantidade sem
## virar amontoado de peças grandes se sobrepondo.
##
## Até 2026-09-18 eram os mesmos nomes do pool geral, só com min/max
## divididos por 2 — não é mais verdade desde que o mar raso ganhou kit
## próprio (`MAR_RASO_KIT`, ver `PZ01_SCATTER_POOL`). As cinco últimas
## entradas (`Azure_Coral_Horn` em diante) são peças novas somadas ao
## `AQUA_KIT` no mesmo dia; escalas ainda não calibradas visualmente.
const PZ01_REEF_SCATTER_POOL: Array = [
	["Emerald_Seaweed_Grove", 1.25, 2.25],
	["Seafoam_Pipe_Coral", 0.75, 1.25],
	["Aqua_Coral_Garden", 0.9, 1.5],
	["Reef_Cluster", 0.6, 1.1],
	["Aqua_Sponge_Cluster", 0.75, 1.25],
	["Aqua_Bloom_Grove", 0.75, 1.25],
	["Pastel_Tidepool_Treas", 0.7, 1.3],
	["Terraced_Stone_Mounds", 0.65, 1.25],
	["Azure_Coral_Horn", 0.7, 1.3],
	["Blue_Porous_Bowl", 0.6, 1.1],
	["Pink_Coral_Spire", 0.8, 1.5],
	["Spiky_Orange_Spheres", 0.5, 1.0],
	["Verdant_Root_Chalice", 0.7, 1.3],
]
## Mesma régua da contagem geral acima: a densidade de área do mapa de 120 m,
## que a 175 m dá ~300 (era 420 sub-escalado a 350 m, ver lá). O recife
## continua sendo o trecho MAIS cheio do mapa.
const PZ01_REEF_SCATTER_COUNT := 300
const PZ01_REEF_SCATTER_SEED := 20260902
## Bem mais apertado que `CLEAR_RADIUS` (3,5 m) de propósito — é o que faz o
## recife ler denso em vez de espalhado; peça pela metade do porte cabe em
## separação menor sem colar.
const PZ01_REEF_MIN_SEP := 1.4
## Manchas de espécie do recife: menores que as do mar raso (6 m), porque a
## peça tem metade do porte e o recife é o bioma que mais deve variar por
## quadro. Medido: vizinho da mesma espécie em 46% das peças (~15% antes), e
## nenhuma das telas amostradas com menos de duas peças. Campos em
## `PZ01_PATCH`.
const PZ01_REEF_PATCH := {
	"radius": 6.0,
	"dominance": 0.7,
}
## Os passes de scatter, na ordem em que rodam (`scatter_layout`). A ordem
## importa: cada passe rejeita posição já ocupada pelos anteriores.
const SCATTER_PASSES := ["general", "reef", "coast_rock", "coast_pebble"]

## ## A costa ganha props (2026-09-17)
##
## Ela era o único trecho seco sem NADA plantado — decisão antiga e correta
## enquanto o kit disponível era coral tropical (`_is_excluded_biome` e o
## orçamento ×0,15 de `BIOME_PROPS.md` §3 registram o porquê). O efeito
## colateral era a leitura de PISO: por boa que a textura fique, chão liso
## sem nada cruzando o plano não lê como lugar.
##
## Quem resolve isso são as pedras do MegaKit (Quaternius, CC0), que já estão
## no projeto para o terrestre do PZ-02/03. Pedra não é vegetação, então não
## esbarra na regra de época que proíbe planta terrestre no PZ-01 — e é por
## isso que o kit inteiro continua reservado, mas estas peças não.
##
## **As peças do MegaKit NÃO são normalizadas em 1×1×1** como as do Meshy: vêm
## em escala real, medidas por sonda em 2026-09-17 — `Rock_Medium_*` tem ~3 m
## de largura e ~2 m de altura, `Pebble_*` ~0,4 m por ~0,1 m. Os pares de
## escala abaixo já levam isso em conta, e é por isso que eles não se parecem
## com os do pool aquático.
const MEGA_KIT := "res://models/biomes/megakit/"

## Matacão: a peça que quebra o plano. Escala 0,35–0,75 dá 1,1–2,6 m de largura
## — da altura do ombro de uma criatura (1,4 m) para baixo, para não competir
## com landmark nem tapar NPC.
const PZ01_COAST_ROCK_POOL: Array = [
	[MEGA_KIT + "Rock_Medium_1.gltf", 0.35, 0.75],
	[MEGA_KIT + "Rock_Medium_2.gltf", 0.35, 0.75],
	[MEGA_KIT + "Rock_Medium_3.gltf", 0.3, 0.65],
]
const PZ01_COAST_ROCK_COUNT := 22
const PZ01_COAST_ROCK_SEED := 20260917
const PZ01_COAST_ROCK_MIN_SEP := 2.2
## A faixa de distância da água (m) em que matacão pode nascer. Fica CENTRADA
## em `PZ01_COAST_WET_WIDTH`: a ideia é a pedra cruzar a linha onde a lama
## úmida vira terra seca, porque é a transição que mais precisa de algo em pé
## por cima dela.
const PZ01_COAST_ROCK_BAND := Vector2(2.0, 12.0)
## Matacão anda acompanhado: depois de plantar um, tenta de 1 a 2 vizinhos
## perto, e é isso que faz o resultado ler como afloramento em vez de pedra
## solta a cada tantos metros. Aqui o agrupamento por POSIÇÃO é o objetivo (ao
## contrário do scatter de mar, onde ele custava cobertura — ver `_scatter`):
## não existe promessa de "toda tela tem pedra", e a costa tem serviço e
## portal para preencher o resto.
const PZ01_COAST_ROCK_CLUSTER := Vector2(1.6, 3.2)

## Seixo: detalhe de chão, espalhado pelo platô inteiro. Escala 0,8–1,8 dá
## 0,3–0,9 m — grande o bastante para aparecer na ortográfica, pequeno o
## bastante para ninguém tentar contornar.
const PZ01_COAST_PEBBLE_POOL: Array = [
	[MEGA_KIT + "Pebble_Round_1.gltf", 1.2, 2.4],
	[MEGA_KIT + "Pebble_Round_3.gltf", 1.2, 2.4],
	[MEGA_KIT + "Pebble_Round_5.gltf", 1.2, 2.4],
	[MEGA_KIT + "Pebble_Square_2.gltf", 1.2, 2.2],
	[MEGA_KIT + "Pebble_Square_4.gltf", 1.2, 2.2],
	[MEGA_KIT + "Pebble_Square_6.gltf", 1.2, 2.2],
]
const PZ01_COAST_PEBBLE_COUNT := 90
const PZ01_COAST_PEBBLE_SEED := 20260918
const PZ01_COAST_PEBBLE_MIN_SEP := 1.2
## Seixo não nasce na rampa molhada nem na beirada: abaixo disto o chão já está
## dentro ou perto da água.
const PZ01_COAST_PEBBLE_MIN_INLAND := 2.0

## Largura (m) da faixa de lama úmida da costa. Vive aqui, e não como default
## do shader, porque os DOIS lados a usam: a cor (via `ground_palette`) e a
## linha em que os matacões nascem (`PZ01_COAST_ROCK_BAND`).
const PZ01_COAST_WET_WIDTH := 7.0

## ## A praça da vila (2026-09-20)
##
## O adro dos três serviços da costa é chão "pavimentado por gente": uma
## terceira camada de textura (lajes de pedra, Stone Wall 1 do mesmo pack da
## lama) que só aparece dentro de uma máscara em volta da vila, bakeada na
## grade do terreno (`MapTerrain.bake_mask`) e entregue ao shader como
## `village_mask_tex`. A forma é um retângulo de cantos arredondados centrado
## na âncora da vila, com o MESMO warp de borda que o relevo usa
## (`MapTerrain.edge_warp`) — um retângulo liso ao lado de uma costa
## irregular leria como adesivo.
##
## `plaza_profile` é a fonte ÚNICA da forma: a cor (via máscara), o keep-out
## do scatter (matacão e seixo não nascem no miolo) e a posição das lajes
## soltas (`PZ01_VILLAGE_PROPS`) saem todos da mesma função, pela lição do
## `glacial_mask_tex` — geometria e cor não podem discordar.
##
## Os offsets são a partir de `WorldPopulator.VILLAGE_ANCHOR` (o comerciante),
## em metros, como as luzes: medida de prédio, não escala com o mapa. O
## centro é puxado 1,5 m para a frente (+Z, lado do mar) porque é lá que as
## pessoas ficam e de onde o jogador chega; o meio-lado em X cobre os três
## serviços (`VILLAGE_SPACING` de cada lado do comerciante) mais ~2 m além das
## paredes externas. O tom aquece a Stone Wall 1 (cinza-azulada de origem)
## para a família do `color_coast`; a escala dá lajes de ~0,6–0,9 m, menores
## que as placas de lama, para ler como pedra assentada.
const PZ01_PAVED_TINT := Color("#D9C7AA")
const PZ01_PAVED_TEX_SCALE := 0.16
const PZ01_PLAZA_CENTER_OFFSET := Vector3(0.0, 0.0, 1.5)
const PZ01_PLAZA_HALF := Vector2(14.0, 6.0)
const PZ01_PLAZA_CORNER := 4.0
## Largura (m) do esmaecimento da borda — é onde a lama sobe pelas juntas
## das lajes (`village_paving` no shader).
const PZ01_PLAZA_FEATHER := 1.5
## Amplitude do warp da borda da praça. Menor que a da costa (4 + 1,5 m): um
## retângulo de 28 × 12 m não aguenta 5,5 m de deformação sem virar mancha.
const PZ01_PLAZA_WARP := 2.0
## Acima disto no `plaza_profile` o scatter da costa não entra: o miolo fica
## livre para as pessoas e para o spawn. Na orla (abaixo) matacão e seixo
## continuam nascendo — são eles que cruzam o plano na transição, que é o
## que faz uma borda de textura ler como lugar e não como tapete.
const PZ01_PLAZA_KEEPOUT := 0.6

## Props da vila, à mão, em offset da `VILLAGE_ANCHOR` — padrão de
## `PZ01_LANDMARKS`, não de scatter: a praça é layout, e cada peça tem lugar.
##
## Dois tipos de entrada, pela convenção de pivô do arquivo:
##   - `scale`  → peça do MegaKit (pivô na BASE, escala real): passa pelo
##                `_place` comum, com o afundamento de sempre;
##   - `height` → peça gerada no Tripo (pivô no CENTRO, como as estruturas —
##                ver `InteractableActor._load_model`): `_plant_village` mede
##                a AABB, escala para a altura pedida em metros e apoia a base
##                no chão. Auto-calibrado: peça nova entra sem sonda.
##
## As lajes `RockPath_*` ficam na ORLA da praça (`plaza_profile` entre 0,1 e
## 0,9), cruzando a borda da textura — nunca na rampa: `_place` apoia só o
## centro da peça, e numa rampa uma laje de 2 m flutuaria numa ponta. Todas a
## mais de `CLEAR_RADIUS` do spawn e a mais de 1 m das pessoas
## (`test_biome_dressing` cobra as duas; a isenção do raio em volta dos TRÊS
## SERVIÇOS é de propósito: a regra existe para cenário sorteado não tapar um
## serviço, e layout à mão é decisão, não entulho).
##
## A cerca de pedra e corda (`cerca_corda.glb`, ~2 m, ~0,9 m de altura) é
## gerada no Tripo Studio pelo usuário e copiada à mão para
## `models/village/props/` (o `game:export` não espelha `models/village/`,
## como os quatro prédios). Enquanto o arquivo não existe, a entrada é pulada
## em silêncio — `village_layout` só devolve o que carrega.
const PZ01_VILLAGE_PROPS: Array = [
	# orla esquerda
	{"file": MEGA_KIT + "RockPath_Round_Wide.gltf", "at": Vector3(-13.5, 0.0, -1.0), "yaw": 0.4, "scale": 1.2},
	{"file": MEGA_KIT + "RockPath_Square_Wide.gltf", "at": Vector3(-14.0, 0.0, 3.5), "yaw": 1.9, "scale": 1.1},
	# orla direita
	{"file": MEGA_KIT + "RockPath_Round_Wide.gltf", "at": Vector3(13.8, 0.0, -2.5), "yaw": 2.6, "scale": 1.15},
	{"file": MEGA_KIT + "RockPath_Round_Small_2.gltf", "at": Vector3(14.2, 0.0, 2.5), "yaw": 0.9, "scale": 1.3},
	# orla da frente (lado do mar)
	{"file": MEGA_KIT + "RockPath_Square_Wide.gltf", "at": Vector3(-11.0, 0.0, 7.2), "yaw": 0.2, "scale": 1.2},
	{"file": MEGA_KIT + "RockPath_Round_Small_1.gltf", "at": Vector3(-6.0, 0.0, 7.8), "yaw": 2.2, "scale": 1.3},
	{"file": MEGA_KIT + "RockPath_Round_Wide.gltf", "at": Vector3(1.0, 0.0, 7.5), "yaw": 1.3, "scale": 1.1},
	{"file": MEGA_KIT + "RockPath_Round_Small_3.gltf", "at": Vector3(13.0, 0.0, 7.4), "yaw": 0.6, "scale": 1.3},
	# fundo, atrás das estruturas
	{"file": MEGA_KIT + "RockPath_Square_Small_2.gltf", "at": Vector3(-8.0, 0.0, -5.5), "yaw": 1.1, "scale": 1.3},
	{"file": MEGA_KIT + "RockPath_Round_Small_1.gltf", "at": Vector3(9.5, 0.0, -6.0), "yaw": 2.9, "scale": 1.2},
	# cerca de pedra e corda (Tripo; ver acima) — laterais, com vão de passagem
	{"file": "res://models/village/props/cerca_corda.glb", "at": Vector3(15.5, 0.0, -2.5), "yaw": PI * 0.5, "height": 0.9},
	{"file": "res://models/village/props/cerca_corda.glb", "at": Vector3(15.5, 0.0, 2.0), "yaw": PI * 0.5, "height": 0.9},
	{"file": "res://models/village/props/cerca_corda.glb", "at": Vector3(-14.5, 0.0, -4.5), "yaw": PI * 0.5, "height": 0.9},
]

## Fração da escala que cada prop afunda abaixo do relevo — esconde o corte
## reto da base da malha na borda do chão. É também o que define o PIVÔ do
## balanço (`_sway_material`): o ponto em que o chão corta a peça é o ponto
## que não pode se mover.
const SINK_FRACTION := 0.05

## Peças que balançam na corrente, e quanto: deslocamento na PONTA, em
## unidades locais da peça (o kit é ~1×1×1, então 0,10 = 10% da altura).
## Peça fora desta lista fica parada, e isso é a maioria de propósito: coral
## duro, pedra, arco e poça não balançam, e um leito em que TUDO se mexe lê
## como distorção de tela, não como água.
##
## Escolhido pelo nome e pelo papel no kit (`BIOME_PROPS.md` §2), não por
## inspeção de malha — é o ajuste a olho mais provável desta lista, e é por
## isso que é uma tabela por nome e não uma regra.
const SWAY := {
	"Emerald_Seaweed_Grove": 0.10,
	"Aqua_Bloom_Grove": 0.06,
	"Aqua_Sponge_Cluster": 0.03,
}
## Ritmo do balanço (rad/s da senoide principal). Lento: corrente de leito
## raso, não rebentação.
const SWAY_SPEED := 0.8
const SWAY_SHADER := preload("res://shaders/prop_sway.gdshader")
## A direção do balanço não mora aqui: é `MapTerrain.WATER_FLOW_DIR`, a mesma
## que o material da água recebe.

## Peças cuja cor de base é multiplicada por um tom, por nome de arquivo.
##
## Existe para o MegaKit: as pedras dele são cinza-azuladas (o kit foi feito
## para floresta temperada), e na costa quente do PZ-01 o seixo lia como
## lasca de gelo no chão — visível na captura de 2026-09-17. Tingir é o
## caminho certo porque a textura é COMPARTILHADA com o uso terrestre de
## PZ-02/03: recolorir o arquivo mudaria os dois, e o material tingido nasce
## em runtime só para quem está nesta lista.
##
## Matacão NÃO é tingido de propósito: ele é grande o bastante para ler como
## rocha de outra origem (matacão errático é justamente isso), e o cinza dele
## é o que o separa do chão em silhueta.
const TINT := {
	MEGA_KIT + "Pebble_Round_1.gltf": Color("#E3C39F"),
	MEGA_KIT + "Pebble_Round_3.gltf": Color("#E3C39F"),
	MEGA_KIT + "Pebble_Round_5.gltf": Color("#DDBE9C"),
	MEGA_KIT + "Pebble_Square_2.gltf": Color("#E3C39F"),
	MEGA_KIT + "Pebble_Square_4.gltf": Color("#DDBE9C"),
	MEGA_KIT + "Pebble_Square_6.gltf": Color("#E3C39F"),
	# As lajes da praça da vila: mesmo cinza-azulado do kit, um tom acima do
	# seixo para ler como pedra assentada, não como pedra do chão.
	MEGA_KIT + "RockPath_Round_Wide.gltf": Color("#D8C2A2"),
	MEGA_KIT + "RockPath_Square_Wide.gltf": Color("#D8C2A2"),
	MEGA_KIT + "RockPath_Round_Small_1.gltf": Color("#D8C2A2"),
	MEGA_KIT + "RockPath_Round_Small_2.gltf": Color("#D8C2A2"),
	MEGA_KIT + "RockPath_Round_Small_3.gltf": Color("#D8C2A2"),
	MEGA_KIT + "RockPath_Square_Small_2.gltf": Color("#D8C2A2"),
}

## Um `ShaderMaterial` por material importado, não por instância: as ~550
## peças do mapa compartilham 11 materiais importados (cache de recurso do
## Godot), e as que balançam devem continuar compartilhando — um material por
## prop colocado seria centenas de materiais para três variações.
static var _sway_cache := {}
## Mesma regra para os materiais tingidos, com a cor na chave: dois tons da
## mesma peça são dois materiais, e não um por seixo plantado.
static var _tint_cache := {}

## Nenhum prop nasce a menos disto dos pontos de interação/origem — cenário
## não pode esconder um serviço nem entulhar o spawn do jogador.
const CLEAR_RADIUS := 3.5


## Paleta do solo deste mapa, para o `MapTerrain` — vazia = shader nos
## defaults. Vive aqui (e não no terreno) porque cor de bioma é vestimenta.
##
## Carrega também a largura da faixa úmida da costa, que não é cor: é a MESMA
## medida que este arquivo usa para plantar matacão na linha da água
## (`PZ01_COAST_WET_WIDTH`). Ela viaja junto porque o caminho até o shader já
## existe (o `MapTerrain` escreve toda chave desta tabela como uniform), e
## porque a alternativa — cada lado com o seu número — é a linha de pedra
## seguindo uma borda que a cor desenhou noutro lugar.
static func ground_palette(map_code: String) -> Dictionary:
	if map_code != "PZ-01":
		return {}
	var out := PZ01_GROUND.duplicate()
	out["coast_wet_width"] = PZ01_COAST_WET_WIDTH
	# A praça da vila (ver o bloco "A praça da vila"): cor é vestimenta —
	# mora aqui, não no shader.
	out["paved_tint"] = PZ01_PAVED_TINT
	out["paved_tex_scale"] = PZ01_PAVED_TEX_SCALE
	return out


## Cota da superfície da água deste mapa; `-INF` = mapa seco.
##
## Mesmo raciocínio da paleta: onde fica a superfície é decisão de bioma, e o
## terreno só a consome. A cota é a MESMA que fragmenta a névoa, e tem de
## continuar sendo: se o jogador nadasse numa cota e a murk trocasse noutra, a
## imagem contradiria o corpo na rampa da costa.
static func water_line(map_code: String) -> float:
	return PZ01_WATER_LINE if map_code == "PZ-01" else -INF


static func apply(root: Node3D, map_code: String, terrain: MapTerrain = null, map_biomes: MapBiomes = null) -> void:
	if map_code != "PZ-01":
		return

	_apply_pz01_ambience(root)

	var holder := Node3D.new()
	holder.name = "Dressing"
	root.add_child(holder)

	# Material de balanço é cacheado por material importado (ver `_sway_material`).
	# Zerado a cada montagem: a chave é id de instância, e um id de recurso que o
	# Godot liberou entre duas montagens do mundo pode ser reutilizado por outro.
	_sway_cache.clear()
	_tint_cache.clear()

	for l in active_landmarks(map_biomes):
		_place(holder, terrain, l[0], l[1], l[2], l[3], l[4])

	var layout := scatter_layout(terrain, map_biomes)
	for pass_name in SCATTER_PASSES:
		# "general" é o passe do mar raso — único que usa o kit próprio dele
		# desde a separação de 2026-09-18. Os outros passes (recife, costa)
		# continuam no `AQUA_KIT`/MegaKit de sempre.
		var pass_kit := MAR_RASO_KIT if pass_name == "general" else AQUA_KIT
		for e in layout[pass_name]:
			_place(holder, terrain, e[0][0], e[1], e[2], e[3], 0.0, pass_kit)

	# A praça da vila: a máscara para o shader e as peças à mão, num nó
	# próprio (`Dressing/Village`) para a suíte separar layout de scatter.
	_pave_plaza(terrain)
	var village := Node3D.new()
	village.name = "Village"
	holder.add_child(village)
	_plant_village(village, terrain)


## Os landmarks que entram no mapa.
##
## O kit aquático inteiro é temático de mar raso/recife — nenhuma peça dele é
## glacial ou de mar profundo (pedido do usuário, 2026-09-02). A costa
## (BIO-002) já não tem landmark nenhum desde a Fase 2; aqui é só filtrar as
## duas geografias que ainda tinham peça por acidente de posição, não por
## intenção.
static func active_landmarks(map_biomes: MapBiomes) -> Array:
	var out: Array = []
	for l in PZ01_LANDMARKS:
		if map_biomes and _is_excluded_biome(map_biomes.biome_at(l[1])):
			continue
		out.append(l)
	return out


## Onde cada peça de scatter vai, sem instanciar nada: um `Array` por passe
## (`SCATTER_PASSES`), cada entrada `[pick, pos, yaw, escala]`.
##
## Separado de `apply` para a suíte (`test_biome_dressing`) medir o layout que
## o jogo PLANTA — com os passes separados, que na árvore de cena já chegam
## misturados num nó só — em vez de uma réplica dele que poderia divergir.
static func scatter_layout(terrain: MapTerrain, map_biomes: MapBiomes) -> Dictionary:
	var clear_spots := _clear_spots()
	var occupied: Array[Vector3] = []
	for l in active_landmarks(map_biomes):
		occupied.append(l[1])

	# A costa fica sem bioma natural — é o adro dos NPCs e portais. A ilha
	# também: o que cresce nela são as duas pedras fixas, postas à mão.
	# Margem de 1,5 m para nenhuma alga nascer encostada na saia.
	var off_dry := func(pos: Vector3) -> bool:
		return not (terrain and (terrain.on_coast(pos) or terrain.on_island(pos, 1.5)))

	var general: Array = []
	_scatter(
		func(pick: Array, pos: Vector3, yaw: float, s: float) -> void: general.append([pick, pos, yaw, s]),
		PZ01_SCATTER_POOL, PZ01_SCATTER_COUNT, PZ01_SCATTER_SEED,
		SCATTER_RADIUS_MIN, SCATTER_RADIUS_MAX, PZ01_SCATTER_MIN_SEP, 12,
		PZ01_PATCH, clear_spots, occupied,
		func(pos: Vector3) -> bool:
			return off_dry.call(pos) and not (map_biomes and _is_excluded_biome(map_biomes.biome_at(pos))))

	# Preenchimento denso do recife (BIO-003) por cima do scatter geral acima
	# — amostra por REJEIÇÃO sobre a própria partição de bioma (`biome_at`),
	# não um círculo recalculado aqui: a forma/posição do recife é dado do
	# catálogo, e duplicar isso em geometria própria é a mesma classe de erro
	# que `REEF_CENTER` já cometeu uma vez (ver `map_terrain.gd`). Raio de
	# amostragem parte de 0 (não de `SCATTER_RADIUS_MIN`) porque o recife
	# encosta perto da origem; `on_island`/`on_coast` acima de qualquer forma
	# protegem os dois trechos que não são recife mesmo perto do centro.
	var reef: Array = []
	_scatter(
		func(pick: Array, pos: Vector3, yaw: float, s: float) -> void: reef.append([pick, pos, yaw, s]),
		PZ01_REEF_SCATTER_POOL, PZ01_REEF_SCATTER_COUNT, PZ01_REEF_SCATTER_SEED,
		0.0, SCATTER_RADIUS_MAX, PZ01_REEF_MIN_SEP, 25,
		PZ01_REEF_PATCH, clear_spots, occupied,
		func(pos: Vector3) -> bool:
			return off_dry.call(pos) and map_biomes != null and map_biomes.biome_at(pos) == "BIO-003")

	# As peças da praça também ocupam lugar — seixo não nasce em cima de laje.
	# Entram SÓ agora, antes dos passes da costa: os passes do mar já rejeitam
	# a costa inteira por `off_dry`, e uma laje na lista de ocupados antes deles
	# mudaria a sequência de sorteio do mar raso por uma peça que ele nem
	# poderia plantar.
	for v in village_layout():
		occupied.append(v["pos"])
	var rocks := _coast_props(PZ01_COAST_ROCK_POOL, PZ01_COAST_ROCK_COUNT, PZ01_COAST_ROCK_SEED,
		PZ01_COAST_ROCK_MIN_SEP, PZ01_COAST_ROCK_BAND, PZ01_COAST_ROCK_CLUSTER,
		terrain, clear_spots, occupied)
	var pebbles := _coast_props(PZ01_COAST_PEBBLE_POOL, PZ01_COAST_PEBBLE_COUNT, PZ01_COAST_PEBBLE_SEED,
		PZ01_COAST_PEBBLE_MIN_SEP, Vector2(PZ01_COAST_PEBBLE_MIN_INLAND, INF), Vector2.ZERO,
		terrain, clear_spots, occupied)

	return {"general": general, "reef": reef, "coast_rock": rocks, "coast_pebble": pebbles}


## Props da costa, por faixa de distância da água em vez de anel.
##
## Não reusa `_scatter` de propósito: lá a posição é sorteada num ANEL em volta
## da origem e a espécie vem de manchas; aqui o domínio é uma faixa estreita ao
## longo da borda de um platô na quina do mapa, e o agrupamento é de posição.
## Sortear no anel para cair nessa faixa gastaria ~25 tentativas por peça.
##
## `band` é o intervalo aceito de `coast_inland_at` (a MESMA medida que o
## shader usa para pintar úmido/seco); `cluster` é o intervalo de distância de
## um vizinho de aglomerado, ou `Vector2.ZERO` para não agrupar.
##
## Nenhuma peça tem colisão (`PZ01_PROPS_COLLIDABLE`), então nada disto fecha a
## rampa nem cerca um serviço — o que os protege de virar cenário em cima do
## comerciante é `clear`, como em todo passe.
static func _coast_props(
	pool: Array,
	count: int,
	seed_value: int,
	min_sep: float,
	band: Vector2,
	cluster: Vector2,
	terrain: MapTerrain,
	clear: Array[Vector3],
	occupied: Array[Vector3]
) -> Array:
	if terrain == null:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var half := float(MapTerrain.SIZE) * 0.5
	# Caixa de sorteio: a largura do mapa pela profundidade do platô (o lobo é
	# a parte mais funda). Bem menor que o mapa, e é o que mantém a taxa de
	# aceitação alta sem duplicar a forma da costa aqui.
	var z_max := MapTerrain.COAST_TOP + MapTerrain.COAST_RAMP_WIDTH

	var accept := func(pos: Vector3) -> bool:
		if not terrain.on_coast(pos):
			return false
		# O miolo da praça da vila fica livre (ver `PZ01_PLAZA_KEEPOUT`).
		if plaza_profile(terrain, pos) > PZ01_PLAZA_KEEPOUT:
			return false
		var inland := terrain.coast_inland_at(pos)
		return inland >= band.x and inland <= band.y

	var out: Array = []
	var attempts := 0
	while out.size() < count and attempts < count * 40:
		attempts += 1
		var pos := Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, z_max))
		if not accept.call(pos) or _too_close(pos, clear) or _too_close(pos, occupied, min_sep):
			continue
		var pick: Array = pool[rng.randi() % pool.size()]
		out.append([pick, pos, rng.randf() * TAU, rng.randf_range(pick[1], pick[2])])
		occupied.append(pos)
		# Os vizinhos do aglomerado entram pelo mesmo crivo: um que caia na
		# água, em cima de outro ou perto de um serviço simplesmente não nasce.
		if cluster == Vector2.ZERO:
			continue
		for i in rng.randi_range(1, 2):
			if out.size() >= count:
				break
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(cluster.x, cluster.y)
			var near := pos + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			if not accept.call(near) or _too_close(near, clear) or _too_close(near, occupied, min_sep):
				continue
			var companion: Array = pool[rng.randi() % pool.size()]
			out.append([companion, near, rng.randf() * TAU, rng.randf_range(companion[1], companion[2])])
			occupied.append(near)
	return out


## Quanto da praça da vila existe neste ponto: 1 no miolo, 0 fora, com a orla
## esmaecida em `PZ01_PLAZA_FEATHER`. Fonte única da forma — ver o bloco "A
## praça da vila" nas constantes.
static func plaza_profile(terrain: MapTerrain, pos: Vector3) -> float:
	if terrain == null:
		return 0.0
	var center := WorldPopulator.VILLAGE_ANCHOR + PZ01_PLAZA_CENTER_OFFSET
	var w := terrain.edge_warp(pos.x, pos.z, PZ01_PLAZA_WARP)
	var sdf := terrain.rounded_rect_sdf(
		w.x, w.y, center.x, center.z, PZ01_PLAZA_HALF.x, PZ01_PLAZA_HALF.y, PZ01_PLAZA_CORNER)
	return 1.0 - smoothstep(-PZ01_PLAZA_FEATHER, PZ01_PLAZA_FEATHER, sdf)


## As peças da praça em coordenadas de MUNDO — só as que carregam. Pura, para
## a suíte medir o mesmo layout que `_plant_village` planta. Cada entrada
## copia a de `PZ01_VILLAGE_PROPS` com `pos` resolvido.
static func village_layout() -> Array:
	var out: Array = []
	for entry in PZ01_VILLAGE_PROPS:
		var file: String = entry["file"]
		if not ResourceLoader.exists(file):
			continue
		var e: Dictionary = entry.duplicate()
		e["pos"] = WorldPopulator.VILLAGE_ANCHOR + (entry["at"] as Vector3)
		out.append(e)
	return out


## Bakeia a máscara da praça na grade do terreno e a entrega ao shader.
static func _pave_plaza(terrain: MapTerrain) -> void:
	if terrain == null:
		return
	terrain.set_ground_uniform("village_mask_tex", terrain.bake_mask(
		func(x: float, z: float) -> float:
			return plaza_profile(terrain, Vector3(x, 0.0, z))))


## Planta as peças de `village_layout` — MegaKit pelo `_place` comum; peça do
## Tripo (pivô no centro) medida e apoiada aqui.
static func _plant_village(parent: Node3D, terrain: MapTerrain) -> void:
	for e in village_layout():
		if e.has("scale"):
			_place(parent, terrain, e["file"], e["pos"], float(e["yaw"]), float(e["scale"]), 0.0)
			continue
		var packed := load(e["file"]) as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate() as Node3D
		_flatten_specular(node)
		var aabb := InteractableActor.local_aabb(node)
		if aabb.size.y <= 0.0:
			node.free()
			continue
		var s := float(e["height"]) / aabb.size.y
		var pos: Vector3 = e["pos"]
		if terrain:
			pos.y = terrain.height_at(pos)
		# Base da AABB (escalada) no chão — a origem do modelo está no centro.
		pos.y -= aabb.position.y * s
		node.position = pos
		node.rotation.y = float(e["yaw"])
		node.scale = Vector3.ONE * s
		parent.add_child(node)


## Um passe de scatter: posição espaçada, espécie em MANCHAS.
##
## Até 2026-09-17 cada peça sorteava a espécie sozinha. Com oito peças no pool,
## o vizinho de qualquer peça era de outra espécie em ~89% dos casos — a
## leitura "salpicado" que nenhum leito real tem. Alga cresce em campo de alga,
## esponja em colônia.
##
## O passe agora espalha centros de mancha pelo anel (Voronoi: cada peça
## pertence à mancha de centro mais próximo, e as bordas saem irregulares por
## construção) e cada peça é, com chance `dominance`, a espécie da sua mancha.
##
## ## Por que não aglomerar a POSIÇÃO
##
## Foi a primeira versão, e está registrado para ninguém repetir sem medir. O
## passe abria aglomerados (centro, espécie, 6–12 peças em raio de 5 m) e o
## índice de Clark–Evans confirmou agrupamento real — 0,82× o acaso, contra
## 1,38× do espaçado antigo. Na tela, o mar raso esvaziou: com 250 peças,
## aglomerados ficam a ~16 m um do outro, e a câmera (~24 m de largura) cai
## entre eles. Telas com no máximo uma peça num raio de 8 m foram de 6% para
## 34%; variantes mais leves ficaram entre 24% e 37%, e até a que já nem
## agrupava (1,04×) perdia cobertura. O espaçamento uniforme era o que
## sustentava a cobertura com esse orçamento.
##
## Aglomerar posição volta a fazer sentido quando a densidade subir — que é o
## que o `MultiMesh` destrava (`BIOME_PROPS.md` §5). Até lá, o agrupamento é
## de espécie, que não custa cobertura nenhuma.
##
## A CONTAGEM e a SEMENTE não mudam; o layout sai diferente do anterior (outra
## sequência de sorteio), mas continua fixo entre execuções.
##
## Dois raios de exclusão: `clear` (pontos de serviço) sempre a `CLEAR_RADIUS`,
## `occupied` (outros props) a `min_sep` do passe. Antes eram a mesma lista.
##
## O plantio entra por `place` (`pick, pos, yaw, escala`) em vez de o passe
## chamar `_place` direto: o sorteio não depende de a peça existir, e separar
## os dois é o que deixa a suíte medir o layout sem instanciar cenário.
static func _scatter(
	place: Callable,
	pool: Array,
	count: int,
	seed_value: int,
	radius_min: float,
	radius_max: float,
	min_sep: float,
	attempts_per_prop: int,
	patch: Dictionary,
	clear: Array[Vector3],
	occupied: Array[Vector3],
	accept: Callable
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var patches := _species_patches(rng, pool, radius_min, radius_max, float(patch["radius"]))

	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * attempts_per_prop:
		attempts += 1
		var pos := _ring_point(rng, radius_min, radius_max)
		if not accept.call(pos) or _too_close(pos, clear) or _too_close(pos, occupied, min_sep):
			continue
		var pick: Array = pool[rng.randi() % pool.size()]
		if rng.randf() < float(patch["dominance"]):
			pick = _patch_species(patches, pos)
		place.call(pick, pos, rng.randf() * TAU, rng.randf_range(pick[1], pick[2]))
		occupied.append(pos)
		placed += 1


## Centros de mancha espalhados pelo anel do passe, cada um com a sua espécie.
##
## Quantidade pela ÁREA do anel sobre a de uma mancha (`raio²`, sem o π, que
## cancela), e distância sorteada uniforme em ÁREA (`sqrt` do quadrado) —
## sorteio uniforme em raio amontoaria manchas pequenas no miolo e deixaria as
## da borda enormes. Os centros não passam pelos filtros de terreno de
## propósito: centro caído em terra seca continua moldando as manchas vizinhas.
static func _species_patches(rng: RandomNumberGenerator, pool: Array, radius_min: float, radius_max: float, patch_radius: float) -> Array:
	var n := maxi(1, ceili((radius_max * radius_max - radius_min * radius_min) / (patch_radius * patch_radius)))
	var patches: Array = []
	for i in n:
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf_range(radius_min * radius_min, radius_max * radius_max))
		patches.append([Vector2(cos(angle) * dist, sin(angle) * dist), pool[rng.randi() % pool.size()]])
	return patches


static func _patch_species(patches: Array, pos: Vector3) -> Array:
	var xz := Vector2(pos.x, pos.z)
	var best := INF
	var pick: Array = patches[0][1]
	for p in patches:
		var d := xz.distance_squared_to(p[0])
		if d < best:
			best = d
			pick = p[1]
	return pick


static func _ring_point(rng: RandomNumberGenerator, radius_min: float, radius_max: float) -> Vector3:
	var angle := rng.randf() * TAU
	var dist := rng.randf_range(radius_min, radius_max)
	return Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


## Pontos que o cenário deve deixar livres: origem do jogador e os pontos
## fixos do `WorldPopulator`.
static func _clear_spots() -> Array[Vector3]:
	return [
		Vector3.ZERO,
		WorldPopulator.PLAYER_START_SPOT,
		WorldPopulator.MERCHANT_SPOT,
		WorldPopulator.CRAFTING_BENCH_SPOT,
		WorldPopulator.RELIC_STATION_SPOT,
		WorldPopulator.ARENA_SPOT,
		WorldPopulator.PORTAL_SPOT,
	]


static func _too_close(pos: Vector3, occupied: Array[Vector3], radius: float = CLEAR_RADIUS) -> bool:
	for o in occupied:
		if pos.distance_to(o) < radius:
			return true
	return false


## Os kits aquáticos (`AQUA_KIT`/`MAR_RASO_KIT`) são temáticos de mar
## raso/recife — pedido do usuário, 2026-09-02: nenhuma peça deles pertence
## ao platô glacial (BIO-014, tem textura de gelo própria desde então) nem
## ao Mar Profundo (BIO-004). `DEFAULT_BIOME` nunca aparece aqui por ser
## fallback de dado faltando, não bioma real (ver `CLAUDE.md`) — só os dois
## códigos abaixo.
static func _is_excluded_biome(biome_code: String) -> bool:
	return biome_code == "BIO-014" or biome_code == "BIO-004"


static func _apply_pz01_ambience(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = PZ01_WATER_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = PZ01_AMBIENT
	env.ambient_light_energy = PZ01_AMBIENT_ENERGY
	env.fog_enabled = true
	env.fog_light_color = PZ01_FOG
	# Névoa de altura: densa abaixo da linha d'água, quase nada acima. O sinal
	# POSITIVO de `fog_height_density` é o que faz a névoa engrossar para
	# BAIXO da cota — invertido, a costa afogaria e o mar clarearia.
	env.fog_density = PZ01_FOG_BASE_DENSITY
	env.fog_height = PZ01_WATER_LINE
	env.fog_height_density = PZ01_FOG_UNDERWATER_DENSITY
	# AO real (SSAO), não luz achatada — era uma das lacunas visuais
	# originais do bioma (bio-002-costa-primordial.md, 3.5): sem AO, fenda
	# entre rochas e base de prop leem plano na câmera ortográfica, porque não
	# há sombra projetada de uma fonte única sustentando o volume sozinha.
	# Intensidade reduzida em 2026-09-08 (1.6 → 0.9): no elenco (CRT-001..014),
	# a força antiga escurecia demais o contato cabelo/roupa-corpo, reforçando
	# a leitura "apagada" que já vinha do ambient — mantém o volume nas
	# frestas de rocha/prop sem escurecer o personagem inteiro.
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 0.9
	env.ssao_power = 1.5
	var we := WorldEnvironment.new()
	we.name = "Ambience"
	we.environment = env
	root.add_child(we)

	# A luz já existe em `main.tscn`; aqui só recebe o banho de cor do bioma.
	# Se a cena mudar o nome do nó, o mapa fica com a luz neutra — degradação
	# silenciosa aceitável para apresentação. O CHÃO não é mais pintado aqui:
	# o `MapTerrain` é dono do material do solo, com a paleta que
	# `ground_palette` fornece.
	var key := root.get_node_or_null("KeyLight") as DirectionalLight3D
	if key:
		key.light_color = PZ01_SUN
		key.light_energy = PZ01_SUN_ENERGY
		key.shadow_enabled = true

	# O que foi escrito acima é o perfil de BIO-001; daqui em diante quem
	# mexe nesses mesmos campos, por bioma, é o `BiomeAmbience` (ver o topo
	# dele para o porquê de não ser um `Environment` por bioma).
	BiomeAmbience.create(root, env, key)

	# O banho quente do trecho seco. Omnis largas sobre a vila da costa: quem
	# sobe a rampa entra no alcance delas e "sai da água" também na luz.
	for i in PZ01_COAST_LIGHT_OFFSETS.size():
		_add_fill_light(root, "CoastFill%d" % i,
			WorldPopulator.MERCHANT_SPOT + PZ01_COAST_LIGHT_OFFSETS[i],
			PZ01_COAST_LIGHT_RANGE)
	_add_fill_light(root, "IslandFill", PZ01_ISLAND_LIGHT_SPOT, PZ01_ISLAND_LIGHT_RANGE)


## Uma omni de preenchimento sobre chão emerso. Sem sombra de propósito: é
## banho de cor, não fonte de leitura — quem desenha volume aqui é o sol.
## Sem especular pelo mesmo motivo (2026-09-02): mantém só a contribuição
## difusa do banho de cor. NÃO era a causa da bolha branca reportada no mesmo
## dia — essa hipótese (hotspot na água espelhada) foi descartada depois de
## testada; a causa real era `_flatten_specular` (ver comentário lá). Fica
## desligado mesmo assim, por ser consistente com "banho de cor, não fonte
## de leitura" e não ter custo.
static func _add_fill_light(root: Node3D, node_name: String, pos: Vector3, light_range: float) -> void:
	var fill := OmniLight3D.new()
	fill.name = node_name
	fill.position = pos
	fill.light_color = PZ01_COAST_LIGHT
	fill.light_energy = PZ01_COAST_LIGHT_ENERGY
	fill.omni_range = light_range
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	root.add_child(fill)


static func _resolve_asset(file: String) -> String:
	var alias := {
		PZ01_PLACEHOLDER_ROCK_HERO_01: "Aqua_Coral_Garden",
		PZ01_PLACEHOLDER_GLAZE_01: "Aqua_Sponge_Cluster",
	}
	var resolved: String = alias.get(file, file)
	if resolved.begins_with("res://") or resolved.contains("/") or resolved.ends_with(".glb") or resolved.ends_with(".tscn") or resolved.ends_with(".scn"):
		return resolved
	return resolved


## O kit aquático veio do Meshy com `_metallic_roughness.jpg`/`_normal.jpg`
## próprios (anterior à regra de cel-shading do `BIOME_PROPS.md`, "sem normal
## map, sem specular, sem roughness" — só o kit mais novo nasceu já seguindo
## ela). Sem isto, o `KeyLight` (única luz do mapa com sombra, energia 1.35)
## acende reflexo especular real nessas peças — visível como pontos de brilho
## alheios ao resto do cel-shading, achado em 2026-09-02 depois de a costa
## esvaziar (kit de BIO-002 removido) deixar essas peças mais expostas.
## Muta o material importado (compartilhado por todas as instâncias do mesmo
## `.glb`, via cache de recurso do Godot) em vez de duplicar por instância —
## é exatamente o efeito desejado (o kit inteiro achatado) e evita criar um
## `Material` novo por prop colocado.
##
## Sonda direta (`probe_aqua_materials.gd`, descartada depois) achou o motivo
## da primeira versão não ter resolvido: `roughness = 1.0` não fazia nada,
## porque 1,0 já É o fator default do glTF quando existe textura de
## roughness — o valor final no shader é `fator × textura`, e a textura (com
## pontos baixos = brilhante) passava direto. Faltava também zerar
## `metallic_specular` (o brilho dielétrico, 0,5 por padrão, não depende de
## `metallic`) — ele sozinho já bastava pra acender hotspot em superfície
## curva sob o sol, com `metallic` em zero ou não. Versão final limpa as
## DUAS texturas (`roughness_texture`/`metallic_texture`, senão o fator não
## tem efeito nenhum) e zera `metallic_specular` junto.
static func _flatten_specular(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is BaseMaterial3D:
					var flat := mat as BaseMaterial3D
					flat.metallic = 0.0
					flat.metallic_texture = null
					flat.metallic_specular = 0.0
					flat.roughness = 1.0
					flat.roughness_texture = null
					flat.normal_enabled = false
	for child in node.get_children():
		_flatten_specular(child)


## Multiplica a cor de base das superfícies de `node` por `color`, num material
## duplicado e compartilhado (ver `TINT` e `_tint_cache`). O material importado
## não é tocado: ele é o mesmo recurso que o uso terrestre do kit carrega.
static func _apply_tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var base := mi.get_active_material(i) as BaseMaterial3D
				if base == null:
					continue
				var key := "%d:%s" % [base.get_instance_id(), color.to_html(false)]
				if not _tint_cache.has(key):
					var tinted := base.duplicate() as BaseMaterial3D
					tinted.albedo_color = base.albedo_color * color
					_tint_cache[key] = tinted
				mi.set_surface_override_material(i, _tint_cache[key])
	for child in node.get_children():
		_apply_tint(child, color)


## Troca o material das superfícies de `node` pelo de balanço, sem tocar no
## material importado (outras instâncias da mesma peça podem estar paradas —
## hoje não estão, mas a lista `SWAY` é por nome e a regra não deve depender
## disso). Roda DEPOIS de `_flatten_specular`, e herda dele o que copiar.
##
## Superfície que não é o caso simples medido no kit (`BaseMaterial3D` opaco
## com textura) fica com o material original, parada. Balançar errado é pior
## que não balançar: uma peça transparente virando opaca, ou sem textura
## virando branca, é defeito visível; uma alga parada é só uma alga parada.
static func _apply_sway(node: Node, amount: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var base := mi.get_active_material(i) as BaseMaterial3D
				if base == null or base.albedo_texture == null:
					continue
				if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					continue
				mi.set_surface_override_material(i, _sway_material(base, mi.mesh, amount))
	for child in node.get_children():
		_apply_sway(child, amount)


## O `ShaderMaterial` de balanço equivalente a `base`, cacheado por ele.
##
## O pivô é `SINK_FRACTION` em unidade LOCAL: o prop é posto com a origem a
## `SINK_FRACTION × escala` abaixo do chão, então o chão corta a malha em
## y local = `SINK_FRACTION`, qualquer que seja a escala. A ponta é o topo da
## AABB da malha. Isso vale porque o nó de malha do kit tem transform
## identidade dentro da cena importada (medido nas 11 peças em 2026-09-17) —
## uma peça futura com o nó de malha deslocado ou escalado balançaria a partir
## do pivô errado.
static func _sway_material(base: BaseMaterial3D, mesh: Mesh, amount: float) -> ShaderMaterial:
	var key := base.get_instance_id()
	if _sway_cache.has(key):
		return _sway_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = SWAY_SHADER
	mat.set_shader_parameter("albedo_tex", base.albedo_texture)
	mat.set_shader_parameter("albedo_color", base.albedo_color)
	mat.set_shader_parameter("sway_amount", amount)
	mat.set_shader_parameter("sway_speed", SWAY_SPEED)
	mat.set_shader_parameter("sway_dir", MapTerrain.WATER_FLOW_DIR)
	mat.set_shader_parameter("sway_pivot_y", SINK_FRACTION)
	mat.set_shader_parameter("sway_top_y", mesh.get_aabb().end.y)
	_sway_cache[key] = mat
	return mat


static func _place(
	parent: Node3D,
	terrain: MapTerrain,
	file: String,
	pos: Vector3,
	yaw: float,
	prop_scale: float,
	col_radius: float,
	kit: String = AQUA_KIT
) -> void:
	var resolved := _resolve_asset(file)
	var packed: PackedScene = null
	var scene_path := resolved
	if not scene_path.begins_with("res://"):
		if scene_path.contains("/"):
			scene_path = "res://" + scene_path
		else:
			scene_path = kit + scene_path + ".glb"
	packed = load(scene_path) as PackedScene
	if packed == null:
		push_warning("MapDressing: prop ausente %s (resolved %s) — rode pnpm game:export no bestiario" % [file, scene_path])
		return
	# Apoiado no relevo, meio palmo afundado — prop de borda de colina com a
	# base 100% exposta mostraria o corte reto da malha do Meshy.
	if terrain:
		pos.y = terrain.height_at(pos) - SINK_FRACTION * prop_scale
	var node := packed.instantiate() as Node3D
	_flatten_specular(node)
	# Tinta ANTES do balanço: `_apply_sway` lê o material ativo da superfície,
	# que já é o tingido, e leva a cor para o `ShaderMaterial` dele. Na ordem
	# inversa a peça balançaria sem a tinta.
	if TINT.has(resolved):
		_apply_tint(node, TINT[resolved])
	var sway: float = SWAY.get(resolved, 0.0)
	if sway > 0.0:
		_apply_sway(node, sway)
	node.position = pos
	node.rotation.y = yaw
	node.scale = Vector3.ONE * prop_scale
	parent.add_child(node)

	# Colisão só nos landmarks maciços, como cilindro simples — o jogador e
	# as criaturas (CharacterBody3D) deslizam ao redor em vez de atravessar
	# uma rocha do próprio tamanho. Desligada por enquanto (`PZ01_PROPS_COLLIDABLE`).
	if col_radius > 0.0 and PZ01_PROPS_COLLIDABLE:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = col_radius
		cyl.height = maxf(2.0, prop_scale)
		shape.shape = cyl
		shape.position.y = cyl.height * 0.5
		body.add_child(shape)
		parent.add_child(body)
