# Roadmap

O que está pendente, em que ordem, e por quê. Cobre os dois repositórios — o jogo aqui, o catálogo em `../avyron-bestiary`.

Saúde estrutural (duplicação, contratos que mentem, guardas que não guardam) não mora aqui — mora em [AUDITORIA.md](AUDITORIA.md).

Atualizado em: bundle `dataVersion 0.420`, 60 criaturas, todas alocadas em mapa. O catálogo segue em edição contínua por outra sessão em paralelo — este número já deve estar defasado quando você ler.

---

## Fechado na rodada do mapa (2026-08)

O PZ-01 saiu de "chão liso com cápsulas" para um mapa vestido — o detalhe de cada peça está no README ("Assets 3D" e "Relevo e solo"):

- **Elenco inteiro com corpo animado**: 31/31 criaturas vinculadas N:1 aos placeholders do Quaternius (vocabulário de clipes normalizado, botão "vincular/alterar modelo" na ficha do bestiário), resolvidas por `modelUrl` com fallback em cápsula.
- **Cenário do PZ-01**: props aquáticos do Meshy + `MapDressing` (landmarks + scatter com semente), relevo com colisão e consulta (`MapTerrain`), costa na borda -Z para NPCs/portais, e iluminação fragmentada por altura (murk subaquática × costa quente).
- **Ilha da arena** no meio do mapa: platô de 8 m (+2,6 m) com rampa andável (38°), o duelista em cima e a origem do jogador junto — o jogo abre em terra seca e desce para o mar. Segue as mesmas regras do trecho emerso da costa: predicado próprio (`on_island`), keep-out de spawn, sem scatter de bioma, tom seco no shader e omni de preenchimento.
- Pontas soltas que esta rodada abriu: `PORTAL_SPOT` ainda ao pé da rampa em vez de na costa — hoje sem urgência, porque o PZ-01 deixou de ter guardião (travessia interna de era é livre; ver "Arena e Glifos" no README), e mover o posto é uma constante só desde o `InteractableActor.ground_on_spot()`; PZ-02/PZ-03 sem receita de dressing (o MegaKit já está no pipeline esperando por elas); mob pode vagar até a beira da rampa em casos raros (keep-out cobre o spawn, não a patrulha inteira — vale igual para a ilha).

---

## Pendências imediatas

### 1. Item de cura em combate

**A metade do mapa está feita.** `ITM-016`/`017`/`018` se usam pela janela do time (`I` → alvo → item), consomem a bolsa e curam de verdade. `ItemEffects` é a classe de fórmula, `PlayerRoster.heal_at` aplica, `WorldRoot.use_item_on_slot` arbitra, `test_items.gd` prende. O laço econômico fechou: comprar cura é comprar tempo contra os 10 %/min de regeneração.

Falta o uso **em combate**, que é o que o jogador do gênero espera. Exige `Kind.ITEM` em `BattleAction` e `_do_item` em `Battle`, ~40 linhas seguindo o padrão de `_do_capture`, mais um menu de item no `DuelScreen` — a captura não serve mais de referência para isso, virou ação direta sem menu com o Relicário. A aritmética já está pronta e é reusável inteira — `ItemEffects.heal_amount` não sabe se quem chama é o mapa ou a batalha.

Duas decisões a tomar quando isso for feito, e nenhuma delas é óbvia:

- **Usar item gasta o turno?** Se sim, é uma jogada e o adversário ataca no intervalo — mesma economia da troca. Se não, cura vira dominante e o duelo trava em quem tem mais emplastro.
- **A recusa de cura nula vale em combate?** No mapa ela vale (`use_item_on_slot` mede antes de consumir). Em combate, recusar depois que o turno já foi escolhido é pior que gastar — o certo é a lista não oferecer alvo cheio, como a janela do mapa já faz.

### 2. Set do jogador — o que ficou aberto no Amplificador e no Encantador

A mecânica está de pé e jogável: duas peças, três tiers cada, fabricadas na bancada com minério, passivas em combate, com a exclusividade glacial funcionando. `test_equipment.gd` prende 103 verificações. O que segue aberto:

- **Nada disso persiste.** Posse e equipado vivem em memória, como o time e a bolsa — fechar o jogo apaga trinta cobres de trabalho. `PlayerProgress` continua sendo o único que grava em disco, e é lá que as duas listas entram quando o save crescer. É a pendência mais cara das três, porque é a única que o jogador sente como perda.
- **Os números são placeholders, como sempre.** 5/10/15 pontos percentuais e as quantidades das receitas (330 / 820 / 1 860 óbolos de material) são escolhas com raciocínio e sem playtest. O que está preso é a *relação*, não os valores: o passivo tem de ser mais fraco que o golpe que custa a rodada, e os dois slots do mesmo tier têm de custar igual.
- **Metade do vocabulário de efeito não tem modelo.** `buff_defense` e `debuff_defense` são valores válidos do enum e ninguém os usa. Não é dívida — é espaço deixado de propósito, e um modelo que os use não custa uma linha de código, porque o efeito é dado. Vale quando houver razão de design para um eixo defensivo, não antes.

O que **não** está em aberto, e vale registrar para não ser reaberto por engano: uso ativo em combate. Estas peças são passivas por decisão; uma peça que dispare efeito na rodada é outro desenho e encosta no trabalho do item 1.

---

### 3. Nginx ainda devolve 502 em produção

O processo PM2 foi removido, mas o server block do Nginx segue ativo fazendo proxy para um upstream morto — a UI carrega e falha em toda chamada. É a versão mais confusa de "desligado".

```bash
sudo rm /etc/nginx/sites-enabled/bestiary
sudo nginx -t && sudo systemctl reload nginx
```

### 4. Git LFS no repositório do bestiário

**Atualizado (rodada do mapa):** as partes (a) e (b) que viviam aqui morreram de causas naturais — `publish-models.mjs` foi removido do repo, e os `model_url` órfãos foram limpos pelo `syncModels` (que hoje só gerencia o padrão `CRT-XXX.glb` e preserva os vínculos N:1 de placeholder). Todo o elenco aponta para placeholders vivos. O que resta deste item é só o LFS:

**A janela para migrar ao LFS continua aberta.** Estado do histórico do repositório do bestiário:

| | |
|---|---|
| blobs de `.glb` no histórico | 14 |
| soma bruta | 194 MB |
| `size-pack` do repositório | 140,6 MiB |

Praticamente todo o peso do repositório são modelos — todo o código, migrations, documentos e 104 versões de changelog cabem no resto. E git soma, nunca substitui: o commit `1354e63` ("draco-compressed v2, 13MB → 2.4MB") não economizou um byte no repositório, porque os 12,8 MB originais continuam lá e o v4 somou 26,4 MB por cima.

Como os modelos estão sendo **trocados por inteiro agora**, o custo de reescrever o histórico nunca vai estar mais baixo:

```bash
# 1. instalar git-lfs no servidor ANTES, se o deploy voltar algum dia
# 2. num branch:
git lfs migrate import --include="*.glb" --everything
# 3. conferir que os modelos abrem e que size-pack despencou
# 4. force-push
```

O `avyron` já está protegido — `.gitattributes` com filtros LFS entrou antes do primeiro asset.

### 5. A câmera de batalha enquadra o domador, não o confronto

`BattleStaging` põe os dois combatentes frente a frente e o domador atrás da própria criatura. A composição está certa; quem não a mostra é a câmera, que segue o `Player` — e o `Player` agora é uma das **pontas** dela, não o centro.

**Atualizado:** `BattleStaging.TRAINER_SPREAD` caiu de `3,0` para `1,5` (recuo do domador pela metade, a pedido — mitigação, não a correção definitiva abaixo). A conta, recalculada:

| | antes | agora |
|---|---|---|
| domador → companheira | 6,5 m | **3,25 m** |
| companheira → adversário | 8,9 m | 8,9 m (sem mudança) |
| adversário → centro do quadro | 15,4 m | **12,15 m** |
| meia-altura do enquadramento (size 15,01) | 7,5 m | 7,5 m |
| meia-largura a 16:9 | 13,35 m | 13,35 m |

Com `base_size` em 17,15: ao longo do eixo de visão a projeção comprime por `sin(18°)`, e 12,15 m viram ~3,75 m contra 7,5 m de meia-altura — folga ampla. Perpendicular, sem compressão nenhuma: 12,15 m contra 13,35 m de meia-largura — o caso que antes estourava (15,4 > 13,35) agora **cabe**, para este par de exemplo. Não é garantia geral: um par grande o bastante ainda estoura, só que precisa ser maior que o medido aqui para chegar lá.

A correção definitiva continua sendo apontar a câmera para o **ponto médio dos dois combatentes** enquanto a batalha dura. `IsoCamera.set_target` já existe, e o ponto médio é exatamente o que a correção simétrica da encenação preserva — ele não se move, então seria um alvo estável, não um que persegue, e elimina a dependência do ângulo por completo (não só reduz, como a mitigação acima).

O que trava a decisão não é a implementação, é o contrato: a câmera hoje tem **um** alvo e o lookahead lê a velocidade dele (`_target is CharacterBody3D`). Um ponto médio não é um nó, então ou `set_target` passa a aceitar uma posição, ou nasce um nó-âncora que a encenação move. O segundo é mais feio e não muda o `_physics_process`; o primeiro é mais limpo e mexe no lookahead.

### 6. Relicário e progressão — pontas soltas do redesenho de captura

A mecânica está de pé — captura, XP de relicário e de criatura por participação, drops, storage, posto, set do jogador — mas algumas coisas seguem deliberadamente em aberto:

- **Aquisição de relicário *especializado* não existe — e agora isso destoa.** O Amplificador e o Encantador nasceram com posse (`PlayerLoadout` separa fabricado de equipado, e `equip()` recusa o que não é do jogador), porque a bancada é o sistema de aquisição deles. O posto do Relicário segue sem nada disso, e o contraste ficou visível dentro do próprio set: duas peças exigem conquista, uma não. Quando a aquisição de relicário for desenhada, `PlayerLoadout` é a forma já provada — não é preciso inventar outra. O starter (`RLC-000`, neutro — sem elemento/classe, `slotCapacity 2`) resolve o boot; `RLC-001/002/003` (um por classe — ver abaixo) continuam sem forma de conquista. O posto deixa trocar para **qualquer** modelo do catálogo sem checar posse, mesmo furo de sempre, só visível em jogo em vez de escondido atrás de "fora de escopo". Loot de dungeon, arena, crafting ou quest são os candidatos óbvios; nenhum foi decidido. A primeira escolha relevante de especialização está prevista como recompensa da arena final do mapa — também fora de escopo ainda.
- **O buff de combate do Relicário foi removido do sistema**, não só adiado: o equipamento agora só cobre captura, afinidade de captura, slots e progressão própria — nenhum bônus direto de status em batalha (`DuelScreen._apply_relic_buff` saiu, `attack_modifier` não é mais tocado pelo relicário). `relic-stats.combatBuffBase/PerLevel` **saíram do banco** em 2026-08 (migration `0014`), junto com o campo `buff` que o posto do Relicário ainda exibia. Se o jogo ganhar buff de combate no futuro, é peça de outro slot do set do jogador, não deste — e nasce com consumidor, não antes dele.
- **Números de XP e custo de material são placeholders sem playtest**, dos dois lados (`relic_rules.xpPerCapture/xpCurveBase/xpCurveExponent/materialCostBase/materialCostLevelStep` e o mesmo bloco em `progression_rules`) — mesma ressalva que já existia para a regeneração de HP. Some-se a eles `ProgressionMath.XP_BASE_SHARE_RATIO` (hoje `0.2`/`0.8` entre parcela base e parcela por contribuição na divisão de XP entre participantes de uma vitória): também sem playtest, também um ponto só para mudar quando o número fechar.

Nenhum bloqueia jogar — o sistema funciona de ponta a ponta sem eles fechados. Bloqueiam é declarar a mecânica "pronta" em vez de "jogável".

### 7. O mapa cresceu para 120 m, com alvo declarado de 350

A conta é de tempo: **30 s de travessia por bioma** a 5,2 m/s dão 156 m por bioma, e cinco biomas pedem 350 m de lado. Aplicados 120 m nesta rodada porque tamanho sem conteúdo é vazio — os 44 props de antes diluídos em 350 m dariam 1 a cada 2.784 m². Detalhe e tabela no README, "O tamanho do mapa, e o que escala com ele".

O que fica pendente para chegar aos 350 m, e nenhum é trabalho de tuning:

- **`MultiMesh` para o scatter.** Hoje são 132 instâncias de `.glb` soltas; a 350 m seriam ~1.500 e cada uma é um nó.
- **População de criatura local ao jogador.** `CreatureSpawner.creature_count` é contagem fixa povoada na abertura. Subiu de 8 para 24 no resize, e 24 já foi escolhido por prudência (a densidade proporcional daria 41, e esse número nunca foi medido nesta cena). A 350 m a densidade proporcional daria ~270, que não é questão de ajustar o campo.
- **Medir os 245 mil triângulos do terreno.** A grade de 1 m não é opcional — `HeightMapShape3D` fixa o espaçamento, e o princípio do `MapTerrain` é que malha, colisão e consulta saem da mesma grade. É o primeiro número desse arquivo que precisa de medição em vez de estimativa.
- **O posto avançado deixou de ser ideia e virou pré-requisito.** A ida e volta ao comerciante era de 8,8 s a 60 m, é de 18 s a 120 m e seria de 52 s a 350 m. A primeira das três fricções que este ROADMAP lista ("voltar até o comerciante") escala junto com o mapa, e é a que o posto avançado existe para resolver.

---

### O bioma virou consulta — fechado em 2026-08-28

**As duas metades fecharam.** As taxas primeiro (todos os biomas do catálogo têm `mining_rates`, e bioma novo entra com as 11 ou não entra), a partição espacial depois: `maps[].biomeRegions` no export, `MapBiomes.biome_at(pos)` no Godot, `WorldRoot` consultando em vez de declarar. Andar da costa para o recife troca o perfil de mineração, e o painel da criatura ativa mostra. Detalhe do desenho — coordenadas normalizadas, ordem de avaliação, as três travas — no README, "Bioma: consultado por posição".

O que **não** fechou junto, e é escopo do desenho espacial do mapa:

- ~~Dois biomas sem região~~ — **fechado em 2026-08-28.** O desenho espacial foi autorado a partir de uma planta do designer: cinco biomas, sete regiões, cobertura total, nenhum bioma inalcançável. Os três avisos silenciaram e `test_playable` passou a sondar os cinco. O relevo acompanhou: a costa virou lobo, porque a planta a desenha assim e manter a faixa faria 47% do chão seco responder "mar raso".
- **O cenário não acompanha a partição, e agora é a ÚNICA peça que falta.** `MapDressing` veste os 14.400 m² com um kit só: os mesmos corais no anel do centro e a 55 m dele. A mineração distingue cinco lugares, a partição distingue cinco lugares, e a imagem distingue **um** — uma captura da Plataforma Glacial hoje mostra o painel dizendo "Plataforma Glacial" sobre um leito coberto de coral turquesa.

  Duas contas já medidas: só **5 dos 14 landmarks** de coral caem dentro dos Jardins Recifais desde que a região saiu do centro (os props continuam plantados em anel em volta da origem), e nenhum dos onze props do kit aquático lê como gelo, sedimento glacial ou fundo abissal.

  **O escopo do acervo está fechado** em [`../avyron-bestiary/docs/BIOME_PROPS.md`](../avyron-bestiary/docs/BIOME_PROPS.md): 21 peças novas, distribuídas por bioma, com orçamento de triângulo e textura, e a ordem de encomenda escolhida por quanto cada peça muda a leitura do mapa — o glacial primeiro, porque é o bioma que hoje mente na cara do jogador.

  Falta de código, e o acervo não serve sem: `MapDressing` consultar `biome_at` no sorteio em vez de vestir o mapa inteiro com um pool só; reposicionar os corais para o recife novo; e ambiência por bioma (hoje a névoa é fragmentada por ALTURA, num `Environment` só, e nem escuro-abissal nem frio-glacial são expressáveis como altura).
- **Nada usa o bioma além da mineração, e o BIO-014 depende disso.** Spawn de criatura, ambiência e névoa continuam decididos por predicado geográfico em código (`on_coast`, `on_island`) em vez de por bioma. A Plataforma Glacial é declarada **sem fauna** — nem nasce, nem patrulha, mesmo tratamento que a ilha recebe —, e isso não é expressável em dado hoje. São duas saídas: um quinto predicado geográfico em código, ou fazer o keep-out do spawner derivar de `biome_at`. A segunda é a que não cobra código novo a cada bioma; nenhuma das duas existe.

---

## O caminho maior

A ordem abaixo foi escolhida por dependência, não por preferência. Cada item destrava o seguinte.

### Construção — o próximo

Agora tem sentido: os minérios têm preço, e o comerciante pode vender as plantas. Antes da economia, construir era um sistema procurando uso.

**O que construir** deve atacar os atritos que o jogo já tem, não uma lista genérica. Hoje são três: voltar até o comerciante, esperar 10 minutos de HP, e minerar a taxa fixa. Isso sugere um "posto avançado" — ponto de descanso que acelera a regeneração num raio, extrator de minério passivo, marco de retorno. Cada peça responde a uma dor já sentida jogando.

### Vilarejo e arenas

É um contêiner: construído antes do conteúdo, é um cômodo vazio. Depois do comerciante e da construção, tem o que guardar.

**A primeira arena já existe**, fora de ordem em relação ao resto deste item — documento `glifos-e-portais` no bestiário. `Battle.is_wild = false` (que desliga captura e trata o adversário como criatura de outro domador) tinha o caminho pronto e nunca usado em jogo; agora tem consumidor: `ArenaActor` + `NPC-002` (`role = duelist`) + `WorldRoot._on_arena_engaged`, concedendo o Glifo Daleth numa vitória. Ela ganhou **lugar próprio** desde então: o topo da ilha no meio do mapa, cercado de mar. O que falta desta peça não é mais "existe arena?" nem "onde ela fica?" — é o que se constrói em cima da ilha (estrutura de arena de verdade, arquibancada, algum acesso encenado; hoje é o duelista de pé em duas pedras) e uma segunda arena quando Titanor tiver mapa (Glifo Zayin está definido no bestiário, sem onde morar ainda).

### Arte — em paralelo, não no fim

É o único item que **não bloqueia em decisão de código**, e o de maior prazo: os loops de animação por criatura, no **vocabulário normalizado que o código já consome** (`Idle`, `Walk`, `Run`, `Attack`, `Attack2`, `HitReact`, `Death` — ver README, "Assets 3D"), para todo o elenco.

**A lacuna de curto prazo fechou com os placeholders animados** (rodada do mapa): 31/31 criaturas têm corpo rigado em jogo hoje. O que esta frente entrega agora é identidade, não funcionalidade — os modelos definitivos (Meshy animado ou arte própria) substituem placeholder por placeholder via `modelUrl`, sem tocar em código.

**Meia identidade já chegou sem asset novo** (rodada da paleta): os placeholders são recoloridos pela rampa do elemento e o Despertar Ancestral acende aura da cor do elemento — ver README, "Cor por elemento e a aura do Despertar". Isso desanuvia a leitura de longe (27 dos 30 corpos dividiam dois atlas) e **não substitui** esta frente: matiz separa elemento, silhueta separa criatura, e duas criaturas do mesmo elemento com o mesmo corpo continuam sendo a mesma criatura para o jogador. O que a paleta compra é tempo. Duas pendências herdadas dela:

- **A rampa foi autorada contra o PZ-01**, cujo ambiente é aquático e esverdeado. Mapa novo com dominante diferente pode engolir um elemento — a tela `/elements` do bestiário mostra a rampa contra os fundos reais do mapa, e é lá que se confere antes de gravar.
- **`spread` está em 0,12–0,22 sem playtest.** É o quanto uma criatura pode variar dentro da família; alto demais e duas criaturas do mesmo elemento param de ler como parentes, baixo demais e ficam idênticas. Número de conteúdo, ajustável na tela, ainda sem alguém tendo jogado o suficiente para dizer.

**Ressalva (resolvida):** o modelo do jogador foi adiantado — e virou sistema, não asset. Jogador e NPCs humanos agora montam de um kit modular com esqueleto compartilhado (`CharacterRig`, documento `personagens-humanos` no bestiário): o jogador usa `PlayerController.DEFAULT_RECIPE`, os dois NPCs vestem receitas do catálogo (`npc_appearances`), e a cápsula ficou como fallback de receita vazia. O que restou desta frente: tela de criação de personagem (a receita já é dado; falta a UI que edita o que vira save), tint de paleta no shader toon para multiplicar variedade, e ligar o clipe `Throw` ao arremesso de captura.

---

## Coisas que ficaram medidas e valem revisitar

Números escolhidos com raciocínio mas sem playtest. Todos ajustáveis por `PATCH` no bestiário, exceto onde indicado.

| O quê | Valor | Onde |
|---|---|---|
| Regeneração de HP | 10 %/min | `PlayerRoster.REGEN_FRACTION_PER_MINUTE` — **em código**, é o único que não veio do bestiário |
| Renda de mineração | ~98 óbolos/min no PZ-01 com a classe escavadora | derivado de `item_stats.value` × `mining_rates` |
| Emplastro de Limo | 80 óbolos por 30 % do HP ≈ 3 min de regeneração comprados | `item_stats` |
| Seiva Primordial | 600 óbolos por 100 % ≈ 10 min comprados, a 2,25× o preço por ponto | `item_stats` |
| Margem do comerciante | `sellRatio` 0.4 | `economy_rules` |
| Distância do companheiro | 2,6 m parado / 3,6 m correndo | `CompanionActor.FOLLOW_DISTANCE` — apresentação, fica em código |
| Recuo do domador em combate | ~3,25 m (era 6,5 m) | `BattleStaging.TRAINER_SPREAD` — apresentação, fica em código |
| Marcha em que o corpo passa a correr | 2,2 m/s (o jogador se move a 5,2, então corre sempre) | `CharacterRig.RUN_THRESHOLD` — apresentação, fica em código |
| Altura do nadador sobre o leito | 0,9 m | `CharacterRig.SWIM_LIFT` — apresentação, fica em código |
| Cota da superfície da água no PZ-01 | 1,25 m (a MESMA que fragmenta a névoa) | `MapDressing.PZ01_WATER_LINE` — vestimenta de bioma, fica em código |

| Potência do Amplificador / Encantador | 5 / 10 / 15 pontos percentuais por tier | `equipment_stats.effectValue` — o teto de 15 é metade do +30% de `HAB-020`, que custa a rodada |
| Custo de material por tier | 330 / 820 / 1 860 óbolos, igual nos dois slots | `equipment_recipes` — a igualdade entre os slots é design, não coincidência |
| Bônus de captura do Relicário | mesmo elemento +15, mesma classe +10, elemento em desvantagem −15 (pontos percentuais) | `relic_rules` |
| XP por captura / curva de nível do Relicário | 20 por captura, `xpCurveBase` 10, `xpCurveExponent` 1.5 | `relic_rules` |
| Custo de material por nível (Relicário e criatura) | base 1 unidade, +1 a cada 20 níveis | `relic_rules.materialCost*` / `progression_rules.itemCost*` |
| Parcela base × parcela por contribuição no XP de vitória | 20 % base (dividida igual entre participantes) / 80 % por contribuição | `ProgressionMath.XP_BASE_SHARE_RATIO` — **em código**, não veio do bestiário |

A regeneração é a primeira que eu mexeria depois de jogar: seis criaturas se recuperando em paralelo pode tornar a espera irrelevante, ou o contrário — ficar parado olhando a HUD.

E agora ela não se mexe sozinha. Com a cura comprável, `REGEN_FRACTION_PER_MINUTE` é o denominador do preço de todo emplastro: acelerar a regeneração desvaloriza a prateleira inteira de uma vez, e o inverso torna a Seiva Primordial barata. Os dois números se ajustam juntos ou o comerciante fica com estoque parado. Vale notar a assimetria de propósito: por ponto percentual de HP, o Limo sai a 2,67 óbolos, o Espesso a 3,14 e a Seiva a 6,00 — o item caro compra *conveniência de um clique só*, não HP mais barato. A janela mostra o desperdício em ember justamente porque essa curva pune usar o caro cedo.
