# Roadmap

O que está pendente, em que ordem, e por quê. Cobre os dois repositórios — o jogo aqui, o catálogo em `../game`.

Atualizado em: bundle `dataVersion 0.178`. O catálogo segue em edição contínua por outra sessão em paralelo — este número já deve estar defasado quando você ler.

---

## Pendências imediatas

### 1. Item de cura em combate

**A metade do mapa está feita.** `ITM-016`/`017`/`018` se usam pela janela do time (`I` → alvo → item), consomem a bolsa e curam de verdade. `ItemEffects` é a classe de fórmula, `PlayerRoster.heal_at` aplica, `WorldRoot.use_item_on_slot` arbitra, `test_items.gd` prende. O laço econômico fechou: comprar cura é comprar tempo contra os 10 %/min de regeneração.

Falta o uso **em combate**, que é o que o jogador do gênero espera. Exige `Kind.ITEM` em `BattleAction` e `_do_item` em `Battle`, ~40 linhas seguindo o padrão de `_do_capture`, mais um menu de item no `DuelScreen` — a captura não serve mais de referência para isso, virou ação direta sem menu com o Relicário. A aritmética já está pronta e é reusável inteira — `ItemEffects.heal_amount` não sabe se quem chama é o mapa ou a batalha.

Duas decisões a tomar quando isso for feito, e nenhuma delas é óbvia:

- **Usar item gasta o turno?** Se sim, é uma jogada e o adversário ataca no intervalo — mesma economia da troca. Se não, cura vira dominante e o duelo trava em quem tem mais emplastro.
- **A recusa de cura nula vale em combate?** No mapa ela vale (`use_item_on_slot` mede antes de consumir). Em combate, recusar depois que o turno já foi escolhido é pior que gastar — o certo é a lista não oferecer alvo cheio, como a janela do mapa já faz.

### 2. Nginx ainda devolve 502 em produção

O processo PM2 foi removido, mas o server block do Nginx segue ativo fazendo proxy para um upstream morto — a UI carrega e falha em toda chamada. É a versão mais confusa de "desligado".

```bash
sudo rm /etc/nginx/sites-enabled/bestiary
sudo nginx -t && sudo systemctl reload nginx
```

### 3. Modelos 3D e o Git LFS no repositório do bestiário

**A convenção de nome mudou:** os modelos antigos com sufixo (`CRT-001.v2.glb`, `CRT-002.v4.glb`) foram removidos, e os novos entram como **`CRT-XXX.glb`**, sem versão no nome.

Três consequências, todas silenciosas:

**a) `scripts/publish-models.mjs` virou no-op.** O seletor é `/^(CRT-\d+)\.v(\d+)\.glb$/` — só casa com a forma antiga. Com nomes sem sufixo ele não encontra nada e imprime *"no local .glb files matched — nothing to do"*, que lê como sucesso. O script também aponta para `bestiary.sysnode.com.br`, que está aposentado. Está morto por dois motivos; ou se conserta (regex nova + alvo local) ou se remove.

**b) Sete criaturas têm `model_url` apontando para arquivos apagados.** No snapshot: `CRT-001`, `002`, `003`, `009`, `017`, `019`, `025` → `/models/CRT-XXX.vN.glb`. É dado a corrigir via `PATCH /creatures/{code}` quando os modelos novos entrarem, seguido de `pnpm db:dump`.

**c) A janela para migrar ao LFS abriu.** Estado do histórico do repositório `game`:

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

### 4. A câmera de batalha enquadra o domador, não o confronto

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

### 5. Relicário e progressão — pontas soltas do redesenho de captura

A mecânica está de pé — captura, XP de relicário e de criatura por participação, drops, storage, posto, set do jogador — mas algumas coisas seguem deliberadamente em aberto:

- **Aquisição de relicário *especializado* não existe.** O starter (`RLC-000`, neutro — sem elemento/classe, `slotCapacity 2`) resolve o boot; `RLC-001/002/003` (um por classe, com buff de combate zerado — ver abaixo) continuam sem forma de conquista. O posto deixa trocar para **qualquer** modelo do catálogo sem checar posse, mesmo furo de sempre, só visível em jogo em vez de escondido atrás de "fora de escopo". Loot de dungeon, arena, crafting ou quest são os candidatos óbvios; nenhum foi decidido. A primeira escolha relevante de especialização está prevista como recompensa da arena final do mapa — também fora de escopo ainda.
- **O buff de combate do Relicário foi removido do sistema**, não só adiado: o equipamento agora só cobre captura, afinidade de captura, slots e progressão própria — nenhum bônus direto de status em batalha (`DuelScreen._apply_relic_buff` saiu, `attack_modifier` não é mais tocado pelo relicário). `relic-stats.combatBuffBase/PerLevel` seguem no catálogo, sempre `0` nos modelos atuais — não removidos por ficarem sem consumidor, só desligados. Se o jogo ganhar buff de combate no futuro, é peça de outro slot do set do jogador, não deste.
- **Números de XP e custo de material são placeholders sem playtest**, dos dois lados (`relic_rules.xpPerCapture/xpCurveBase/xpCurveExponent/materialCostBase/materialCostLevelStep` e o mesmo bloco em `progression_rules`) — mesma ressalva que já existia para a regeneração de HP. Some-se a eles `ProgressionMath.XP_BASE_SHARE_RATIO` (hoje `0.2`/`0.8` entre parcela base e parcela por contribuição na divisão de XP entre participantes de uma vitória): também sem playtest, também um ponto só para mudar quando o número fechar.

Nenhum bloqueia jogar — o sistema funciona de ponta a ponta sem eles fechados. Bloqueiam é declarar a mecânica "pronta" em vez de "jogável".

---

## O caminho maior

A ordem abaixo foi escolhida por dependência, não por preferência. Cada item destrava o seguinte.

### Construção — o próximo

Agora tem sentido: os minérios têm preço, e o comerciante pode vender as plantas. Antes da economia, construir era um sistema procurando uso.

**O que construir** deve atacar os atritos que o jogo já tem, não uma lista genérica. Hoje são três: voltar até o comerciante, esperar 10 minutos de HP, e minerar a taxa fixa. Isso sugere um "posto avançado" — ponto de descanso que acelera a regeneração num raio, extrator de minério passivo, marco de retorno. Cada peça responde a uma dor já sentida jogando.

### Vilarejo e arenas

É um contêiner: construído antes do conteúdo, é um cômodo vazio. Depois do comerciante e da construção, tem o que guardar.

**A primeira arena já existe**, fora de ordem em relação ao resto deste item — documento `glifos-e-portais` no bestiário. `Battle.is_wild = false` (que desliga captura e trata o adversário como criatura de outro domador) tinha o caminho pronto e nunca usado em jogo; agora tem consumidor: `ArenaActor` + `NPC-002` (`role = duelist`) + `WorldRoot._on_arena_engaged`, concedendo o Glifo Daleth numa vitória. O que falta desta peça não é mais "existe arena?" — é vilarejo de verdade ao redor dela (hoje é um ponto isolado no mapa, mesmo estágio de posto do Relicário e comerciante) e uma segunda arena quando Titanor tiver mapa (Glifo Zayin está definido no bestiário, sem onde morar ainda).

### Arte — em paralelo, não no fim

É o único item que **não bloqueia em decisão de código**, e o de maior prazo: oito loops de animação por criatura (`idle`, `walk`, `run`, `attack_primary`, `attack_secondary`, `hurt`, `death`, `victory`), 26 criaturas.

Pôr por último desperdiça o paralelismo. Já está em andamento — ver item 3 acima.

**Ressalva:** se o que pesa é olhar cápsula cinza, o **modelo do jogador** é peça avulsa e vale adiantar. É o que se olha 100 % do tempo, é um asset só, e não depende de nenhuma decisão acima.

---

## Coisas que ficaram medidas e valem revisitar

Números escolhidos com raciocínio mas sem playtest. Todos ajustáveis por `PATCH` no bestiário, exceto onde indicado.

| O quê | Valor | Onde |
|---|---|---|
| Regeneração de HP | 10 %/min | `PlayerRoster.REGEN_FRACTION_PER_MINUTE` — **em código**, é o único que não veio do bestiário |
| Renda de mineração | ~98 óbolos/min no PZ-01 com Loricati | derivado de `item_stats.value` × `mining_rates` |
| Emplastro de Limo | 80 óbolos por 30 % do HP ≈ 3 min de regeneração comprados | `item_stats` |
| Seiva Primordial | 600 óbolos por 100 % ≈ 10 min comprados, a 2,25× o preço por ponto | `item_stats` |
| Margem do comerciante | `sellRatio` 0.4 | `economy_rules` |
| Distância do companheiro | 2,6 m parado / 3,6 m correndo | `CompanionActor.FOLLOW_DISTANCE` — apresentação, fica em código |
| Recuo do domador em combate | ~3,25 m (era 6,5 m) | `BattleStaging.TRAINER_SPREAD` — apresentação, fica em código |
| Bônus de captura do Relicário | mesmo elemento +15, mesma classe +10, elemento em desvantagem −15 (pontos percentuais) | `relic_rules` |
| XP por captura / curva de nível do Relicário | 20 por captura, `xpCurveBase` 10, `xpCurveExponent` 1.5 | `relic_rules` |
| Custo de material por nível (Relicário e criatura) | base 1 unidade, +1 a cada 20 níveis | `relic_rules.materialCost*` / `progression_rules.itemCost*` |
| Parcela base × parcela por contribuição no XP de vitória | 20 % base (dividida igual entre participantes) / 80 % por contribuição | `ProgressionMath.XP_BASE_SHARE_RATIO` — **em código**, não veio do bestiário |

A regeneração é a primeira que eu mexeria depois de jogar: seis criaturas se recuperando em paralelo pode tornar a espera irrelevante, ou o contrário — ficar parado olhando a HUD.

E agora ela não se mexe sozinha. Com a cura comprável, `REGEN_FRACTION_PER_MINUTE` é o denominador do preço de todo emplastro: acelerar a regeneração desvaloriza a prateleira inteira de uma vez, e o inverso torna a Seiva Primordial barata. Os dois números se ajustam juntos ou o comerciante fica com estoque parado. Vale notar a assimetria de propósito: por ponto percentual de HP, o Limo sai a 2,67 óbolos, o Espesso a 3,14 e a Seiva a 6,00 — o item caro compra *conveniência de um clique só*, não HP mais barato. A janela mostra o desperdício em ember justamente porque essa curva pune usar o caro cedo.
