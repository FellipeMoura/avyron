# PZ-01 — Plano de refinamento (trocar Camada A, preservar Camada B)

> Depende da leitura de [bio-002-costa-primordial.md](bio-002-costa-primordial.md)
> (o que a referência exige, e a correção de que o bioma-alvo é **BIO-002**,
> não BIO-001) e da conversa que definiu a fronteira entre as duas camadas
> do mapa:
>
> - **Camada A (visual/apresentação)** — geometria da "massa rochosa", shader
>   de cor do chão, quais assets são instanciados, água, iluminação. Não tem
>   *caller*: nada fora do que está na tela lê o interior dela. Pode ser
>   jogada fora e reconstruída livremente.
> - **Camada B (interface/dado)** — tudo que outro sistema **consome por
>   contrato**: `height_at`, `on_coast`, `on_island`, `submerged`,
>   `clamp_to_bounds`, `water_line`, os pontos fixos do `WorldPopulator`, e a
>   partição de bioma vinda do catálogo (`MapBiomes`/`biomeRegions`). Mexer
>   aqui exige atualizar quem chama, e potencialmente o bestiário.
>
> Convenção de dono de tarefa: **👤 Você** (decisão de produto/estética,
> geração e curadoria de asset 3D, veredito de "ficou bom") ou **🤖 Eu**
> (GDScript, shader, script de composição, testes headless, screenshot
> headless, edição de dado do catálogo quando for mecânica). Onde os dois
> aparecem, é ciclo de ida e volta, não tarefa dividida ao meio.

## 0. Contrato congelado — o que NÃO muda neste refinamento

Isto é a lista de aceite de toda reescrita de Camada A daqui pra frente.
Qualquer entrega que quebre um item daqui não está pronta, mesmo que a
imagem bata com a referência.

| Interface | Onde vive hoje | Quem consome |
|---|---|---|
| `MapTerrain.height_at(pos)` | `map_terrain.gd` | props, spawner, encenação de duelo, atores fixos |
| `MapTerrain.on_coast(pos, margin)` | idem | `MiningTable`, `MapDressing`, `CreatureSpawner` |
| `MapTerrain.on_island(pos, margin)` | idem | idem |
| `MapTerrain.on_glacial(pos)` | idem, desde 2026-09-01 | `on_dry_land`, `submerged` |
| `MapTerrain.on_dry_land(pos)` | idem, desde 2026-09-01 | `submerged` |
| `MapTerrain.should_float(pos)` (funda `is_deep` + inclinação) | idem, desde 2026-09-01 | `PlayerController._floating`, `CompanionActor._ground_y` (via `surface_or_ground`) |
| `MapTerrain.submerged(pos)` | idem | `PlayerController` (andar vs. nadar), névoa |
| `PlayerController._floating()` / `FLOAT_RISE_SPEED` | `player_controller.gd`, desde 2026-09-01 | física do jogador (Y quando `should_float`) |
| `CompanionActor._ground_y()` | `companion_actor.gd`, desde 2026-09-01 | Y da companheira (sem física própria) |
| `MapTerrain.clamp_to_bounds(pos)` | idem | `BattleStaging` |
| `MapTerrain.water_line` | idem, injetado por `MapDressing.water_line()` | névoa de altura, `submerged` |
| `WorldPopulator.MERCHANT_SPOT` / `RELIC_STATION_SPOT` / `CRAFTING_BENCH_SPOT` / `ARENA_SPOT` / `PORTAL_SPOT` / `PLAYER_START_SPOT` | `world_populator.gd` | `WorldRoot._ready` |
| Partição de bioma (`MapBiomes.biome_at`, `biomeRegions` normalizadas ±1) | catálogo (`avyron-bestiary`) + `map_biomes.gd` | mineração, `WorldRoot.current_biome()` |
| Rampas caminháveis (≤45°) da costa e da ilha | `map_terrain.gd`, `_coast_profile`/`_island_profile` | física do `CharacterBody3D` |
| Testes verdes: `test_data.gd`, `test_world.gd`, `test_playable.gd`, `test_merchant.gd` | `scripts/dev/` | CI manual (rodado à mão) |

**Ponto de atenção, confirmado como orçamento aprovado (seção 1):** mudar a
geografia macro (raio/posição do lobo da costa, da ilha, do bloco rochoso)
*parece* Camada A mas mexe na Camada B — as regiões do catálogo são
normalizadas sobre o meio-lado do mapa. **Só é permitido mudar VALOR** de
região já existente (raio, centro, limite) ou, se necessário, adicionar
nova linha usando uma das 3 formas que o schema já suporta
(`band`/`circle`/`rect` — um bioma já pode ter mais de uma região, é o
recurso usado por Mar Profundo hoje). Não entra campo novo, tabela nova, ou
conceito novo no catálogo só por fidelidade visual — complexidade nova lá
só se justifica por funcionalidade nova.

### 0.1 Dado de referência — partição atual de PZ-01

Levantado do `avyron-bestiary` em 2026-08-31 (`map_biome_regions`, `map_id`
do PZ-01), base para a Fase 1:

| sortOrder | biomeCode | bioma | shape | params (±1) |
|---|---|---|---|---|
| 0 | BIO-002 | Costa Primordial | rect | `x0:-0.8, x1:0.66, z0:-1, z1:-0.72` |
| 1 | BIO-002 | Costa Primordial | circle | `r:0.46, cx:-0.07, cz:-1` |
| 2 | BIO-003 | Jardins Recifais | circle | `r:0.47, cx:-0.34, cz:0` |
| 3 | BIO-014 | Plataforma Glacial | rect | `x0:-1, x1:-0.3, z0:0.72, z1:1` |
| 4 | BIO-004 | Mar Profundo | band | `axis:z, from:0.47, to:1` |
| 5 | BIO-004 | Mar Profundo | rect | `x0:0.54, x1:1, z0:-0.1, z1:1` |
| 6 | BIO-001 | Mar raso | rect | `x0:-1, x1:1, z0:-1, z1:1` (catch-all, avaliado por último) |

Resolução: primeira região que contém o ponto vence, por `sortOrder`. Mar
raso (BIO-001) não tem geometria própria — é o que sobra.

**Achado, resolvido na Fase 1 (2026-08-31):** o relevo antigo
(`map_terrain.gd`) não usava essas regiões pra desenhar nada — `REEF_CENTER
= Vector2(-12, -20)` era uma constante solta, de uma leitura de concept art
anterior a este refinamento. A correção não foi mover o recife pro
território de BIO-002 (a leitura original deste achado presumia isso): era
o rótulo do achado que estava errado — `_reef_profile` sempre foi Jardins
Recifais (BIO-003), não Costa Primordial. `REEF_CENTER` migrou pro círculo
real de `RGN-002`, `_glacial_profile` virou retângulo (era círculo) pro
`RGN-004`, e `_abyss_profile` ganhou portão em `z` pro `RGN-007` — os três
detalhados no changelog da Fase 1 abaixo.

---

## 1. Decisões de escopo — fechadas em 2026-08-31

Registro das respostas; detalhe de cada uma em
[bio-002-costa-primordial.md, seção 7](bio-002-costa-primordial.md#7-decisões-tomadas-fase-0).

- [x] **Câmera:** -30°/45°, isométrico clássico — **já aplicado** em
      `iso_camera.gd`, `main.tscn` e `test_world.gd`, testes verdes.
- [x] **Fidelidade à imagem:** o mapa é remodelado pra refletir as
      proporções do overview (`refs/pz01-overview-target.png`) até o ponto
      em que isso não exija complexidade nova no catálogo — só valor, nos
      campos que `map_biome_regions` já tem (seção 0.1).
- [x] **Fonte de asset:** Meshy AI em todos os biomas. Para BIO-002, os 9
      assets de 2026-08-30 (pasta mal-nomeada `assets_BIO-001`, conteúdo é
      de BIO-002) **são o material final**, não placeholder — entram na
      Fase 3 como estão. Para os biomas seguintes, o pipeline é protótipo
      2D via ChatGPT → conversão 3D no Meshy; escrevo o prompt do protótipo
      junto com você quando chegar a vez de cada bioma.
- [x] **Orçamento de geografia macro:** aprovado, mapa inteiro. Sequência
      combinada: **(1)** remodelar a geografia macro do mapa inteiro
      primeiro — todos os 5 biomas, sem tocar asset ainda — **(2)** aplicar
      o kit já pronto em BIO-002 **(3)** gerar o próximo bioma, e repetir.
      É essa sequência que organiza as fases abaixo.

---

## Fase 1 — Geografia macro do mapa inteiro

Antes de qualquer asset novo: alinhar o **relevo** (`map_terrain.gd`) e,
onde precisar, o **dado de partição** (`map_biome_regions`) com as
proporções do overview — para os 5 biomas, não só BIO-002.

- [x] **🤖 Eu** comparei cada região da tabela 0.1 com a posição/proporção
      que `pz01-overview-target.png` mostra, e propus ajustes de valor —
      sem criar região com forma nova além de `band`/`circle`/`rect`.
- [x] **👤 Você** aprovou a proposta (incluindo remover a `band` do Mar
      Profundo e esticar o `rect` dele).
- [x] **🤖 Eu** reautorei as regiões via API do bestiário: `RGN-001` (x1
      0.66→0.85), `RGN-004` (z0 0.72→0.22), `RGN-002` (cx -0.34→-0.4 —
      pedido original era -0.5, ajustei pra -0.4 porque -0.5 tirava a
      origem do mapa do raio do círculo e quebrava um teste real), `RGN-007`
      (x0 0.54→0.3, z0 -0.1→-0.6), `RGN-005` removida. `dataVersion`
      0.441→0.447, `pnpm game:export` rodado.
- [x] **🤖 Eu** reescrevi a shape macro do relevo em `map_terrain.gd`:
      `_reef_profile` migrou pro círculo de BIO-003 (`RGN-002`, não mais
      "concept art" solto — o nome "reef" passou a fazer sentido de novo,
      já que BIO-003 é Jardins Recifais); `_glacial_profile` virou
      retângulo com cantos suaves (era círculo, não batia com a forma real
      de `RGN-004`); `_abyss_profile` ganhou um portão em `z` pra não
      morder mais o platô seco da costa; `_coast_profile`/o shader
      ganharam um centro próprio pro retângulo (`COAST_RECT_CENTER_X`),
      separado do centro do círculo, porque só o retângulo mudou de forma.
      Dois ajustes finos, ambos rodada de teste real, nenhum mexeu em
      Camada B: `REEF_HEIGHT` caiu de 4,8 para 3,0 m (o novo centro do
      recife, mais perto da origem, estava empurrando a orla da ilha pra
      cima da linha d'água; recife nunca deveria decidir "molhado/seco"
      por altura, então isso é correção, não regressão) e a distância do
      teste "pé da rampa" em `test_world.gd` foi corrigida de 2,0 m para
      4,5 m depois do início da rampa — medido por sonda direta, a água só
      cruza a rampa perto dos 3,5 m; o valor de 2,0 m só passava antes
      porque o recife antigo (fora do lugar) alcançava até ali por acidente.
- [x] **🤖 Eu** rodei `test_data.gd`, `test_world.gd`, `test_playable.gd`,
      `test_merchant.gd` headless — 230 verificações, 0 falhas.
- [ ] **👤 Você** abre o editor e confere a silhueta macro contra o
      overview antes de eu seguir pra Fase 2 — ainda sem textura/asset
      novo, só forma e proporção.

---

## Entre Fase 1 e Fase 2 — dois pontos de física declarados

Duas pendências abertas pelo usuário depois da Fase 1, resolvidas em
2026-09-01 antes de começar a Fase 2 — as duas mexem em Camada B
(predicado geográfico novo, e a física vertical do jogador), então entram
aqui e não como "detalhe" de asset.

- [x] **👤 Você** pediu: o platô glacial (BIO-014) também devia ser terra
      firme — hoje só a costa e a ilha eram exceção à regra "fora delas é
      sempre mar", e um bioma com fauna e minério próprios (minério glacial
      exclusivo, ver `CLAUDE.md`) lendo como leito de mar contradizia o
      resto do design.
      **🤖 Eu** declarei `MapTerrain.on_glacial(pos)` — terceiro predicado de
      geografia seca, mesmo padrão de `on_coast`/`on_island` — e um funil
      único `on_dry_land(pos)` que os três compõem, usado por `submerged()`
      e (novo) por `PlayerController`. Medido por sonda direta (descartada
      depois): o núcleo do platô nunca ficava a menos de 0,25 m da cota com
      `GLACIAL_HEIGHT` em 1,5 — margem fina demais (mesma lição do recife
      nesta rodada); subiu para 1,8 m, folga de 0,55 m, mesma ordem de
      grandeza da costa. `test_world.gd` ganhou a seção "platô glacial"
      (núcleo seco, pé da rampa molhado, rampa andável) e uma das três sondas
      de "sempre molhado" precisou trocar de lugar — o ponto antigo passou a
      cair dentro do platô e virou seco por altura, não mais "sempre".
- [x] **👤 Você** pediu: é possível o jogador **flutuar** em vez de mergulhar
      em água profunda, sempre na superfície? Isso descreve um bug real, não
      só uma preferência: o Mar Profundo (`ABYSS_*`) desce 15 m, a rampa dele
      é mais íngreme que os 45° que o `CharacterBody3D` aceita como piso, e
      o jogador que caía lá dentro ficava PRESO — sem como escalar de volta
      andando.
      **🤖 Eu** dei ao `PlayerController` um modo de empuxo: fora de
      `on_dry_land`, o corpo para de seguir a colisão no eixo Y — cai
      normalmente enquanto está acima da cota (entrar na água por cima ainda
      afunda um pouco) e sobe de volta (`FLOAT_RISE_SPEED = 3,0 m/s`) assim
      que cruza abaixo dela. Continua passando por `move_and_slide` (só o Y é
      diferente), então colisão horizontal segue valendo. `test_playable.gd`
      ganhou uma fase nova: larga o corpo em queda livre sobre o Mar
      Profundo e prova que ele assenta perto da cota (medido: pés a 1,33 m,
      cota 1,25 m) em vez de no leito, 15 m abaixo.
- [x] **👤 Você** jogou e trouxe três defeitos reais na primeira versão do
      empuxo, todos corrigidos no mesmo dia: (1) o corpo ficava "quicando"
      parado, mesmo sem nadar; (2) a criatura companheira caía no Mar Profundo
      enquanto o jogador flutuava por cima; (3) ao sair da água pra terra
      seca, o corpo parava de flutuar e só então subia — um degrau visível.
      **🤖 Eu** reprojetei em torno de uma causa raiz só: o gatilho de
      flutuação era `on_dry_land` (a FORMA da costa/ilha/platô glacial), que
      cobre a rampa inteira, mas a rampa inteira já é rasa — o degrau do item
      3 era exatamente esse descompasso entre "geometria diz seco" e "leito
      ainda está fundo". Troquei o gatilho para `MapTerrain.is_deep(pos)`
      (profundidade real: mais de `SHALLOW_DEPTH` = 3 m abaixo da cota), com
      `surface_or_ground(pos)` como par pra quem só consulta altura sem
      física. Isso resolveu o item 3 de graça — a rampa nunca é funda o
      bastante pra acionar o empuxo, então o corpo sobe andando o tempo
      todo — e deu à `CompanionActor` (que só faz `global_position.y =
      height_at(...)`, sem gravidade) o mesmo tratamento, resolvendo o item
      2. O item 1 era bug à parte na física do empuxo: a velocidade de subida
      era fixa (nunca desacelerava perto da cota) e ultrapassava o alvo a
      cada quadro; a gravidade do quadro seguinte não zerava a velocidade
      herdada, só reduzia aos poucos, então o corpo continuava subindo um
      pouco além antes de cair de novo — um ciclo-limite. Uma zona morta
      (`FLOAT_DEADBAND` = 0,1 m) que zera a velocidade perto da cota, em vez
      de deixá-la oscilar entre subir e cair, resolveu. `test_playable.gd`
      ganhou uma checagem de amplitude na cauda da janela de assentamento
      (medido: 0,000 m em 30 quadros — perfeitamente parado), `test_world.gd`
      ganhou a invariante "nenhuma rampa é funda o bastante pra flutuação" nos
      três pés de rampa já medidos, e `test_companion.gd` ganhou um caso de
      companheira sobre água funda (antes: afundava até -14,96 m; depois:
      para exatamente na cota, 1,25 m).
- [x] **🤖 Eu** rodei as 16 suítes headless do projeto (não só as 4 do
      contrato congelado) — 0 falhas. Duas mexiam em predicado geográfico
      consumido amplamente (`on_dry_land`) e em física do corpo que quase
      toda suíte jogável instancia; a varredura completa foi para não deixar
      um consumidor fora das quatro suítes de referência passar despercebido.
- [x] **👤 Você** trouxe um quarto defeito, parecido com o item 3 mas na
      direção OPOSTA: entrando no Mar Profundo (não saindo dele), o corpo
      descia um pouco e só então subia — "como se a superfície do Mar
      Profundo fosse mais alta que o resto". **🤖 Eu** achei a causa: o
      gatilho da rodada 2 (`is_deep`, limiar de profundidade) tinha uma
      LACUNA — a rampa do Mar Profundo fica intransitável (inclinação >45°)
      bem ANTES de a profundidade cruzar o limiar de 3 m, e nesse intervalo o
      corpo caía de verdade, sem empuxo nenhum, até o limiar finalmente
      disparar. Troquei o gatilho pela primeira vez para `not is_on_floor()`
      (a mesma determinação de inclinação que o motor de física já calcula)
      — e isso reabriu, na hora, o bug da rodada 2 só que na direção inversa:
      um corpo momentaneamente no ar por QUALQUER motivo alheio à
      profundidade (um `y` de partida no ar, por exemplo) já conta como
      `not is_on_floor()`, e como `submerged()` é incondicional fora de
      `on_dry_land`, isso bastava para flutuar em vez de simplesmente cair
      até o leito raso comum que estava logo abaixo. `is_on_floor()` reflete
      o ESTADO do motor no quadro, não o TERRENO. A versão final,
      `MapTerrain.should_float`, junta profundidade E inclinação — as duas
      calculadas do MESMO campo de altura que gera a malha e a colisão, então
      a resposta nunca depende de quadro, velocidade ou como o corpo chegou
      ali. `CompanionActor.surface_or_ground` passou a usar a mesma função
      (antes só profundidade), unificando os dois consumidores.
      `test_playable.gd` ganhou uma travessia A PÉ (não em queda livre) até o
      Mar Profundo — assenta no chão raso primeiro, anda de verdade pela
      rampa, e prova que o ponto mais fundo alcançado depois de perder o
      chão nunca fica abaixo do último ponto em que ainda tinha chão (medido:
      perdeu o chão em y=0,59, mínimo depois disso foi y=0,64 — subiu na
      hora, sem afundar primeiro). As 16 suítes voltaram a passar.

---

## Fase 2 — BIO-002 (Costa Primordial): aplicar o kit já pronto

Só começa depois da Fase 1 fechada — sem isso, o kit seria posicionado
sobre uma geografia que ainda vai mudar de forma.

- [x] **🤖 Eu** renomeei a pasta `models/biomes/assets_BIO-001/` →
      `assets_BIO-002/` (aqui e a fonte equivalente no `avyron-bestiary`) e
      atualizei as referências em `map_dressing.gd` (`BIO001_KIT` →
      `BIO002_KIT`, 8 landmarks) — mecânico, corrige o nome errado registrado
      na seção 5 do doc de BIO-002. Pasta continua fora do git em ambos os
      repos (nunca foi commitada), mesmo estado de antes.
- [x] **👤+🤖** achamos e resolvemos uma peça faltando antes de escrever o
      povoador: o `avyron-bestiary/docs/BIOME_PROPS.md` (documento
      autoritativo, desconhecia as 9 peças de `assets_BIO-001`) pede 4 papéis
      pra Costa Primordial — poça de maré, rocha molhada, banco de lama/areia,
      esteira algal/estromatólito. As 8 peças existentes cobrem os 3
      primeiros por reinterpretação (`Oasis_Pool`, o grupo de rochas,
      `Cracked_Earth`); nenhuma cobria o 4º. Você gerou o protótipo 2D e o
      Meshy converteu (`Mossbound_Stone_Isles`). Processado antes de integrar
      (nenhum script do projeto fazia isto automaticamente — `models:optimize`
      e `models:biomes` só mexem em textura):
      - origem recentrada da base do volume pra base real (estava enterrando
        metade da peça — bug real, não estilo);
      - 1.590 → 924 triângulos (piso real de simplificação automática, achado
        por teste com `error` de 0,02 até 1,0 — a malha tem costuras de UV
        internas que o `meshoptimizer` trava por segurança; 500 exigiria
        edição manual de costura, não vale pra uma peça de scatter);
      - textura 2048² → 256².
      Registrada em `assets_BIO-002/Mossbound_Stone_Isles.glb` (espelhada no
      `avyron-bestiary`) e no `PZ01_COAST_SCATTER_POOL` de `map_dressing.gd`,
      porte 0,8–1,5. 6 suítes headless relevantes rodadas, 0 falhas, nenhum
      aviso de asset ausente.
- [x] **🤖 Eu** reconsiderei o povoador de densidade em vez de escrevê-lo do
      zero: "kit-bash denso, sem chão liso visível" (3.2) descreve o
      arquipélago de colunas basálticas da referência original, mas o
      `BIOME_PROPS.md` — que você já tratou como autoritativo no item
      anterior — pede o OPOSTO pra Costa Primordial: densidade ×0,15, "adro
      da vila", deliberadamente vazio pra não esconder comerciante/posto/
      portal. Como a decisão de manter as 8 peças genéricas (não regenerar
      um kit de colunas) já era, na prática, abandonar a leitura de
      arquipélago denso, escrever um sistema de kit-bash pra essa visão
      ficaria resolvendo o problema errado. O sistema de landmark+scatter que
      já existe (8 landmarks + até 26 no scatter da faixa costeira, mais a
      peça nova) já cobre a função — "povoar a costa com props" —, e o
      `CLEAR_RADIUS`/`_clear_spots()` já protege os pontos de serviço
      independente da contagem. Não reduzi a densidade existente sem
      confirmação visual seria destruir posição ajustada à mão sem
      justificativa clara — fica pra você apontar se ler denso demais depois
      de ver no editor.
- [x] **🤖 Eu** escrevi o plano de água dedicado — não existia em NENHUMA
      forma até aqui. `MapTerrain.build_water_mesh()` gera um único plano
      (`PlaneMesh`, sem colisão) na cota do bioma, com
      `shaders/terrain_water.gdshader` lendo profundidade da MESMA grade de
      altura do relevo (bake num `heightmap_tex` de um canal) — não de
      depth-buffer de tela, que não se dá bem com câmera ortográfica. Cor por
      profundidade (rasa clara → funda escura, satura em 8 m), espuma onde a
      profundidade se aproxima de zero, ondulação vertical leve só de
      leitura. Chamado por `WorldRoot` logo depois de injetar `water_line`.
- [x] **🤖 Eu** ajustei AO/iluminação (3.5): SSAO ligado no `Environment` do
      PZ-01 — a lacuna original era luz ambiente achatada, sem volume nas
      fendas entre rocha e base de prop. Não mexi na luz direcional/ambiente
      em si, só acrescentei o SSAO; qualquer retuning de brilho é julgamento
      visual que fica pra depois de ver.
- [x] **🤖 Eu** removi o placeholder `pz01_reef_hero_01.tscn` — achei, ao
      verificar minha própria mudança com stderr visível (as rodadas
      anteriores usavam `2>$null` e escondiam isso), que o arquivo **nunca
      carregou nesta versão do Godot**: `Color(r,g,b)` de 3 argumentos dentro
      de `sub_resource`, que o parser 4.7.1 rejeita (`Expected 4 arguments`).
      O fallback de `_place` também falhava (caminho reconstruído saía
      malformado), então esse landmark nunca existiu de verdade em jogo —
      sempre foi `push_warning` e nada instanciado. Removidos: o arquivo, a
      constante `PZ01_REEF_HERO_SCENE`, o alias, e a linha do landmark morto
      em `PZ01_LANDMARKS`.
- [x] **🤖 Eu** achei e corrigi, na mesma verificação, dois casos de um bug
      pré-existente (não causado por esta rodada — a ordem de tentativa já
      era assim antes da troca de pasta): `_place()` tentava resolver TODO
      nome nu pelo kit de BIO-002 primeiro, mesmo peças claramente do kit
      aquático — cada uma disparava um erro real de "Resource file not
      found" no log antes de acertar no fallback. `_place` ganhou um
      parâmetro `primary_kit` (default `AQUA_KIT`), e os dois call sites que
      usam nomes de BIO-002 (`PZ01_COAST_LANDMARKS`, e o scatter geral
      quando `_pool_for_pos` devolve a pool da costa pela margem mais larga
      dela) passam a indicar isso explicitamente. Log de carga de cena foi
      de ~120 linhas de erro pra zero.
- [x] **🤖 Eu** rodei as 16 suítes headless com stderr visível (não
      `2>$null` — foi assim que os dois achados acima apareceram) — 0
      falhas, 0 erros no log. Screenshot headless não funciona neste
      ambiente (`--headless` do Godot não expõe framebuffer real; travou
      tentando capturar textura nula, já registrado na rodada de física
      anterior) — verificação ficou pela suíte + inspeção direta dos
      arquivos processados.
- [ ] **Deixado pra depois, não bloqueante**: o shader triplanar de
      rocha+musgo pro chão residual (3.4). As texturas que existem
      (`assets_BIO-002/*_base_color.jpg`) são fotos de props individuais,
      2048², nunca preparadas pra tilar — escolher uma e avaliar se ela lê
      bem repetida por um shader triplanar é julgamento visual que eu não
      faço às cegas, ao contrário da água (que eu pude verificar
      estruturalmente sem depender de olhar o resultado).

---

## Kit de colunas basálticas — a lacuna real, achada depois de jogar

Você jogou, tirou um print e comparou com `bio-002-target.png`: o chão
continua liso e pintado por baixo de props espalhados, longe do arquipélago
de colunas da referência. Diagnóstico: as 8 peças de `assets_BIO-002` são
rocha AVULSA, não colunas modulares desenhadas pra encaixar e formar
terreno — nenhuma densidade de instanciamento fecha isso, é peça errada pra
função, não parâmetro errado.

- [x] **👤 Você** decidiu: não é pré-requisito ilhas cercadas de água — o
      alvo é o CHÃO coberto só por elementos da referência, mesmo que isso
      signifique tirar a água da costa por completo. Isso simplificou a
      máscara (área inteira de `on_coast`, sem recortar "ilha vs. mar
      aberto").
- [x] **🤖 Eu** escrevi 3 prompts isolados (protótipo 2D pro ChatGPT, depois
      Meshy): coluna basáltica base, variante com crosta de alga (reenquadrei
      "musgo" da referência pra não violar a regra da era — cianobactéria
      incrustada, não planta), e o atol/piscina de maré.
- [x] **👤 Você** gerou os três protótipos e converteu no Meshy — saíram
      como `Basalt_Sentinel` (coluna única com alga), `Fractured_Basalt_Column`
      (feixe de sub-colunas, mais largo — leitura melhor que uma coluna
      simples pra tilar), `Stone_Ring_Pool` (atol).
- [x] **🤖 Eu** processei os três (mesmo tratamento da estromatólito, mais
      um problema novo): origem recentrada pra base, textura 2048²→512²
      (mais rica que o tier scatter — reaproveitada por centenas de
      instâncias via UM material só, então o custo não multiplica por
      instância), decimação até o piso real de cada malha (Sentinel
      942→500, Ring Pool 880→500, Column 868→828 — o mesmo teto de costura
      de UV da estromatólito). A `Basalt_Sentinel` veio com mapa normal e
      metallic/roughness — removidos, a regra de cel-shading é só base color.
- [x] **🤖 Eu** escrevi o preenchimento denso (`PZ01_COLUMN_POOL`,
      `PZ01_COLUMN_COUNT = 260`): reaproveita o sistema de scatter existente
      em vez de um `MultiMesh` novo — decisão explícita de menor risco,
      trocando colisão individual por instância (inviável em 260+ peças sem
      reescrever o sistema de props inteiro) por colunas sem colisão,
      apoiadas visualmente no platô da costa que já é andável por baixo.
      **Bug achado e corrigido no caminho**: a primeira versão testava contra
      `occupied` (todos os landmarks/scatter já colocados) com o raio padrão
      de exclusão (3,5 m) — ~38 props já espalhados pela faixa, cada um
      "comendo" 3,5 m ao redor, cobriam quase toda a área disponível e só 2
      das 260 colunas pedidas entravam. Corrigido pra testar só contra
      `clear_spots` (pontos de serviço) com o raio cheio, e contra as
      OUTRAS colunas com uma separação bem mais apertada (1,1 m) — confirmado
      por print direto no loop: 260 de 260 colocadas, com folga (só 480 de um
      teto de 3.900 tentativas — dá pra ir mais denso ainda se a densidade
      atual não bastar).
      O atol entrou como landmark único, longe de serviço e das outras
      landmarks (>11 m).
- [x] **🤖 Eu** rodei as 16 suítes headless (stderr visível) — 0 falhas, 0
      erros no log. Achei e corrigi no caminho: os `.glb` novos precisaram de
      um `--headless --editor --quit-after 40` pra gerar o cache de import
      (mesmo motivo do `class_name` novo documentado no `CLAUDE.md`, só que
      pra recurso em vez de script) — sem isso, `load()` falhava com "No
      loader found".

---

- [x] **👤 Você** abriu o editor, jogou, e deu o veredito: o kit de BIO-002
      (as 8 peças Meshy originais + `Mossbound_Stone_Isles` + o preenchimento
      denso `PZ01_ROCK_FILL_POOL`) não bateu com a referência — mesmo
      diagnóstico da "segunda tentativa" registrada acima, agora estendido ao
      kit inteiro, não só ao preenchimento.
- [x] **🤖 Eu** removi tudo isso em 2026-09-02: a pasta
      `models/biomes/assets_BIO-002/` (e a fonte espelhada em
      `avyron-bestiary/apps/web/public/models/biomes/assets_BIO-002/`, nenhuma
      das duas cópias chegou a ser commitada) e todo consumo em
      `map_dressing.gd` — `BIO002_KIT`, `PZ01_COAST_LANDMARKS`,
      `PZ01_COAST_SCATTER_POOL`, `PZ01_ROCK_FILL_POOL/COUNT/MIN_SEP`, o
      parâmetro `primary_kit`/fallback de `_place`, e o ramo de `_pool_for_pos`
      que devolvia a pool da costa. A costa (`on_coast`) volta a ficar sem
      prop nenhum — mesmo estado de antes da Fase 2, só o kit aquático
      (`AQUA_KIT`) continua em uso no resto do mapa. 16 suítes headless
      rodadas depois da remoção, 0 falhas, sem aviso de asset ausente no
      log.
- [ ] Próximo kit de BIO-002 (se/quando for gerado de novo) entra do zero,
      não reaproveitando estas peças — ver `BIOME_PROPS.md` no bestiário para
      o pedido de conteúdo já registrado (poça de maré, rocha molhada,
      banco de lama/areia, esteira algal).
- [x] **👤 Você** apontou, no print pós-remoção, 3 reflexos de luz perto da
      ilha/costa — brilho especular real, não cel-shading, em peças do kit
      **aquático** (`Terraced_Stone_Mounds` e um coral em cristal ao lado, na
      posição do print). Causa: o kit aquático é anterior à regra "sem normal
      map, sem specular, sem roughness" de `BIOME_PROPS.md` §5 — veio do
      Meshy com `_metallic_roughness.jpg`/`_normal.jpg` próprios, e o
      `KeyLight` (única luz do mapa com sombra, energia 1,35) reflete neles de
      verdade. Não é regressão desta sessão — só ficou mais exposto com a
      costa vazia.
      **🤖 Eu** escrevi `MapDressing._flatten_specular`, chamada em `_place`
      pra toda peça posta no mapa: zera `metallic`, satura `roughness` em 1,0
      e desliga `normal_enabled` no material ativo de cada `MeshInstance3D`.
      Muta o material IMPORTADO (compartilhado pelo cache de recurso do
      Godot entre todas as instâncias do mesmo `.glb`), não duplica por
      prop — é o efeito certo (kit inteiro achatado) sem criar um `Material`
      novo a cada posicionamento. Achado no caminho: a primeira versão
      duplicava o material por instância (`.duplicate()`) e isso disparava
      `ERROR: Parameter "material" is null` do renderer dummy ao sair do
      processo headless (`test_playable.gd`) — sumiu ao trocar pra mutação
      direta do recurso compartilhado. 16 suítes headless rodadas depois,
      0 falhas.
- [x] **👤 Você** conferiu no editor e trouxe um segundo print: uma bolha
      branca estourada, redonda, flutuando sobre a água — visualmente
      diferente dos 3 reflexos em peça de cima. **🤖 Eu** propus uma primeira
      hipótese (as luzes de preenchimento `CoastFill0/1`/`IslandFill`
      refletindo na água espelhada) e apliquei `light_specular = 0.0` nelas —
      **errada**: você confirmou que a bolha continuava depois. Descartada.
      A causa real, achada com sonda direta (`probe_aqua_materials.gd`,
      descartada depois) em vez de nova suposição: o item anterior
      (`_flatten_specular`) não tinha resolvido nada de verdade.
      `roughness = 1.0` é o FATOR default do glTF quando existe textura de
      roughness — o valor final no shader é `fator × textura`, e a textura
      (com pontos baixos = brilhante) passava direto sem o fator mudar nada.
      Faltava também `metallic_specular` (o brilho dielétrico, 0,5 por
      padrão, independente de `metallic`) — sozinho já bastava pra acender
      hotspot em superfície curva sob o `KeyLight`. Corrigido de verdade:
      `_flatten_specular` agora limpa `roughness_texture`/`metallic_texture`
      (sem isso o fator não pega) e zera `metallic_specular` junto. Sonda
      confirmou os quatro valores efetivos (não só o fator) zerados nas 11
      peças depois da correção. 16 suítes headless rodadas, 0 falhas.
      `light_specular = 0.0` nas luzes de preenchimento ficou mesmo assim —
      não era a causa, mas é consistente com "banho de cor, não fonte de
      leitura" e não custa nada.

---

## Fase 3 — Próximo bioma (repete por bioma: BIO-003, BIO-004, BIO-014)

Mesmo padrão da Fase 2, mas sem kit pronto — precisa gerar antes.

- [ ] **👤 + 🤖** escrevemos juntos o prompt do protótipo 2D (ChatGPT) para
      o bioma da vez, a partir da leitura do trecho correspondente no
      overview e da régua de material já validada em BIO-002 (mesma
      família visual: rocha/água/musgo, ajustada pro bioma).
- [ ] **👤 Você** gera o protótipo, avalia, gera o kit 3D no Meshy a partir
      dele, e exporta pro `avyron-bestiary`.
- [ ] **🤖 Eu** rodo `pnpm game:export`, confiro o espelhamento em
      `models/biomes/`, e repito os passos de integração da Fase 2
      (povoador de densidade, shader, verificação) para este bioma.

---

## Relevo — de contínuo pra dois níveis fixos (2026-09-01)

Depois de ver o resultado das colunas em jogo (denso, mas ainda distante da
referência) e comparar com uma imagem de qualidade-alvo, a decisão foi
recalibrar a ambição em vez de insistir no relevo contínuo: **`MapTerrain`
inteiro virou só dois níveis fixos** — `SEA_HEIGHT` (mar) e `LAND_HEIGHT`
(terra firme), sem ruído, sem colina, sem recife nem Mar Profundo com
profundidade própria.

- [x] **👤 Você** decidiu: sacrificar a leitura de profundidade que o relevo
      contínuo dava, em troca de um gráfico mais controlado. Transição entre
      os dois níveis só em **pontos de acesso específicos** (não rampa
      contínua em toda borda) — 2 na costa, 2 no platô glacial, 1 na ilha da
      arena, posições a meu critério.
- [x] **🤖 Eu** reescrevi `MapTerrain`: removidas as constantes de ruído
      (`FLAT_RADIUS`/`HILL_HEIGHT`/`TERRAIN_SEED`) e as três feições de bioma
      com relevo próprio (`REEF_*`, `ABYSS_*`, a altura própria de
      `GLACIAL_*`/`ISLAND_*`/`COAST_*`) — todas viram só `SEA_HEIGHT`/
      `LAND_HEIGHT`. O Mar Profundo, especificamente, era a origem do bug que
      abriu esta sessão inteira (poço sem saída) — não existe mais como
      feição de relevo, só como partição de bioma (mineração/scatter
      continuam vendo BIO-004 normalmente).
- [x] **🤖 Eu** implementei os 5 pontos de acesso (`ACCESS_RAMPS`) como
      rampa própria, NÃO reaproveitando o esmaecimento da forma da
      costa/ilha/glacial — essa foi a primeira tentativa, e saiu íngreme
      demais: aquele esmaecimento (5–10 m) foi calibrado pra uma diferença de
      altura de ~1,6–1,8 m, não para os 6,6 m entre `SEA_HEIGHT` e
      `LAND_HEIGHT` de hoje. Medido por sonda direta
      (`probe_access_ramps.gd`, descartada): a primeira versão caía >3 m em
      2 m de vão (quase 60°). A versão final tem vão próprio
      (`ACCESS_RAMP_INNER`/`OUTER`, 12 m), calibrado pra ≤45° contra a
      diferença cheia.
- [x] **🤖 Eu** achei e corrigi, testando, um bug de consistência real:
      `on_dry_land` (que `submerged`/`should_float` consultam) não sabia dos
      pontos de acesso — o relevo já levantava o chão até `LAND_HEIGHT` ali,
      mas a geografia continuava dizendo "não é terra firme", e o jogador
      ficava em pé em chão sólido que o próprio jogo insistia em tratar como
      flutuável. Corrigido incluindo `_access_ramp_profile` em `on_dry_land`.
      Mesma classe de bug que a saga de `should_float` inteira já tinha
      ensinado — geografia e altura precisam concordar.
- [x] **🤖 Eu** simplifiquei a física de flutuação de volta pra
      `not on_dry_land(pos)` — a primeira versão (2026-09-01, antes do corte
      pra dois níveis) usava exatamente essa fórmula e foi abandonada por
      bug real, mas a causa daquele bug (relevo contínuo criando pontos
      "fora da terra firme, mas ainda rasos") deixou de existir. `is_deep`,
      `SHALLOW_DEPTH`, `MAX_WALKABLE_SLOPE` e `SLOPE_SAMPLE` — toda a
      maquinaria de profundidade+inclinação da rodada anterior — saíram por
      não terem mais função.
- [x] **🤖 Eu** reescrevi `test_world.gd` (a seção "linha d'água" inteira) e
      `test_playable.gd`/`test_companion.gd` (as partes que dependiam do
      relevo contínuo) pra verificar os NOVOS invariantes de verdade — parede
      fora dos pontos de acesso, rampa andável dentro deles, os três núcleos
      de terra firme em `LAND_HEIGHT` exato — em vez de só ajustar o texto
      pra passar. `test_playable.gd` ganhou uma travessia a nado de ponta a
      ponta até o ponto de acesso da ilha, provando o mecanismo por física
      real, não só pela conta analítica de inclinação.
- [x] **🤖 Eu** rodei as 16 suítes headless — 0 falhas.

---
- [ ] Repete para o próximo até fechar os 5 biomas do PZ-01.

---

## Corte de 90% da Costa Primordial (2026-09-17)

Fora da sequência de fases acima — pedido do usuário, não parte do
refinamento visual: encolher BIO-002 em 90% e empurrar os NPCs (vila da
costa) para o que restar dela, distribuindo o espaço liberado para os
biomas vizinhos.

- [x] **👤 Você** decidiu, via pergunta direta: o espaço liberado pode virar
      Mar Raso (BIO-001, catch-all) em vez de eu redistribuir manualmente
      entre Recife/Platô Glacial/Mar Profundo — nenhum dos três tem
      geometria que alcance essa faixa perto da borda -Z de qualquer forma.
      E aceitar ~89% de corte (não 90% cravado) para não apertar o
      espaçamento da vila (`_VILLAGE_SPACING`, `PLAYER_START_SPOT`).
- [x] **🤖 Eu** reautorei `RGN-001`/`RGN-006` via API do bestiário para um
      retângulo justo em volta da vila (`_VILLAGE_ANCHOR` e derivados, que já
      nasciam dentro dele sem precisar mover) e um círculo pequeno contido
      nele — `dataVersion` 0.604→0.607, `pnpm game:export` rodado. Mirrorei
      os mesmos valores em `map_terrain.gd` (`COAST_CENTER_X`,
      `COAST_LOBE_R`, `COAST_RECT_*`) e corrigi `COAST_RAMP_START` (que
      assumia o círculo sempre vencendo o alcance máximo — deixou de ser
      verdade com o círculo encolhido).
- [x] **🤖 Eu** medi contra `test_biome_dressing.gd` antes de declarar pronto
      e achei que a primeira tentativa (retângulo de ~13 m de meia-largura,
      ~87,5% de corte) quebrava dois invariantes que a folga de
      `CLEAR_RADIUS` sozinha não cobria: a largura livre de rampa
      (`half_w - COAST_RAMP_WIDTH`) precisa caber o gradiente úmido/seco
      (`PZ01_COAST_WET_WIDTH` = 7 m) e ficar acima de `COAST_RAMP_WIDTH · 2`
      (12 m) para o platô nunca ler como "beira d'água". Larguei o corte
      para ~72,5% (retângulo de 44 × 26,5 m, `COAST_RECT_HALF_W` = 22 m) —
      o mínimo medido que respeita os dois, em vez dos ~89% aprovados. Não
      cravei mais fundo porque o resto do orçamento (matacões, seixos,
      scatter geral) já fechava neste tamanho sem precisar reduzir
      contagem nenhuma.
- [x] **🤖 Eu** ajustei um teto fixo (`range(1, 21)`) em
      `test_biome_dressing.gd` para um teto derivado da geometria
      (`COAST_RECT_HALF_W - COAST_RAMP_WIDTH - EDGE_NOISE_AMPLITUDE`): acima
      dele a célula não-platô mais próxima na linha de centro deixa de ser a
      rampa e passa a ser a borda LATERAL do retângulo, e a distância parar
      de crescer com `k` é geometria correta, não regressão — só ficou
      invisível enquanto a costa era larga o bastante para nunca bater nesse
      teto dentro dos 20 m testados.
- [x] **🤖 Eu** rodei as 17 suítes headless (stderr visível) — 0 falhas,
      incluindo as que tocam a vila (`test_merchant`, `test_staging`) e a
      partição de bioma (`test_data`).
- [ ] **👤 Você**: se ~72,5% de corte (em vez dos ~90% originais) não servir,
      as alavancas que sobraram são: comprimir `_VILLAGE_SPACING`/o offset do
      `PLAYER_START_SPOT` (encolhe a vila em si, não só o retalho ao redor
      dela), ou reduzir `COAST_RAMP_WIDTH`/reescrever `coast_inland_at` — os
      dois fora do escopo de um corte de proporção, avaliar com calma se
      vier a valer a pena.

---

## Cantos arredondados + irregularidade de borda (2026-09-18)

Pedido do usuário: a costa e o platô glacial liam "quadrados" — arredondar a
forma e acrescentar irregularidade na borda dos dois.

- [x] **🤖 Eu** troquei a construção por eixo (`band * side` na costa, `fx *
      fz` no glacial — cada uma desenhava uma faixa 1D por eixo e só
      ANTI-ALIASAVA o canto onde elas se cruzavam, nunca arredondava de
      verdade) por um SDF de retângulo com canto arredondado
      (`_rounded_rect_sdf`, técnica padrão de Inigo Quilez) — `COAST_CORNER_RADIUS`
      = 8 m, `GLACIAL_CORNER_RADIUS` = 15 m.
- [x] **🤖 Eu** achei, rodando `test_biome_dressing.gd` (quebrou já na
      primeira amostra), um bug real na primeira versão: um SDF de retângulo
      pede bordas simétricas nos dois lados de cada eixo, mas a costa (e o
      glacial) só têm fronteira de UM lado — o outro sempre foi aberto
      (mar/rim, sem limite). Espelhar isso ingenuamente fechava um canto
      exatamente na borda visível do mapa, e a costa "acabava" no primeiro
      metro. `_OFFSCREEN_PAD` (50 m) empurra o lado que não importa bem além
      da malha antes de calcular centro/meia-largura, sem tocar no lado que
      de fato desenha a fronteira real.
- [x] **🤖 Eu** dei à costa e ao platô glacial uma amplitude de `_warp`
      PRÓPRIA, maior que a da ilha (`EDGE_NOISE_AMPLITUDE` = 2 m, calibrada
      pro raio pequeno da ilha e mantida como padrão só pra ela) — costa
      4 m + uma segunda oitava mais fina de 1,5 m, glacial 5 m + 2 m. A
      oitava fina reaproveita o mesmo `FastNoiseLite` amostrado numa escala
      maior (~7×) em vez de um segundo recurso, deslocada em domínio pra não
      repetir a quebra da oitava larga no mesmo lugar.
- [x] **🤖 Eu** troquei a costa (`terrain_ground.gdshader`) de 6 uniforms
      recalculados em GLSL (`coast_center_x`/`coast_lobe_r`/`coast_rect_*`)
      para uma máscara BAKEADA (`coast_mask_tex`), mesma técnica que
      `glacial_mask_tex` já usava — reproduzir o SDF arredondado E as duas
      oitavas de ruído em GLSL duplicaria a geometria em dois lugares, e o
      shader antigo dependia de um gate (`coast_lobe_r > 0.0`) que já tinha
      causado um susto na rodada do corte de 90%. Ganho colateral: o gate
      sai de vez, a máscara nunca pode ficar "desligada por engano".
- [x] **🤖 Eu** rodei as 19 suítes headless (stderr visível) — 0 falhas,
      depois do fix do `_OFFSCREEN_PAD`.
- [x] **👤 Você** abriu o editor: a costa ficou perfeita. O platô glacial
      não — uma pequena ilha quase encostada, com o platô contornando ela.

---

## Ilha órfã do platô glacial + lobo (2026-09-18, mesmo dia)

- [x] **🤖 Eu** achei a causa raiz por sonda direta (`probe_glacial_island.gd`,
      descartada): não era o arredondamento em si. `ACCESS_RAMPS[1]`
      (-58,33, 23,33, a rampa da borda SUL do platô) sempre esteve DENTRO do
      círculo do recife (`RGN-002`) — `biome_at` sempre respondeu BIO-003
      ali, e o filtro de `_glacial_profile` (evita geografia/bioma
      discordarem) sempre zerou o platô nesse ponto exato, mesmo antes de
      qualquer mudança desta sessão. O que mudou foi o vão: o platô "cru" de
      antes chegava perto o bastante da rampa pra ler como reentrância; o
      corte de área e o arredondamento abriram espaço suficiente pra o
      círculo PRÓPRIO da rampa (`_access_ramp_profile`, independente da forma
      do platô) sobrar isolado, "quase encostado".
- [x] **🤖 Eu** reautorei `ACCESS_RAMPS[1]` para (-80, 23) — mesma margem de
      ~4 m da borda que o ponto original tinha, só numa coluna fora do
      alcance do recife (distância ao centro dele ≥ 50 m contra um raio de
      41 m). Mecânico: Camera A, não toca no catálogo (`ACCESS_RAMPS` não
      está na tabela de interface congelada).
- [x] **🤖 Eu** dei ao platô glacial um LOBO (`GLACIAL_LOBE_R` = 95 m,
      círculo no canto do mapa `(GLACIAL_X0, GLACIAL_Z1)`, unido ao
      retângulo por `maxf` — mesma construção de `_coast_profile`), pedido
      explícito do usuário ("modifique o formato dela para algo similar à
      costa"). Maior que a largura E a altura do retângulo, pra criar uma
      barriga que passa das bordas retas dele.
- [x] **🤖 Eu** verifiquei por sonda que o lobo (mesmo maior que a diagonal
      do retângulo até o canto visível) não reabre conflito com o recife em
      nenhum ponto amostrado — a lente de sobreposição dos dois círculos cai
      fora da área que qualquer sistema de jogo consulta.
- [x] **🤖 Eu** rodei as 19 suítes headless (stderr visível) — 0 falhas.
- [x] **👤 Você** confirmou a ilha órfã resolvida e trouxe um print: o
      arredondamento leu bem (curva de verdade, sem ângulo de 90°), mas a
      irregularidade da borda estava fraca — o contorno lia como uma curva
      quase lisa contra a água, a serrilhada visível vinha só da textura do
      gelo (blocos hexagonais facetados), não da FORMA do platô.
- [x] **🤖 Eu** subi `GLACIAL_EDGE_NOISE_AMPLITUDE`/`_FINE` de 5/2 para
      11/5 — mais que o dobro do deslocamento combinado (7 m → 16 m). Como
      o platô usa degrau reto (`other_hard` em `_land_profile`, sem
      esmaecimento na altura), o warp maior se traduz direto em quanto a
      borda desvia, sem precisar mexer em `GLACIAL_FEATHER`/corner
      radius/lobo.
- [x] **🤖 Eu** rodei as 19 suítes headless de novo (o ponto de acesso
      reautorado, `test_world.gd`, é o mais sensível a isto) — 0 falhas.
- [ ] **👤 Você**: novo print pra confirmar se 11/5 quebra o contorno o
      bastante, ou se precisa subir mais.

---

## Bordas do platô glacial virando rampa, como a costa (2026-09-18)

Pedido do usuário: em vez de degrau reto (andável só nos dois pontos de
`ACCESS_RAMPS`), a borda inteira do platô glacial vira rampa andável — o
mesmo tratamento que a costa já tinha.

- [x] **🤖 Eu** parei de "endurecer" `_glacial_profile` em `_land_profile`
      (o `other_hard` que arredondava pra 0/1 antes de levantar a altura) —
      o glacial passou a entrar direto, como a costa. A ILHA continua
      hardenada (pedido original de 2026-09-01, não incluído neste pedido).
- [x] **🤖 Eu** removi os dois pontos do platô glacial de `ACCESS_RAMPS`
      (inclusive o (-80, 23) reautorado horas antes) — perderam a função
      agora que a borda inteira já é andável. Só o ponto da ilha ficou.
- [x] **🤖 Eu** não precisei mexer em `GLACIAL_FEATHER` (10 m): pela mesma
      conta de inclinação do `COAST_RAMP_WIDTH` (`1,5 · diferença / vão`,
      diferença de 2,0 m entre os níveis), 10 m de vão já dá folga maior
      ainda que os 6 m da costa.
- [x] **🤖 Eu** rodei as 19 suítes headless — 0 falhas (`test_world.gd` foi
      de 53 para 51 verificações, esperado: dois checks por ponto de
      `ACCESS_RAMPS` que não existem mais, não uma regressão).
- [ ] **👤 Você**: confirmar no editor que a borda inteira do platô lê como
      rampa (não parede) fora do miolo.

---

## Rampa do platô ainda parede — causa raiz era o filtro do recife (2026-09-18)

Você voltou de uma sessão anterior reportando exatamente o item em aberto
acima: a borda do platô continuava parede, sem rampa.

- [x] **🤖 Eu** achei a causa por sonda (`probe_glacial_ramp.gd`, descartada):
      o filtro que zera `_glacial_profile` onde `biome_at` não é BIO-014
      (escrito em 2026-09-02, antes do arredondamento/lobo/warp existirem)
      apagava TUDO que a forma orgânica desenha fora do retângulo reto do
      catálogo — exatamente onde a rampa, o lobo e o warp têm de existir.
      Resultado medido: 2 m de queda em 2 m de distância bem na borda reta
      (x=-27→h=1,60, x=-25→h=-0,40) — parede, não rampa.
- [x] **🤖 Eu** estreitei o filtro pra só zerar onde o RECIFE (BIO-003)
      realmente reivindica o ponto (`biome_at == "BIO-003"`, não
      `!= "BIO-014"`) — fora do retângulo e fora do recife cai no catch-all
      Mar Raso, sem concorrência nenhuma pra justificar zerar.
- [x] **🤖 Eu** confirmei por sonda: a mesma travessia agora desce suave de
      1,60 a -0,28 ao longo de ~7 m.
- [x] **🤖 Eu** rodei as suítes relevantes (dados, mundo, ambientação,
      equipamento, staging) — 0 falhas.

---

## Platô glacial encolhido ao tamanho da costa e replicado dela (2026-09-18)

Pedido do usuário: reduzir a área do platô ao mesmo tamanho da costa,
transformar o território liberado nos biomas vizinhos, e replicar a
geometria da costa no platô — os dois idênticos exceto assets/NPCs/texturas.

- [x] **🤖 Eu** encolhi e movi `RGN-004` via API do bestiário (`PATCH
      /map-biome-regions/RGN-004`): de um retângulo de canto (-X/+Z, ~13,65%
      do mapa) para uma banda na borda +Z espelhando `RGN-001` (44 m × 26,5
      m, mesmo tamanho da costa, centro espelhado em x). Criei `RGN-008`
      (círculo, `POST /map-biome-regions`) espelhando `RGN-006`, mesma dupla
      retângulo+círculo que a costa usa. `pnpm game:export` rodado
      (dataVersion 0.611). O território liberado não precisou de região
      nova: cai em `RGN-002` (recife) ou no catch-all `RGN-003` (Mar Raso)
      pela própria ordem de avaliação — confirmado sem sobreposição nova com
      o recife (distância mínima 0,70 contra raio 0,47, normalizado).
- [x] **🤖 Eu** reescrevi a geometria em `map_terrain.gd`: extraí
      `_edge_band_profile` (retângulo arredondado + lobo + warp de duas
      oitavas) como núcleo ÚNICO usado por `_coast_profile` e
      `_glacial_profile` — antes cada bioma tinha a própria cópia da fórmula
      e foi assim que o platô acumulou constantes de warp/canto próprias
      (11/5, 15 m) sem decisão explícita. As constantes do platô
      (`GLACIAL_CENTER_X`, `GLACIAL_RECT_*`, `GLACIAL_CORNER_RADIUS`,
      `GLACIAL_RAMP_WIDTH`) são literalmente as da costa com o sinal de Z
      invertido — não cópias com o mesmo valor.
- [x] **🤖 Eu** medi por sonda (`probe_glacial_final.gd`, descartada): área
      do platô 1.783 m² contra 1.775 m² da costa (razão 1,0045 — mesmo
      tamanho), e rampa suave confirmada na borda real nova.
- [x] **🤖 Eu** achei e consertei uma consequência: a área elegível do passe
      geral de scatter (mar raso + recife) cresceu ~13,5% com o território
      liberado, e `PZ01_SCATTER_COUNT` fixo em 250 deixou o mar raso mais
      esparso que o teto permite (`test_biome_dressing.gd` acusou: 12,3%
      contra teto de 12%). Subi para 284 (mesma proporção, medida por sonda
      descartada) — mesmo padrão já registrado no corte de 90% da costa.
- [x] **🤖 Eu** atualizei os pontos de sonda fixos que assumiam a posição
      antiga do platô (`test_world.gd`, `test_playable.gd`) para derivar da
      nova geometria em vez de fração escrita à mão.
- [x] **🤖 Eu** rodei as 20 suítes headless — 0 falhas.
- [ ] **👤 Você**: abrir o editor e conferir visualmente — o platô deve
      estar no canto oposto de antes (borda +Z, perto do centro em X) e ler
      como a costa espelhada (mesmo tamanho, mesma irregularidade de borda).
      Assets/textura de gelo continuam os mesmos; só a forma e o tamanho
      mudaram.

## Mini vila da costa: praça, espaçamento e pessoas (2026-09-20)

Pedido do usuário depois de jogar com as três estruturas `.glb` de 18/09: elas
colavam umas nas outras (4,5 m de espaçamento para prédios de 5,7 m), sentavam
na beira da rampa (âncora em `COAST_TOP` por coincidência) e a vila não lia como
lugar habitado — a receita de aparência do comerciante tinha virado código
morto. Decisões dele: pessoa só nos três da costa (arena fica), receita fixa
no jogo para posto e bancada, pavimento como camada de shader + lajes do
MegaKit, e como prop novo só a cerca baixa de pedra e corda.

- [x] **🤖 Eu** — `WorldPopulator`: `VILLAGE_SPACING` 4,5 → 9 m, `VILLAGE_ANCHOR.z`
      = `COAST_TOP - VILLAGE_SETBACK` (8 m; o warp da costa chega a 5,5 m),
      spawn no centro do adro. Sonda de planura (descartada): 0 células fora de
      `LAND_HEIGHT` em x ∈ [-10, 20], z ∈ [-82, -66]. Luzes nos dois vãos.
- [x] **🤖 Eu** — `InteractableActor.attach_npc`: `CharacterRig` filho do MESMO
      ator, diante da fachada (`fundo/2 + 0,8 m`, 35% do meio-lado para o lado
      da porta), encarando +Z; placa sobre a cabeça (`_sign_anchor`,
      `_sign_rest_height` a partir dos pés); segunda cápsula de clique. Poses:
      `Idle_FoldArms` (comerciante), `Cast_Idle` (posto), `Fixing_Kneeling`
      (ferreiro). Achado real: o importador glTF do Godot corta o sufixo
      `_Loop` — o clipe do manifest `Idle_FoldArms_Loop` só existe como
      `Idle_FoldArms` na biblioteca (medido por sonda depois de o teste
      acusar "clipe inexistente").
- [x] **🤖 Eu** — praça: Stone Wall 1 (a 5 tem capim; planta terrestre
      contradiz a época) convertida por `Image.load` do BMP → PNG (diffuse
      RGB8, altura L8, `.import` com mipmaps copiado do par `mud_*`);
      `MapTerrain.bake_mask`/`set_ground_uniform`/`edge_warp`/`rounded_rect_sdf`
      expostos; `MapDressing.plaza_profile` é a fonte única (máscara, keep-out
      do scatter acima de 0,6, posição das lajes); shader `village_paving`
      mistura por altura na orla e converge para laje pura no miolo; 10 lajes
      `RockPath_*` tingidas (`#D8C2A2`) na orla, em `Dressing/Village`.
- [ ] **👤 Você** — gerar `cerca_corda.glb` no Tripo Studio (segmento reto ~2 m,
      ~0,9 m de altura, cobble cinza + corda, sem planta) e copiar para
      `avyron/models/village/props/`; as três entradas da tabela já esperam o
      arquivo (altura em metros, pivô no centro auto-calibrado).
- [ ] **👤 Você** — jogar e julgar: tom `PZ01_PAVED_TINT`, escala das lajes,
      orla, posição/pose das pessoas, e se a frente das três estruturas encara
      o mar (se alguma encarar -Z, é `rotation.y = PI` no modelo daquele ator).
- Suítes: `test_merchant` (92), `test_characters` (135), `test_biome_dressing`,
  `test_world` (51), `test_playable` (24), `test_staging` (92), `test_data`.
