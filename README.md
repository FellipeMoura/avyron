# Avyron

Jogo 3D de coleção de criaturas com tema paleontológico, em Godot.

Câmera isométrica ortográfica **travada em 30° de inclinação e 45° de azimute**. Exploração em tempo real, **combate por turnos** (1v1 com troca livre, disputado no mesmo espaço do mapa, sem corte para arena).

## Onde vive o design

Este repositório é o **jogo**. O catálogo de criaturas, a bíblia de design e todos os números de balanceamento vivem em outro lugar:

- **App:** https://bestiary.sysnode.com.br
- **Repo:** https://github.com/FellipeMoura/game

Essa separação é deliberada. Lá o conteúdo é versionado com changelog a cada mudança e escrito por agentes via API; aqui é código e asset.

## `data/bestiary.json` — gerado, não editar à mão

O bundle é produzido pelo repo do bestiário:

```powershell
cd ..\game
pnpm game:export --from https://bestiary.sysnode.com.br --out ..\avyron
```

Ele carrega um `dataVersion` tirado do changelog, então todo build é rastreável até o estado exato do catálogo de onde saiu. Tudo é endereçado por código (`CRT-001`, `ELE-002`, `HAB-014`) — nenhum id numérico atravessa a fronteira, o que mantém o arquivo diffável em pull request e imune a uma reconstrução do banco.

**Editar este arquivo à mão é o erro que o pipeline inteiro existe para evitar.** A próxima exportação sobrescreve. Se um número está errado, corrija no bestiário via API e re-exporte.

O export **aborta sem escrever nada** se alguma criatura estiver sem stats, sem regra de captura ou sem golpes.

## Vocabulário

| Termo | Significa |
|---|---|
| **Loricati** | artrópodes |
| **Theria** | sinapsídeos |
| **Draconis** | sauropsídeos |
| **Aetheris** | era paleozoica |
| **Titanor** | era mesozoica |
| **Novaterra** | era cenozoica |
| **Despertar Ancestral** | transformação temporária em combate |

"Despertar Ancestral" é o único termo válido para a transformação — o bestiário rejeita escritas que usem os termos descontinuados.

## Regras de combate que o código precisa respeitar

```
valor(nível) = floor(base * (1 + growthRate * (nível - 1)))

dano = floor((poder * ataque / defesa) * 0.4 * multElemental * random(0.90, 1.10))
       mínimo 1

carga: recebe dano ×1.0, causa dano ×0.5, escalado por (carga / 50)
       cheia em 100, dura 3 turnos, zera na reversão
```

Ciclo elemental fechado — cada elemento vence exatamente um e perde para exatamente um:

```
Água → Fogo → Natureza → Terra → Gelo → Eletricidade → Água
```

Vantagem 2.0, desvantagem 0.5, todo o resto 1.0 por omissão. As constantes acima também vêm no bundle, em `rules`.

Especificação legível: documentos `combate`, `carga-e-despertar` e `captura` no bestiário.

## Godot

**4.7.x**, build padrão (GDScript, não .NET), renderizador **Forward+**.

A versão está fixada em `project.godot` via `config/features`. Não trocar sem combinar — dois devs em builds diferentes geram diffs fantasma.

### Instalar

Windows 64, build padrão (não .NET):

- **Download direto (4.7.1):** https://downloads.godotengine.org/?version=4.7.1&flavor=stable&slug=win64.exe.zip&platform=windows.64
- **Página oficial** (release notes + hashes): https://godotengine.org/download/windows/

O zip contém dois executáveis — descompacte os dois em `%LOCALAPPDATA%\Programs\Godot\`:

| Executável | Para quê |
|---|---|
| `Godot_v4.7.1-stable_win64.exe` | abrir o editor e dar play |
| `Godot_v4.7.1-stable_win64_console.exe` | rodar os testes `--headless` do bloco abaixo |

Sem instalador — é só extrair. O path `%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.1-stable_win64_console.exe` é o que os comandos de teste esperam no `$godot`.

### Rodar

Na primeira vez você precisa importar o projeto — depois é só abrir do Project Manager.

1. **Abrir o editor.** Duplo clique em `Godot_v4.7.1-stable_win64.exe` (o de cima da tabela acima, sem `_console`). Abre o Project Manager com uma lista de projetos.
2. **Importar este repo.** Botão `Import` → aponte para `c:\code\avyron\project.godot` → `Import & Edit`. Da segunda vez em diante ele já aparece na lista; duplo clique abre.
3. **Play.** `F5` (ou o botão ▶ no canto superior direito) roda a cena principal definida em `project.godot`, que é o mapa. Para rodar o duelo direto, abra `scenes/duel.tscn` na aba de cenas e aperte `F6` (roda **só** a cena atual).

Se pedir para escolher a Main Scene na primeira execução, aponte para `scenes/main.tscn` — está fixado no `project.godot`, mas versões novas do Godot às vezes perguntam mesmo assim.

**Mapa** (`scenes/main.tscn`) — WASD anda, shift corre, **F minera**, **T abre o time**, câmera isométrica travada seguindo com lookahead. A **criatura ativa** do jogador (starter, `CRT-002` por padrão) segue atrás dele, com bob leve — puramente visual, sem colisão nem clique.

### Como a companheira segue

Ela persegue as posições por onde o jogador **realmente passou** — uma trilha de migalhas a cada 25 cm — mantendo `FOLLOW_DISTANCE` medido *ao longo do caminho*, não em linha reta. Três comportamentos caem de graça desse modelo:

- **Sai depois do comando.** Parada, ela está em cima do alvo; o jogador precisa andar meio metro (a folga da coleira) antes de ela ter motivo para se mexer. A 4 m/s isso é um oitavo de segundo de imobilidade, e só então a rampa de aceleração começa.
- **Chega por trás, pelo mesmo caminho.** Numa curva de 90° ela dobra o canto em vez de cortar a diagonal — medido em 0,008 m de desvio lateral.
- **Girar no lugar não a move.** Rodar sem andar não deposita migalha, então ela fica parada.

A versão anterior mirava um ponto no espaço **local** do jogador e copiava o `rotation.y` dele quadro a quadro. Lia como duas peças da mesma engrenagem, e era o sintoma que motivou esta reescrita.

A velocidade é proporcional ao atraso, com ganho 7.0. Um controlador proporcional puro nunca zera o erro — e aqui isso é a intenção, não defeito: **a coleira estica quando ele corre e encolhe quando ele para.**

| | distância |
|---|---|
| parada | ~2,6 m |
| caminhando (4 m/s) | ~3,2 m |
| correndo (7 m/s) | ~3,6 m |

A orientação também é dela: vem da própria direção de marcha, não do jogador — e parada, ela vira devagar para encarar o domador.

**Nota de apoio no chão:** a companheira fica com a origem em `GROUND_Y`, como qualquer criatura do mapa. Antes ela grudava o Y no `global_position` do jogador, que é o *centro da cápsula* dele (~0,9 m), e ainda subia meia altura do próprio corpo — flutuava um metro. Ficou invisível enquanto ela andava ao lado; passar a andar atrás expôs.

Oito criaturas selvagens nascem espalhadas, lidas do bundle: cápsulas escaladas pelo tamanho de jogo e coloridas pelo elemento. Elas patrulham, notam você a 6 m e param para encarar; as agressivas perseguem. **O combate é disparado por clique**: o primeiro clique numa criatura seleciona e abre um painel de identificação (nome, classe, elemento, tamanho); o segundo clique na mesma começa a batalha ali mesmo — a câmera aproxima 12,5% e **inclina para -18°** (era -30°) num único movimento, e o overlay do duelo revela por fade sobre o mundo congelado. Sem corte de cena. Clique fora ou aperte `Esc` para desmarcar; afastar-se demais também desseleciona.

Contato físico não faz mais nada: agressivas continuam perseguindo por pressão, mas quem aperta o gatilho é sempre o jogador.

**Ciclo de vida no mapa** — vencer o combate remove o adversário do mapa e joga um slot de respawn na fila do `CreatureSpawner`. Depois de 20–40s, o slot vira uma criatura nova (espécie e posição sorteadas do pool do bioma). Fuga e derrota do jogador liberam a criatura de origem para ser reengajada. **Captura** remove o adversário sem respawn e o põe no time como reserva.

## Time e mineração

**A criatura ativa amarra os três sistemas.** Quem está à frente no time é a mesma criatura em toda parte: anda ao lado do jogador, entra no duelo, e — pela **classe** dela — decide o que a mineração produz e em que ritmo. Trocar quem vai à frente não é ajuste de menu; muda o que sai do chão no próximo `F`.

**Time** (`T`) — a janela lista a ativa e as reservas com status (HP atual, ATQ/DEF/VEL e perfil de mineração). Clique numa reserva, ou `1`–`6`, para mandá-la à frente. É a única peça de HUD do mapa que aceita clique — todo o resto usa `MOUSE_FILTER_IGNORE` para não roubar o clique de seleção de criatura. Não pausa o jogo.

Seis slots. A capturada entra como **reserva**: quem estava à frente continua à frente, porque uma criatura recém-pega assumindo a exploração e o perfil de mineração no meio do mapa seria efeito colateral, não decisão. Com o time cheio a captura escapa e a criatura volta ao mapa, em vez de sumir em silêncio.

### HP persiste, e se recupera com o tempo

```
recuperação = 10% do HP máximo por minuto, fora de combate
              10 minutos do zero até cheio
```

**Só o HP atravessa.** Carga do Despertar, buffs e usos de golpe continuam começando do zero a cada batalha — são o arco de uma luta, não um orçamento administrado ao longo do dia. O HP é a exceção porque é o que transforma uma sequência de encontros numa expedição com custo: sem ele, seis criaturas são seis opções e nenhuma é um recurso.

A escala foi escolhida contra o cooldown de mineração (3 s) e o respawn de criatura (20–40 s). Recuperar é a coisa lenta do mapa, então voltar ao bioma custa tempo de verdade e mandar uma reserva inteira à frente vira decisão.

Consequências, todas deliberadas:

- **A capturada entra com o HP com que saiu da batalha.** Enfraquecer para capturar tem preço, e ele é pago depois, esperando.
- **Criatura caída regenera.** Desmaiar é interdição temporária, não estado terminal que precisa de item para sair. Se isso mudar, o `if` vai em `PlayerRoster.regenerate`.
- **Caída pode andar à frente no mapa** — ali ela é só uma criatura muito ferida. Quem barra desmaiada é o combate.
- **Time inteiro caído não abre combate.** O clique avisa e não engata, em vez de abrir um duelo travado na substituição sem ninguém para escolher.
- A regeneração não precisa de trava para não correr durante a luta: o mundo fica pausado, e nó pausado não processa.

**Mineração** — `F` coleta um mineral sorteado por:

```
chance(mineral) = normalizar(peso_classe × peso_bioma)

cooldown = 3 s / speedModifier da classe ativa
```

O **bioma** diz o que o chão tem; a **classe da criatura ativa** diz o que ela sabe achar. Os dois pesos vêm do bundle (`mining.rates`), e é a multiplicação que faz a troca de ativa ser sentida — no Mar raso (BIO-001), um Loricati tira âmbar fóssil 16,2 % das vezes contra 3,5 % de um Draconis, que em troca acha prata 11,8 % contra 0,8 %.

O `workFunction` de cada classe também dá o papel e o ritmo:

| Classe | Papel | Ritmo | Especialidade |
|---|---|---|---|
| Loricati | escavadora | ×1.0 | âmbar fóssil, pedra, ferro |
| Theria | tuneladora | ×1.1 | carvão, cobre |
| Draconis | prospectora | ×0.9 | cristais elementais, prata |

A fórmula vive em `scripts/data/mining_table.gd`; `BestiaryData` só indexa o bundle. É a mesma separação que existe entre `CombatMath` e os dados de combate — **nenhum peso, nome ou taxa de minério está escrito em código.** Balancear mineração é `POST /mining-rates` no bestiário e re-exportar, não um commit aqui.

`scripts/data/ore_table.gd` — que carregava cinco minérios inventados em constante — foi removida quando o export passou a trazer o bloco `mining`.

**Painéis** — bolsa e inventário no canto superior esquerdo, criatura ativa no superior direito (status + perfil de mineração + os três minerais mais prováveis para ela ali). Todos somem durante o combate e a negociação, e voltam ao fechar.

## Economia

Mineração passou a ter escoadouro. O **Curador Sarn** (`NPC-001`) fica no PZ-01: clique nele de perto e a loja abre como overlay, com o mundo congelado — mesmo enquadramento do duelo, e sem zoom de câmera, porque numa negociação o que importa é a tabela.

| Tecla | |
|---|---|
| `Tab` | alterna comprar / vender |
| `1`–`9` | negocia uma unidade |
| `Esc` | sai |

```
preço de venda = floor(value × sellRatio), com piso de 1
```

O *spread* entre comprar e vender é a margem do comerciante, e é o que impede o loop de comprar e revender com lucro — o banco recusa `sellRatio` fora de (0, 1). O piso de 1 existe para mineral barato não arredondar para zero: item que não vale nada é lixo que nunca sai do inventário.

**Nenhum preço está em código.** `item_stats.value` no bestiário, `economy_rules` para moeda/bolsa inicial/margem, `merchant_offers` para o catálogo de cada comerciante — com `price` nulo cobrando o valor base, o que faz um segundo vilarejo mais caro custar dado em vez de código.

**Itens que fazem algo** — `effectCode` é o switch que o Godot roda, mesmo contrato que `abilities` já tinha:

| Categoria | Efeito | O que faz |
|---|---|---|
| `capture` | `capture_bonus` | multiplica a chance de captura |
| `heal` | `heal_percent` | recupera % do HP máximo |
| `mineral` | `none` | mercadoria pura |

As **resinas** de captura entram no duelo pelo `C`: com resina em mãos ele abre a lista, sem resina captura direto — menu de uma opção só é cerimônia. A resina se gasta no arremesso, dê certo ou não; devolvê-la em caso de falha faria tentar de novo custar nada, e a escolha entre a resina cara e a barata deixaria de existir.

O gancho `item_bonus` já existia em `BattleAction.capture()` desde a primeira versão da batalha, e nunca teve dado alimentando ele. Só faltava o item.

**Duelo** (`scenes/duel.tscn`) — aberto pelo encontro, entra com **o time inteiro**. Abrível sozinho com `F6` para playtest, e aí sorteia uma criatura só, porque sem mundo não há time.

| Tecla | |
|---|---|
| `1`–`6` | usar golpe — ou **escolher o slot**, quando a lista do time está aberta |
| `S` | abrir/fechar a lista de troca |
| `E` | Despertar Ancestral (quando a carga enche) |
| `C` / `F` | capturar / fugir |
| `R` | novo duelo |
| `Esc` | voltar ao mapa |

O número tem dois significados, e o painel de ações troca de conteúdo junto — então nunca fica ambíguo para quem está olhando.

**Trocar custa a rodada** e tem prioridade 6, acima de quase todo golpe: recuar uma criatura de pé é uma jogada, e o adversário ataca no intervalo. Sair de campo reverte o Despertar — a transformação é do momento, não um estado que se guarda no banco.

**Substituir quem caiu é de graça.** A rodada trava até alguém entrar, e nenhuma outra tecla responde — capturar ou fugir com a criatura desmaiada ainda em campo não é jogada, é brecha. Cobrar um turno pela substituição puniria duas vezes o mesmo golpe. Por isso `Battle.replace_active` existe separado de `_do_switch`: além do design, há um motivo mecânico — `resolve_round` pula o ator desmaiado, então uma ação de troca emitida pela ativa caída nunca chegaria a executar.

Derrota só acontece quando **o time inteiro** cai.

É instrumento de playtest, não a UI do jogo: texto puro, porque o que precisa ser avaliado é o *ritmo* — se cinco rodadas dão espaço tático, se o Despertar chega na hora certa, se a vantagem elemental é sentida.

### Testes

Duas suítes headless, sem dependência de editor:

```powershell
$godot = "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.1-stable_win64_console.exe"

& $godot --headless --script res://scripts/dev/test_data.gd     # contrato de dados + fórmulas
& $godot --headless --script res://scripts/dev/test_world.gd    # input, câmera, cena
& $godot --headless --script res://scripts/dev/test_battle.gd   # máquina de turnos
& $godot --headless --script res://scripts/dev/test_playable.gd # a cena rodando de verdade
& $godot --headless --script res://scripts/dev/test_duel_screen.gd  # duelo jogado por tecla
& $godot --headless --script res://scripts/dev/test_encounter.gd    # spawn, encontro, captura, overlay
& $godot --headless --script res://scripts/dev/test_mining.gd       # mineração, troca de ativa
& $godot --headless --script res://scripts/dev/test_team.gd         # HP persistente, regen, time em combate
& $godot --headless --script res://scripts/dev/test_companion.gd    # a companheira segue, nao acompanha
& $godot --headless --script res://scripts/dev/test_merchant.gd     # o laço da economia
```

`test_playable.gd` é o único que sobe a árvore de cena com física ativa e injeta input. Responde "dá para jogar?" em vez de "as contas fecham?" — e foi ele que pegou o corpo andando de costas, que nenhum teste de lógica isolada veria.

`test_data.gd` é o guarda do contrato com o bestiário: se o formato do bundle mudar, se uma fórmula sair do lugar ou se o export deixar passar uma criatura sem stats, estoura ali em vez de virar bug de runtime. Rode depois de todo `game:export`.

Ele também exige o bloco `mining` — minerais nomeados, toda classe do elenco com pesos e perfil de trabalho, nenhum peso apontando para mineral inexistente. O jogo *sobe* sem mineração (só avisa, porque combate não depende de minério), mas um export sem ela é um export velho, e é aqui que isso tem de doer, não numa tecla `F` que não faz nada.

`test_encounter.gd` cobre o loop completo de encontro — spawn → clique → batalha → vitória (remoção + respawn) → captura (remoção sem respawn + card do jogador).

`test_mining.gd` cobre a `MiningTable` (distribuição normalizada, especialidade por classe, amostragem sobre 4.000 sorteios, perfil de trabalho), o `PlayerRoster` (captura vira reserva, troca não reordena, teto de slots) e o fluxo no `WorldRoot`. A asserção que importa é a de ponta a ponta: trocar a ativa por uma criatura de outra classe muda a companheira, a distribuição de minério **e** o cooldown, os três de uma vez. Se um dia essa falhar, a fórmula parou de ler um dos dois lados e o jogo ficou igual com qualquer criatura à frente.

Trocar a ativa por outra da mesma classe passaria em tudo sem provar nada — por isso o teste usa um Draconis contra o starter Loricati, de propósito.

`test_merchant.gd` fecha o laço: minerar produz, o comerciante compra, a bolsa paga, e o que se compra faz alguma coisa. A asserção que mais importa é negativa — **nenhum consumível pode ser minerável**. Enquanto todo item era minério, o export mandava a tabela inteira para `mining.items`; a primeira resina cadastrada teria virado minério de chão. O filtro por categoria conserta, e este teste é o que impede alguém de removê-lo.

Também prende o "tudo ou nada" das duas pontas: sem saldo, nem a bolsa nem o inventário se mexem; vender o que não se tem não credita nada.

`test_companion.gd` separa "seguir" de "estar preso". A diferença é fácil de descrever e fácil de perder de vista, então o teste prende cada metade: não parte no mesmo quadro do comando, não orbita quando o jogador gira parado, não corta a diagonal na curva, e se orienta pela própria marcha em vez de copiar a do jogador. O "jogador" ali é um `Node3D` movido à mão em passos fixos — sem física nem input, porque o atraso de largada é da ordem de um oitavo de segundo e o jitter do motor esconderia justamente essa margem.

`test_team.gd` responde "uma expedição custa alguma coisa?". Não testa `hp = hp - dano`; testa a cadeia inteira — sair ferido de uma batalha, entrar ferido na próxima, e a espera no mapa sendo o único jeito de desfazer isso. Inclui a armadilha da regeneração fracionária: 10% de 84 HP por minuto dá 0,023 HP por quadro a 60 fps, e sem acumulador a cura inteira desaparece no arredondamento. O teste roda o mesmo minuto em passo de segundo e em passo de quadro e exige que os dois cheguem ao mesmo lugar.

`scripts/dev/setup_project.gd` gerou o input map e a cena inicial. É andaime de bootstrap — daqui em diante a edição normal é pelo editor.

### Sonda de balanceamento

```powershell
& $godot --headless --script res://scripts/dev/balance_probe.gd
& $godot --headless --script res://scripts/dev/balance_probe.gd -- 0.22 3 3.0
```

Simula o elenco inteiro lutando contra si mesmo (2.600 batalhas) e reporta taxa de vitória por criatura, duração média e quanto o Despertar Ancestral realmente vira o jogo. Não falha nem afirma nada — é leitura, para tuning sair de números em vez de impressão.

Os três argumentos opcionais sobrescrevem, nesta ordem: constante de dano, duração do Despertar, escala de enchimento da carga. Servem para medir o efeito de uma mudança **antes** de gravá-la no bestiário.

## Assets 3D

Os modelos servidos pelo app web estão comprimidos com **Draco**, que é otimização de entrega para browser. **Para o jogo, importe o `.glb` mestre sem compressão** — o Godot recomprime no formato dele na importação, e o Draco só adiciona um passo de decodificação e um ponto de falha.

Orçamento por asset, conforme `direcao-3d-arte`:

| Papel | Triângulos | Textura |
|---|---|---|
| Chefe/hero | 5k–8k | 1024² |
| Regular | 2k–4k | 512² |
| Enxame | 500–1.5k | 256² |

Oito loops de animação obrigatórios por criatura a 24 fps: `idle`, `walk`, `run`, `attack_primary`, `attack_secondary`, `hurt`, `death`, `victory`.

Criaturas Loricati usam **rig flutuante** — sem rig locomotor por perna, deslizamento com bob vertical de ~5 cm. Cobre ~60% do elenco atual.

Modelos-fonte ainda não estão versionados aqui: 8–27 MB cada bloqueiam o histórico para sempre. Configurar `git-lfs` antes de commitar o primeiro.

## Convenção de escala

**1 metro real = 1 unidade Godot.** Escala real, sem exagero dramático — um trilobita de 15 cm aparece pequeno e um Arthropleura de 2,5 m aparece grande.
