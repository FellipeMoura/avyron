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

- [ ] **🤖 Eu** renomeio a pasta `models/biomes/assets_BIO-001/` →
      `assets_BIO-002/` (aqui e a fonte equivalente no `avyron-bestiary`) e
      atualizo as referências em `map_dressing.gd` (`BIO001_KIT` e
      companhia) — mecânico, corrige o nome errado registrado na seção 5
      do doc de BIO-002.
- [ ] **🤖 Eu** escrevo o povoador de densidade: trocar landmark avulso por
      instanciamento do kit dentro da máscara de BIO-002, denso o
      suficiente pra não sobrar chão liso visível (ver
      [bio-002-costa-primordial.md, 3.2](bio-002-costa-primordial.md#32-composição-do-terreno--kit-bash-não-heightfield-puro)).
      **Se as 8 peças atuais não cobrirem a variação que a máscara pede**
      (ex.: falta variante com musgo, falta atol), isso pausa aqui e vira
      pedido pontual de geração adicional — não uma rodada nova de
      protótipo do zero.
- [ ] **🤖 Eu** escrevo o shader triplanar de rocha+musgo para o chão
      residual (3.4), o plano de água dedicado (3.3), e ajusto
      iluminação/AO (3.5).
- [ ] **🤖 Eu** removo o placeholder `pz01_reef_hero_01.tscn`.
- [ ] **🤖 Eu** rodo os testes headless + gero screenshot headless
      (`scripts/dev/shot_*.gd` descartável, apagado depois,
      `--resolution 1600x900`, câmera real -30°/45°) — só pra pegar erro
      grosseiro antes de te chamar, não pra decidir "ficou bom".
- [ ] **👤 Você** abre o editor, joga, e dá o veredito estético final —
      escala em movimento, leitura em câmera de verdade, densidade. Isso eu
      não meço com confiabilidade num screenshot estático.
- [ ] Iteração: você aponta o que não bate, eu ajusto parâmetro/posição e
      reverifico, sem reabrir a Fase 1 a menos que a geografia em si esteja
      errada.

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
- [ ] Repete para o próximo até fechar os 5 biomas do PZ-01.
