# Auditoria de arquitetura — agosto de 2026

Rodada dedicada a **medir a saúde dos dois projetos e endurecer regras enquanto está barato** — não a entregar mecânica nova. O jogo aqui, o catálogo em `../avyron-bestiary`.

Este documento é o ponto de retomada: o que foi consertado e como isso foi provado, o que sobrou, e as decisões que estão esperando uma resposta sua. O `ROADMAP.md` continua dono das pendências de **produto**; aqui é só saúde estrutural.

Estado do catálogo quando isto foi escrito: `dataVersion 0.267`, 31 criaturas, 31 despertares.

---

## Como esta rodada trabalha

Regras de processo combinadas durante a sessão. Valem para a continuação:

- **A progressão mora nos docs, não em commits.** Nada foi commitado; tudo se acumula na árvore de trabalho e sai num commit só no fim. As duas árvores também contêm trabalho de **outra sessão em paralelo** (`CharacterRig`, `npcAppearances`, migration `0013`, `models/characters/`) — não é desta auditoria.
- **Conceito antes de implementação.** Cada item começou com uma introdução ao que o sistema faz hoje e ao conceito geral em jogo, para decidir com o assunto entendido em vez de aceitar complexidade nova no escuro.
- **Decisão pendente se pergunta.** Nada de escolher por conta em bifurcação que muda o produto.
- **Toda guarda nova é testada por mutação.** Quebrar de propósito, confirmar vermelho, restaurar, confirmar verde. Guarda que não foi vista falhando não conta como guarda.

---

## O diagnóstico original

| # | Item | Estado |
|---|---|---|
| 1 | Guarda de modal duplicada e discordante (jogo) | **fechado** |
| 1.3 | `CRT-013` com golpe permanentemente inutilizável | **fechado** |
| 2 | Quatro atores de mapa com o mesmo corpo copiado (jogo) | **fechado** |
| 3 | Gate do `game:export` desalinhado do `test_data.gd` | **fechado** |
| 4 | `combatBuff` do Relicário — dado sem consumidor | **fechado** |
| 5 | Fábricas na API do bestiário | **fechado (parte b)** |
| 6 | Idioma e acentuação sem regra escrita | pendente |
| 7 | Bioma e `role` como contrato falso | pendente |
| 8 | Caminho errado no README do jogo | pendente (menor do que parecia) |

---

## Fechados

### 1. Guarda de modal — de dez cópias para um predicado

**Correção importante de diagnóstico:** eu reportei isto como bug ativo ("com o posto do Relicário aberto, `F` mina e o clique atravessa"). **Não era.** Sondei empurrando `InputEventKey` de verdade por `root.push_input()` e o pause já barrava tudo:

```
tree.paused = true · WorldRoot.can_process() = false
empurrando F, T, V → janela do time abriu = false
```

`get_tree().paused = true` impede o callback de input em nó pausável. O problema real era outro e mais chato de achar: **dez guardas escritas à mão que não concordavam entre si** — algumas conferiam duelo e loja, outras só duelo, nenhuma o posto. Nada vazava por sorte de arquitetura, não por desenho.

Virou `WorldRoot._modal_open()`, um predicado só, irmão do `_roster_open()` que já existia. E a regra ganhou nome no `CLAUDE.md`: **toda tela é modal-que-pausa ou janela-de-HUD, não existe terceira família**. Escolher errado é o jeito de vazar input.

Prova: `test_merchant.gd::_test_modal_guard` (+10 verificações) abre o posto — o único modal sem cobertura nenhuma — e exige que minerar, time, set e loja fiquem inertes, e voltem a funcionar ao fechar. Mutação na guarda → 2 FAILs.

### 2. `InteractableActor` — e a armadilha que apareceu no meio

Comerciante, arena, posto e guardião repetiam placa flutuante, colisão, bob/spin, alcance de interação e o cálculo de apoio no chão. O despacho de clique tinha quatro `if hit is X` e quatro `handle_click_on_*` quase idênticos.

Decisão: classe base **e** despacho unificado, de uma vez.

| arquivo | antes | depois |
|---|---|---|
| `merchant_actor.gd` | 120 | 73 |
| `arena_actor.gd` | 130 | 87 |
| `relic_station_actor.gd` | 95 | 59 |
| `portal_guardian_actor.gd` | 112 | 76 |

O achado que valeu mais que as linhas economizadas não estava no diagnóstico: os quatro divergiam em **como apoiam o corpo no chão** — dois somavam meia altura, dois atribuíam. Os quatro estavam corretos por coincidência, porque todos ficam no centro plano do mapa onde a altura do terreno é zero. Mover o guardião para a costa (previsto no `ROADMAP.md`) enterraria dois deles no chão. Colapsou em `InteractableActor.ground_on_spot()`, com o porquê escrito no método.

Prova: `_test_actor_grounding` (+5) põe os quatro em `y = 2.4` e exige `spot.y + HEIGHT * 0.5`. Mutação → 0.95 onde deveria ser 3.35.

### 3. Erro e alvo saem por portas diferentes

Ao comparar os dois guardas, a maioria dos checks do `test_data.gd` já era garantida por `NOT NULL` e FK no banco — replicar no export seria código morto. O que sobrou revelou que **os dois estavam com os papéis trocados**:

- o teste **reprovava** na cobertura 1:1 de Despertar, que o `DATA_WORKFLOW` chama de passo opcional — reprovar numa meta;
- **nenhum dos dois** checava golpe `awakeningOnly` numa criatura sem Despertar, que é erro de dado visível para o jogador.

Foi por essa fresta que o `CRT-013` saiu num bundle conhecendo um golpe que nunca poderia usar.

Política adotada nos dois lados (a escolha de avisar em vez de abortar na cobertura foi sua):

| verificação | export | `test_data` |
|---|---|---|
| golpe `awakeningOnly` sem Despertar | aborta | `_check` |
| criatura sem Despertar (cobertura 1:1) | avisa e escreve | `_warn` |
| peso de mineração apontando para não-mineral | aborta | — |
| classe do elenco sem `mining_rates` | aborta | — |
| classe do elenco sem `workFunction` | aborta | — |

Prova: as cinco portas do export testadas por mutação uma a uma, e os dois caminhos do `test_data` (`AVISO` com suíte verde × `FAIL`).

> Susto registrado para não repetir: a mutação do caminho de aviso **escreveu** um bundle sem o Despertar do `CRT-001` em `data/bestiary.json`. Mutação que exercita caminho de escrita precisa de reexport limpo depois — foi o que foi feito.

### 4. `combatBuff` saiu inteiro

O documento de design `relicario` já declarava buff de combate fora do escopo do sistema, e mesmo assim as colunas existiam, eram exportadas e a tela do posto mostrava `buff %.1f`. Pior: a regra de contenção do próprio documento ("modelo novo cadastra os dois como 0") estava sendo violada por 3 dos 4 modelos.

Removido de ponta a ponta — banco (migration `0014`), API, OpenAPI, export, bundle, Godot, UI e docs. O documento `relicario` foi reescrito **pela API**, como manda a regra do repositório (versão `0.267`).

### 1.3 `CRT-013` ganhou Despertar

`DSP-013 "Maldybulakia Tonans"`, tipo `reinforcement`, criado pela API (`0.266`). O código veio da convenção `DSP-XXX ↔ CRT-XXX` que já existia — `DSP-013` era a única lacuna da sequência. `reinforcement` porque o `awakeningMultiplier: 1.5` já estava registrado, então nenhum número precisou ser reescrito. Mantém a regra 70/30 em 22/9, e a cobertura foi a 31/31.

### 5. Fábricas — o bloco que era caso de manual, e o que não era

Os dois candidatos **não eram o mesmo caso**, e essa foi a conclusão principal:

- **4 singletons de regra** (`combatRules`, `progressionRules`, `economyRules`, `relicRules`): `ensureRow`, `get`, montagem do patch, 422 de patch vazio, transação, `update` e `recordChange` **byte a byte iguais**, variando só uma validação de par ordenado que dois têm e dois não. Duplicação essencial — muda junto, e não estava mudando junto.
- **6 junções** (`drops`, `mapBiomes`, `elementalAdvantages`, `merchantOffers`, `miningRates`, `creatureAbilities`): parecidas de longe, mas variam em seis eixos, e duas divergem de verdade — `miningRates` tem chave polimórfica (`classId` XOR `biomeId`, dois alvos parciais com `targetWhere`) e `creatureAbilities` faz o lote sequencial de propósito e é a única com `DELETE`.

Feito: `singletonFactory.ts` + `singletonRoutes.ts`. Services 343 → 50 linhas, routes 211 → 87. O único eixo de variação virou `orderedPairs`, **declarativo e não callback** de propósito: se aparecer validação de outra natureza, o certo é o módulo sair da fábrica, não a fábrica ganhar gancho.

Provas: 18 verificações contra um **clone do banco** (`CREATE DATABASE ... TEMPLATE`, para não queimar versão no catálogo real), batendo nas mensagens literais da versão manual; duas mutações na fábrica (desligar `orderedPairs` → 5 FAILs; `ensureRow` no-op → `AppError: economy rules not found`); `openapi.json` **byte a byte igual** ao anterior, incluindo as duas `description` longas; `200` nos quatro `GET` e `401` nos quatro `PATCH` sem chave.

As junções ficaram manuais **com o critério escrito** no `CLAUDE.md` do bestiário, e um gatilho de reavaliação: a sétima junção.

---

## Achados que não estavam no diagnóstico

Apareceram durante a execução e foram consertados na mesma rodada.

### Lote de junção que não atualizava nada

Em `drops`, `mapBiomes` e `elementalAdvantages`, o `batchUpsert` escrevia:

```ts
set: { chance: schema.drops.chance, updatedAt: new Date() }
```

que o Postgres recebe como `SET chance = drops.chance` — a linha antiga consigo mesma. O lote **inseria o que era novo e ignorava em silêncio tudo que já existia**, enquanto o `recordChange` gravava normalmente uma versão dizendo que N linhas tinham sido atualizadas. O correto é `` sql`excluded.chance` ``.

Sonda com rollback, antes e depois:

```
BATCH (mandou 0.99, tinha 0.11) → 0.11   [antes]  →  0.99   [depois]
```

O formato do defeito é a lição: **os três módulos que o tinham nasceram do mesmo copy-paste**; os três escritos de outro jeito não o tinham. Duplicação não repete só código, repete defeito — e depois o esconde em três lugares.

Procurei dano nos dados: os únicos dois lotes de `elemental_advantages` no changelog (`0.53` e `0.82`) são re-execuções idênticas do mesmo script de promoção, 46 minutos uma da outra. Nada corrompido.

### `drops` duplicava em vez de sobrescrever

A unicidade era `(creature_id, item_id, condition)` com `condition` anulável. Em Postgres `NULL` nunca conflita com `NULL`, então dois POSTs do mesmo drop sem condição criavam **duas linhas**, contra a regra documentada de que junção se reescreve por re-POST. Hoje as 26 linhas têm condição preenchida, mas o campo é opcional no Zod: armadilha armada. Migration `0015` — `UNIQUE ... NULLS NOT DISTINCT`.

### `pnpm db:restore` estava quebrado em máquina nova

O caminho documentado de hidratar uma máquina (`db:create` → `db:restore`) **não funcionava**. O `migrate()` do Drizzle envolve todas as migrations pendentes numa transação só; a `0008` faz `ALTER TYPE item_category ADD VALUE 'material'` e a `0010` usa esse valor num CHECK — o Postgres recusa valor de enum ainda não commitado (`55P04`) e a rodada inteira volta atrás, com **zero** migrations aplicadas. Na máquina de desenvolvimento nunca doeu porque cada migration commitou na sua vez, meses atrás.

Teve uma segunda camada: consertei o `migrate.ts`, rodei o caminho documentado e ele quebrou igual — porque `restore.ts` importava o `migrate()` do Drizzle **direto**. O conserto tinha chegado no comando que ninguém roda em máquina nova e não no que importa. Só apareceu porque o teste foi o caminho documentado, não o script recém-editado.

Virou `packages/db/src/runMigrations.ts`, **uma transação por arquivo**, chamado pelos dois. O parsing e o hash continuam sendo do Drizzle (`readMigrationFiles`); a única coisa que passou a ser nossa é a fronteira da transação, e a escrituração é deliberadamente idêntica.

Provas: banco zerado migrou as 16; `pg_dump --schema-only` do banco novo × do banco real **idêntico** (2136 linhas cada, só diferem os tokens aleatórios do próprio `pg_dump`); `__drizzle_migrations` com 16 linhas de hashes e timestamps idênticos; segunda execução diz "nada pendente"; caminho completo termina em `restore completo — versao 0.267` com contagem de linhas igual à do banco real nas 29 tabelas.

Contrapartida registrada no arquivo: falha no meio agora deixa as anteriores aplicadas em vez de desfazer tudo — é como Rails, Django e Flyway se comportam, e é o preço de conseguir commitar entre um `ALTER TYPE` e o uso do valor. O erro nomeia a migration que parou.

---

## Pendentes

### 6. Idioma e acentuação sem regra escrita

Dois problemas diferentes debaixo do mesmo item.

**Acentuação em texto de jogador.** Muito texto foi escrito sem diacríticos, dos dois lados — o caso âncora é `elements[1].name = "Agua"`, que aparece na ficha da criatura. O `CharacterRig`, sistema mais novo, usa acentos corretos: a inconsistência é temporal, não uma decisão.

O tamanho depende de como se conta, então fica a medição reproduzível em vez de um número solto. Buscando por uma lista conservadora de palavras portuguesas que apareçam **sem** nenhum diacrítico:

```
bundle (data/bestiary.json)      60 campos de texto
scripts .gd fora de scripts/dev  47 ocorrências
scripts .gd incluindo dev       198 ocorrências
```

Os números são piso, não teto — a lista de palavras é curta de propósito para não gerar falso positivo. O primeiro passo do item é decidir a regra (acentuar tudo que o jogador lê? incluir mensagem de teste?) e só então medir de verdade.

**Idioma de comentário.** O repositório do jogo tem regra explícita (comentários em português); o bestiário não tem nenhuma. O `CLAUDE.md` de lá diz "Código = inglês", mas a lista que segue é de identificadores — tabelas, colunas, endpoints, variáveis —, não de comentários.

Medição de hoje: dos 167 `.ts` em `apps/api/src` + `packages/db/src`, 36 contêm caractere acentuado e 131 não. É proxy grosseiro (um arquivo pode ter acento por causa de um dado, tipo `Óbolo`, e não de um comentário), mas mostra a proporção: a casa é majoritariamente inglesa, com bolsões portugueses — `shared/services/` e os módulos de junção são 100% inglês, enquanto os serviços de singleton eram 100% português antes desta rodada.

> Nota de continuidade: os comentários novos que esta rodada escreveu nos módulos de junção do bestiário saíram **em inglês**, para casar com a vizinhança imediata (aqueles arquivos e `shared/services/` são 100% inglês hoje). Não é uma decisão de regra — é uma escolha local até o item 6 decidir a global.

### 7. Bioma e `role` como contrato falso

Verificado item por item contra o código e o banco:

| coisa | situação real |
|---|---|
| junção `map_biomes` | tem módulo de API completo (Service, Routes, Controller, Types) e **nunca aparece no `export-game-data.mjs`** |
| `creature.biome` | exportado (linha 500 do export), e **nenhum** `.gd` lê o campo |
| `db.biome(code)` | existe em `BestiaryData`, indexa o array `biomes` do bundle e **nunca é chamado** |
| `creature.role` | exportado (linha 501); 19 `null`, 8 `regular`, 4 `hero`; o único `"role"` lido pelo jogo é o `role` do `workFunction` da **classe**, coisa diferente |
| bioma do mundo | `@export var biome_code := "BIO-001"` fixo em `world_root.gd:49` — é o único bioma que a mineração enxerga |

O jogo não erra por causa disso; ele só carrega um contrato que promete algo que ninguém cumpre. É o maior buraco de dados que sobrou, e a decisão é binária por campo: ou passa a ser lido, ou sai do bundle.

### 8. Caminho errado no README do jogo — menor do que o diagnóstico dizia

Conferido hoje: **apenas uma linha está errada.**

- `README.md:96` diz `c:\code\avyron\project.godot`; o real é `c:\code\fellipe\avyron\project.godot`.
- O caminho do Godot (`%LOCALAPPDATA%\Programs\Godot\...`, linhas 82/89/421) **está correto** — os dois executáveis estão lá. O diagnóstico original dizia que isso quebrava todo bloco de comando de teste copiável; não quebra. Conserto de uma linha.

### 5(c). `junctionFactory` — adiada com critério escrito

Não é dívida esquecida: está escrito no `CLAUDE.md` do bestiário por que as seis junções seguem manuais e qual é o gatilho para revisar (a sétima junção). Se for feita, o desenho recomendado é cobrir só as **quatro** de par simples e deixar `miningRates` e `creatureAbilities` de fora explicitamente, em vez de encher a fábrica de condicional.

---

## Decisões esperando você

1. **Suíte de teste no bestiário.** Não existe runner nem script `test` — e o `pnpm lint` da raiz falha, porque nenhum pacote define `lint`. A sonda das 18 verificações dos singletons funciona e está guardada, mas transformá-la em teste permanente significa escolher uma convenção nova para o repositório. Enquanto isso, a verificação do bestiário é manual (sonda + `pnpm typecheck`); a do jogo é a suíte headless.
2. **`scripts/dev/shot_map_tmp.gd.uid`** — `.uid` órfão de um andaime de screenshot já apagado. Sinalizado várias vezes, nunca removido sem confirmação.
3. **`docs/VPS_RUNBOOK.md:119`** (bestiário) diz que o migrate "cria as 15 tabelas"; são 29. O documento está marcado como receita arquivada, então ficou intocado.
4. **O commit final.** Nada foi commitado nesta rodada, por combinação. Ao fechar, lembrar que as duas árvores contêm também o trabalho da sessão paralela.

---

## Estado verificado

Medido ao escrever este documento, não copiado de execução antiga.

**Jogo** — 14 de 14 suítes verdes, 4.608 verificações somadas:

```
test_data 61 · test_battle 41 · test_world 34 · test_team 107 · test_items 81
test_mining 4050 · test_merchant 59 · test_encounter 36 · test_staging 60
test_companion 20 · test_duel_screen 13 · test_glyphs 14 · test_playable 8
test_characters 24
```

`test_duel_screen` oscila entre 12 e 13 — é RNG, não regressão: a verificação "a tela anuncia o Despertar" roda dentro do laço de rodadas, e o número de rodadas varia com a variância de dano. Já se comportava assim antes desta rodada.

**Bestiário** — `pnpm typecheck` limpo nos três workspaces; banco em `0.267`; sondas de teste removidas, só `bestiary` no container.

---

## Armadilhas que custaram tempo

Registradas para não custarem de novo. As de Godot também estão no `CLAUDE.md`; as duas últimas são de ferramenta e não têm outro lugar.

- **`class_name` novo não existe para `--script` até reimportar.** O sintoma engana: as suítes seguem "OK" com contagens *menores*, e o erro real sai no stderr. Depois de criar script com `class_name`, rodar `--headless --editor --quit-after 40` uma vez.
- **`queue_free()` é diferido.** Teste que remove um nó e confere a remoção no mesmo quadro falha por artefato. Conferir o estado síncrono.
- **Testar em banco clonado, não no real.** `CREATE DATABASE probe TEMPLATE bestiary` dá schema e dados idênticos para exercitar caminho de escrita sem queimar versão no catálogo. Derrubar depois.
- **Escapamento no Bash do Windows.** Crase dentro de template literal dentro de string com aspas duplas é interpretada pelo shell. O caminho que funciona: escrever o conteúdo num arquivo do scratchpad com heredoc entre aspas simples e emendar com um `node -e` curto. E o `/tmp` do Node não é o `/tmp` do Git Bash — usar caminho absoluto do Windows.
