# Roadmap

O que está pendente, em que ordem, e por quê. Cobre os dois repositórios — o jogo aqui, o catálogo em `../game`.

Atualizado em: bundle `dataVersion 0.104`.

---

## Pendências imediatas

### 1. Emplastro não é consumível

`ITM-016`, `ITM-017` e `ITM-018` são compráveis, vendíveis e precificados, com `effectCode = heal_percent` no bundle. **Nada os consome.** As resinas de captura já funcionam (`C` no duelo); a cura ficou pela metade.

O gancho de captura já existia em `BattleAction.capture(bonus)`; o de cura **não existe** — `BattleAction.Kind` tem `ABILITY`, `SWITCH`, `CAPTURE`, `FLEE`. Dois caminhos:

- **Usar no mapa**, pela janela do time (`T`): escolhe a criatura, escolhe o item, cura. Não toca em `Battle`. Interage bem com o HP persistente — comprar cura passa a ser comprar tempo contra os 10 %/min de regeneração.
- **Usar em combate**: exige `Kind.ITEM` em `BattleAction` e `_do_item` em `Battle`, ~40 linhas seguindo o padrão que já existe. É o uso clássico do gênero.

O primeiro é menor e já entrega o laço econômico completo. O segundo é o que o jogador vai esperar.

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

---

## O caminho maior

A ordem abaixo foi escolhida por dependência, não por preferência. Cada item destrava o seguinte.

### Construção — o próximo

Agora tem sentido: os minérios têm preço, e o comerciante pode vender as plantas. Antes da economia, construir era um sistema procurando uso.

**O que construir** deve atacar os atritos que o jogo já tem, não uma lista genérica. Hoje são três: voltar até o comerciante, esperar 10 minutos de HP, e minerar a taxa fixa. Isso sugere um "posto avançado" — ponto de descanso que acelera a regeneração num raio, extrator de minério passivo, marco de retorno. Cada peça responde a uma dor já sentida jogando.

### Vilarejo e arenas

É um contêiner: construído antes do conteúdo, é um cômodo vazio. Depois do comerciante e da construção, tem o que guardar.

É também onde o duelo contra IA finalmente acontece. `Battle` já aceita `is_wild = false`, que desliga captura e trata o adversário como criatura de outro domador — o caminho existe e nunca foi usado em jogo. A arena é majoritariamente **conteúdo** (a tabela `npcs` já existe, com `role = duelist`) mais reuso da tela de duelo.

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
| Resina Comum | 60 óbolos ≈ 40 s de mineração | `item_stats` |
| Resina Ancestral | 500 óbolos ≈ 5 min | `item_stats` |
| Margem do comerciante | `sellRatio` 0.4 | `economy_rules` |
| Distância do companheiro | 2,6 m parado / 3,6 m correndo | `CompanionActor.FOLLOW_DISTANCE` — apresentação, fica em código |

A regeneração é a primeira que eu mexeria depois de jogar: seis criaturas se recuperando em paralelo pode tornar a espera irrelevante, ou o contrário — ficar parado olhando a HUD.
