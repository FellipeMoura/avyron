# Avyron

Jogo 3D de coleção de criaturas com tema paleontológico, em Godot.

Câmera isométrica ortográfica **travada em 30° de inclinação e 45° de azimute**. Exploração em tempo real, **combate por turnos** (1v1 com troca livre, disputado no mesmo espaço do mapa, sem corte para arena).

O ângulo é travado; o **zoom** não. `IsoCamera.base_size` (17,15) é a única manopla — batalha e chefe são proporções dele (`×0,875` e `×1,25`), de propósito: o duelo é o mesmo enquadramento um pouco mais fechado, não uma segunda câmera com vida própria. Mexer no `base_size` move os três juntos.

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

**Mapa** (`scenes/main.tscn`) — WASD anda, shift corre, **F minera**, **T abre o time**, **E abre o set do jogador**, **V esconde/reexibe a bolsa**, câmera isométrica travada seguindo com lookahead. O cenário do PZ-01 (ambiência subaquática + recifes) é vestido em runtime por `MapDressing.apply`, e o chão chapado da cena é substituído pelo relevo do `MapTerrain` — ver "Assets 3D". A **criatura ativa** do jogador (starter, `CRT-002` por padrão) segue atrás dele — puramente visual, sem colisão nem clique; corpo rigado anima `Idle`/`Walk` pela marcha, cápsula usa o bob leve.

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

### A encenação do confronto

Como o combate acontece no mesmo espaço, o par que aparece na luta é o par que a exploração deixou ali: a companheira atrás do domador e a selvagem onde a perseguição parou — de costas, colados ou a oito metros. `BattleStaging` corrige isso enquanto o duelo dura: os dois se **encaram** e convergem para a distância de duelo, aproximando-se se estiverem longe e afastando-se se estiverem perto demais. O **domador** entra na composição atrás da própria criatura, virado para o adversário junto com ela.

```
distância = (raio(a) + raio(b) + 0,8 + (tamanho_a + tamanho_b) × 0,35) × 2,5
            limitada a [2,5 ; 17,5] m

domador   = (raio(criatura) + raio(jogador) + 1,2) × 1,5, atrás dela no eixo
```

Somar os **raios** é o que faz a conta funcionar em escala real: o vão que se vê é sempre o mesmo, seja o par dois trilobitas de 15 cm ou dois Arthropleura de 2,5 m. Medir de centro a centro sem eles daria bichos grandes sobrepostos com o número que separa dois pequenos. A parcela proporcional existe pela razão inversa — um par gigante precisa de mais ar entre os corpos para a mesma leitura de "frente a frente".

O `× 2,5` do par e o `× 1,5` do domador são **enquadramento, não geometria**. A soma dos raios mais a folga dá o ponto em que dois corpos apenas se livram — correto e cenicamente errado: lido de cima, em projeção ortográfica, um par nessa distância parece agarrado. Os multiplicadores abrem o vão até a leitura certa, e foram escolhidos olhando a cena. Os dois multiplicam o resultado **inteiro**, e os limites acompanham: aplicá-los só à folga faria o par grande crescer proporcionalmente menos que o pequeno, o oposto do que a distância precisa fazer.

`TRAINER_SPREAD` era `3,0`; caiu pela metade (`1,5`) a pedido, para aproximar o domador da própria criatura em combate — o resto da fórmula (raios, `TRAINER_GAP`) não mudou, então o recuo inteiro só encolheu, não a leitura de "quem é quem".

**Consequência de enquadramento:** a câmera segue o `Player`, que está numa das pontas da composição. Com o par a ~8,9 m e o domador agora ~3,25 m atrás da própria criatura (era 6,5 m), o adversário fica a ~12,15 m do centro do quadro — era 15,4 m. O `base_size` aberto para 17,15 levou a batalha junto (15,01): ao longo do eixo de visão a projeção comprime por `sin(18°)`, e 12,15 m viram ~3,75 m contra 7,5 m de meia-altura, com folga; perpendicular a ele não há compressão, e 12,15 m já cabem dentro dos 13,35 m de meia-largura a 16:9 — o caso que antes estourava (15,4 > 13,35) agora não estoura mais neste exemplo.

A correção definitiva continua sendo apontar a câmera para o **ponto médio dos dois combatentes** enquanto a batalha dura — `IsoCamera.set_target` já existe, e o ponto médio é justamente o que a correção simétrica da encenação preserva, então seria um alvo estável e livre de depender do ângulo. Reduzir o recuo do domador é mitigação, não a correção: um par grande o bastante ainda pode voltar a estourar a borda perpendicular, só que precisa de um par bem maior que o exemplo medido aqui para chegar lá agora.

O raio do jogador é lido da forma de colisão em `main.tscn`, não de uma constante — duas medidas do mesmo corpo discordariam no dia em que uma delas mudasse.

Quatro decisões que o teste prende:

- **Pode mexer na posição direto porque o mundo está pausado.** Nó pausado não processa, então a máquina de estados da `CreatureActor` e a trilha da `CompanionActor` estão as duas congeladas; `BattleStaging` roda com `PROCESS_MODE_ALWAYS`, como a câmera, e tem controle exclusivo dos dois corpos. É o que dispensa física, colisão e trava de prioridade. A encenação é liberada **antes** de o mundo voltar a andar, senão perseguição e trilha disputariam o mesmo `global_position` com ela.
- **A correção é metade para cada um.** O ponto médio não se move, então a briga acontece onde eles se encontraram em vez de escorregar para o lado do mais lento — e nenhum dos dois faz todo o trabalho, que é o que faria a cena ler como "um foge" em vez de "os dois se medem".
- **O domador fica de fora dessa simetria.** O posto dele é *derivado* da posição da criatura, não negociado com ninguém: puxá-lo para o cálculo faria o ponto do encontro escorregar na direção de quem está só assistindo. Ele também anda mais rápido que os combatentes (3,0 contra 2,0 m/s) — a marca dele está presa a um corpo que também se move, e com o mesmo ritmo ele nunca a alcançaria.
- **Só o yaw e o plano.** Os três corpos apoiam o Y em regras próprias — a selvagem sobe meia cápsula, a companheira fica no chão com o mesh deslocado, o domador fica no centro da própria cápsula — e escrever altura ali desfaria as três.

Uma zona morta de 12 cm em torno da distância ideal impede o tremor a dois, pelo mesmo motivo que `CompanionActor.STOP_DISTANCE` existe. E o eixo do confronto é lembrado de um quadro para o outro: dois corpos exatamente sobrepostos não têm direção entre si, e sem essa memória o afastamento escolheria um rumo diferente a cada quadro.

**Ciclo de vida no mapa** — vencer o combate remove o adversário do mapa, joga um slot de respawn na fila do `CreatureSpawner`, sorteia os drops dele (ver [Nível e XP](#nível-e-xp)) e concede XP à criatura que terminou a luta. Depois de 20–40s, o slot vira uma criatura nova (espécie e posição sorteadas do pool do bioma). Fuga e derrota do jogador liberam a criatura de origem para ser reengajada. **Captura** remove o adversário sem respawn, o põe no time como reserva no próprio nível que tinha no encontro, e concede XP de captura ao relicário equipado.

## Time e mineração

**A criatura ativa amarra os três sistemas.** Quem está à frente no time é a mesma criatura em toda parte: anda ao lado do jogador, entra no duelo, e — pela **classe** dela — decide o que a mineração produz e em que ritmo. Trocar quem vai à frente não é ajuste de menu; muda o que sai do chão no próximo `F`.

**Time** (`T`) — a janela lista a ativa e as reservas com status (HP atual, ATQ/DEF/VEL e perfil de mineração). Clique numa reserva, ou `1`–`6`, para mandá-la à frente. É a única peça de HUD do mapa que aceita clique — todo o resto usa `MOUSE_FILTER_IGNORE` para não roubar o clique de seleção de criatura. Não pausa o jogo.

**Curar** (`I`, dentro da janela) — ver [Itens de cura](#itens-de-cura), abaixo.

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

### Nível e XP

Cada criatura sobe de nível **sozinha** — não existe mais um nível de encontro achatado pro time inteiro. `PlayerRoster` guarda nível e XP por membro; o teto de HP de cada uma deriva do próprio nível (`stats_at_level`), não de um valor único do mundo.

```
xpTotal   = floor(xpYield_do_derrotado × nível_do_derrotado / xpYieldDivisor)
xpToNext  = floor(xpCurveBase × nível ^ xpCurveExponent)
custo     = itemCostBase + floor(nível / itemCostLevelStep)   # unidades do material
```

**`xpTotal` é um pool fixo, repartido entre quem participou** — não mais "só a finalizadora leva tudo". `Battle` registra participação de cada slot do time ao longo da luta inteira (`_xp_participation`, indexado por posição, não por quem terminou em campo): entrou em ação válida ou levou golpe hostil em campo, mesmo que tenha sido trocada depois. Trocar mais criaturas nunca cria XP — o pool não muda de tamanho, só de quantas mãos passa.

```
contribuição_i = dano_causado_efetivo_i + dano_sofrido_efetivo_i   # sem overkill
parcela_i = xpTotal/participantes × 0.2 + (xpTotal × 0.8) × contribuição_i / Σcontribuição
```

`ProgressionMath.distribute_xp` calcula as parcelas (piso por arredondamento de maior resto, soma sempre bate com `xpTotal` exatamente) — um participante só leva tudo; contribuição total zero (ninguém causou nem sofreu dano) reparte igual entre quem participou. O `0.2`/`0.8` é **placeholder de tuning** (`ProgressionMath.XP_BASE_SHARE_RATIO`), não decisão final. Cada participante passa individualmente por `PlayerRoster.grant_xp_at` — mesmo gate de sempre, ver abaixo — e a mensagem final lista uma linha por criatura (`Nome +X XP`).

Subir de nível pede as duas condições ao mesmo tempo, igual ao Relicário: **XP cheio e o material da própria classe da criatura** que sobe (`ITM-019` Quitina Fossilizada para Loricati, `020` Presa Fóssil para Theria, `021` Escama Fóssil para Draconis) — o material vem de **drops** de combate, não do comerciante. Sem o material na bolsa, a barra trava no teto em vez de estourar; o próximo ganho de XP (a próxima vitória) resolve sozinho assim que o jogador tiver o item. `PlayerRoster.grant_xp_at` e `PlayerRelic.grant_capture_xp` compartilham a mesma curva (`ProgressionMath`), extraída quando o segundo consumidor apareceu.

**Drops** — criatura derrotada em combate (não capturada — capturar não a mata) rola cada entrada de `creature.drops` **independentemente** (`LootTable.roll`): zero, um ou vários itens na mesma vitória, sem relação entre as chances. O material de subida de nível é só mais um item nessa lista, com a classe do **derrotado** decidindo qual material cai — nunca a de quem venceu. `WorldRoot._grant_drops` joga o que caiu direto na bolsa e mostra uma mensagem; nada cai se o roll não der em nada, e a HUD fica quieta.

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

**Painéis** — bolsa e inventário no canto superior esquerdo, criatura ativa no superior direito (status + perfil de mineração + os três minerais mais prováveis para ela ali). Todos somem durante o combate e a negociação, e voltam ao fechar — exceto a bolsa se o jogador pediu para escondê-la com `V`: essa escolha é dele, não do overlay, e sobrevive ao fechar loja/posto/duelo (`WorldRoot._inventory_hidden`).

**Set do jogador** (`E`, `player_set_window.gd`) — janela central somente-leitura com o que está equipado. Hoje só tem uma seção, o Relicário (nome, nível, XP, afinidade — "—" quando neutra, slots, taxa de captura); outras peças do set entram como novas seções aqui, não como janelas novas. Diferente do posto do relicário: o posto (`Tab`, ponto fixo do mapa) é onde o equipamento se *gerencia* (depositar/retirar/trocar de modelo); esta janela é só a *visão* dele, de qualquer lugar. Fecha com `Esc`, mutuamente exclusiva com a janela do time (`T`) — as duas são overlays centrais e se sobreporiam.

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
| `heal` | `heal_percent` | recupera % do HP máximo |
| `mineral` | `none` | mercadoria pura |

`capture` é categoria legada: os consumíveis de captura (as antigas resinas) saíram do catálogo quando a captura passou a ser resolvida pelo **Relicário**.

### Relicário

Equipamento do domador — sem item consumido por tentativa. O que limita é a **capacidade de slots** do modelo equipado e o storage geral, não a bolsa. Foco do sistema: captura, afinidade de captura por elemento/classe, capacidade de slots, progressão própria de nível e identidade/especialização do domador — **não** bônus direto de status em combate (ver "Buff de combate", abaixo).

Todo jogador começa equipado com `RLC-000`, o **starter neutro**: sem elemento, sem classe, `slotCapacity = 2` — só para ensinar captura/gerenciamento antes da primeira especialização (fora de escopo aqui: prevista como recompensa de arena). `WorldRoot._pick_starter_relic()` procura no bundle por um modelo sem elemento e sem classe em vez de fixar um código; se o catálogo algum dia subir sem esse modelo, o jogador entra sem relicário equipado e um `push_warning` explica o porquê em vez de falhar quieto. `RLC-001/002/003` seguem no catálogo como modelos especializados de exemplo (um por classe) — a distribuição deles pelo mundo continua fora de escopo.

**Captura** entra no duelo pelo `C` e é direta — sem menu: com um relicário equipado ele resolve a tentativa na hora, e sem relicário a tecla recusa com aviso. `BattleAction.capture()` recebe a taxa e o elemento/classe do relicário (`relic.capture_rate()`, `relic.element_code()`, `relic.class_code()`), não um bônus de item; a fórmula vive em `scripts/data/relic_math.gd` e não tem termo de HP nem de Despertar Ancestral — decisão do redesenho, não omissão.

```
relicRate  = baseCaptureRate + (nível - 1) × captureRatePerLevel
resistance = 256 - catchRate
base%      = (relicRate / resistance) × 100

final% = clamp(base%
           + sameElementBonusPct           (elemento do relicário == elemento da criatura)
           + sameClassBonusPct             (classe do relicário == classe da criatura)
           - elementDisadvantagePenaltyPct (elemento do relicário em desvantagem)
         , captureFloorPct, captureCeilPct)
```

**Progressão** — uma barra de XP própria, alimentada só por captura bem-sucedida (tentativa fracassada não gera XP). Ao encher, o level-up consome uma unidade do **material da própria classe do relicário** (`ITM-019`/`020`/`021`, o mesmo material que a subida de nível de criatura usa) — sem o material na bolsa, a barra trava exatamente no teto até o jogador conseguir o item, em vez de estourar em silêncio. Sobe mais de um nível numa chamada só se a XP e o material derem.

**Buff de combate — removido.** O Relicário não concede mais bônus de ataque nem qualquer outro status direto em batalha; `DuelScreen._apply_relic_buff` e o uso de `Combatant.attack_modifier` pelo relicário saíram do duelo. `relic-stats.combatBuffBase`/`combatBuffPerLevel` continuam existindo no catálogo (não removidos por ficarem sem consumidor — só desligados; `RLC-000` já sobe com os dois em `0`), porque outras peças do futuro set do jogador é que devem assumir buffs de combate, Despertar, troca, exploração etc. — não o Relicário.

**Posto do relicário** — ponto fixo no mapa (`RelicStationActor`, mesmo padrão de clique-para-interagir do comerciante), com quatro modos (`Tab` circula): status do equipado, depositar um ativo no storage, retirar um guardado, e trocar de modelo — só habilitado com o time ativo **vazio**, forçando "esvaziar os slots antes de trocar" como o design exige. Sem sistema de posse ainda, a troca deixa escolher qualquer modelo do catálogo — o mesmo furo que a aquisição já é, só tornado visível aqui.

`PlayerRoster` tem três níveis por causa disso: **ativo** (limitado por `slotCapacity`, via `set_capacity()`), **storage** (sem limite de código, só acessível no posto) e o HP/regeneração que já valiam para os dois. Time cheio na hora da captura continua fazendo a captura escapar, exatamente como antes — só que "cheio" agora depende do relicário equipado, não de um teto fixo de seis.

### Arena e Glifos

Documento de regra no bestiário: `glifos-e-portais`. Um **Glifo** é conquista permanente, não item — não se vende, não se craft, não dropa de combate comum. O **Campeão da Arena** (`NPC-002`, `role = duelist` no bestiário) é o primeiro duelista jogável: clicar nele de perto abre o mesmo `duel.tscn` de sempre, mas com `DuelScreen.is_wild = false` — `Battle` recusa captura nessa configuração (`_do_capture`), então a arena é sempre golpe contra golpe até alguém cair. Vencer concede o **Glifo Daleth**; `PlayerProgress.grant_glyph` é idempotente, então refazer a arena depois de já tê-lo não reanuncia nem duplica nada.

O **Guardião do portal** (`PortalGuardianActor`, silhueta em bloco alto — não repete cápsula nem torus de nenhum outro ator) barra a passagem até o jogador ter o Glifo. `can_pass()` é a checagem de lógica, separada de qualquer texto — o requisito vale mesmo se a mensagem nunca aparecesse. Sem cena de Titanor ainda para ir de verdade, atravessar com o Glifo só troca a mensagem do guardião por um aviso de que o destino não existe neste build; não há troca de cena.

**Primeiro estado que sobrevive a fechar o jogo.** Tudo o resto aqui (time, bolsa, relicário) é só em memória — `PlayerProgress` (autoload `Progress`) é o único que grava em disco, em `user://progress.cfg`, na hora que o Glifo é concedido. É formato pequeno de propósito (uma lista de códigos), mas a seção existe para crescer quando o resto do save também precisar persistir, sem precisar de arquivo novo.

Arena e guardião ficam no mesmo mapa único que existe hoje (PZ-01/Aetheris I) — posição de estande-in, mesmo raciocínio de `MERCHANT_SPOT`/`RELIC_STATION_SPOT`. O Glifo Zayin (Titanor) está definido no bestiário mas não tem arena nem guardião próprios ainda: não existe mapa de Titanor para prender neles.

### Itens de cura

Os **emplastros** (`ITM-016`/`017`/`018`) se usam **no mapa**, pela janela do time. `I` entra no modo de cura, e a janela vira uma máquina de três estados:

```
lista ──I──▶ escolher alvo ──criatura──▶ escolher item ──usa──▶ escolher alvo
  ◀───Esc────────┘                ◀────────Esc───────────┘
```

Escolher o alvo primeiro é o que a janela já é — uma lista de criaturas com o HP de cada uma — então o gesto natural é apontar o ferido e depois o remédio. Depois do uso ela volta a **escolher alvo**, não à lista: curar seis criaturas depois de um tombo não deve custar um `I` por criatura.

```
cura = floor(hpMáximo × effectValue / 100)      # heal_percent, com piso de 1
cura = effectValue                              # heal_flat
```

`heal_percent` traz **pontos percentuais** (30, 70, 100) — quem interpreta o número é sempre o `effectCode` ao lado, e ler o campo sozinho é o erro que transformaria o emplastro barato em cura infinita.

Decisões que o teste prende:

- **Cura nula não consome o item.** Alvo cheio é recusado antes de a bolsa ser tocada, e a lista de alvos apaga quem não tem ferimento. A cura é determinística, então gastar sem efeito seria só perder óbolos por um clique.
- **A lista mostra o efetivo, não o nominal.** `+100%` numa criatura a que faltam 12 HP restaura 12, e a linha diz `restaura 12 (desperdicia 92)`. Sem esse número o jogador queima a Seiva Primordial de 600 óbolos num arranhão.
- **Ordenado do fraco para o forte**: a tecla `1` cai sempre no item barato, então o gesto rápido nunca é o caro.
- **Caída pode ser curada** — mesma regra da regeneração por tempo: desmaiar é interdição temporária.
- **O filtro é por `effectCode`, não por categoria.** Categoria é como o bestiário organiza a vitrine; efeito é o que o jogo executa. Item de outra categoria que cure entra na lista sem ela saber que ele existe.

A janela não cura nem consome nada: ela emite `item_use_requested(slot, código)` e o `WorldRoot` — que é quem tem a bolsa **e** o time — mede, recusa, consome e aplica, nessa ordem.

Em combate ainda não se usa item. `BattleAction.Kind` continua com `ABILITY`, `SWITCH`, `CAPTURE`, `FLEE`; um `Kind.ITEM` com `_do_item` em `Battle` é o passo seguinte, e reaproveita `ItemEffects` inteiro.

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

Treze suítes headless, sem dependência de editor:

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
& $godot --headless --script res://scripts/dev/test_items.gd        # cura: formula, janela, bolsa
& $godot --headless --script res://scripts/dev/test_staging.gd      # os dois se encaram no duelo
& $godot --headless --script res://scripts/dev/test_glyphs.gd       # Glifo de arena, nunca de vitória selvagem
```

`test_playable.gd` é o único que sobe a árvore de cena com física ativa e injeta input. Responde "dá para jogar?" em vez de "as contas fecham?" — e foi ele que pegou o corpo andando de costas, que nenhum teste de lógica isolada veria.

`test_data.gd` é o guarda do contrato com o bestiário: se o formato do bundle mudar, se uma fórmula sair do lugar ou se o export deixar passar uma criatura sem stats, estoura ali em vez de virar bug de runtime. Rode depois de todo `game:export`.

Ele também exige o bloco `mining` — minerais nomeados, toda classe do elenco com pesos e perfil de trabalho, nenhum peso apontando para mineral inexistente. O jogo *sobe* sem mineração (só avisa, porque combate não depende de minério), mas um export sem ela é um export velho, e é aqui que isso tem de doer, não numa tecla `F` que não faz nada.

`test_encounter.gd` cobre o loop completo de encontro — spawn → clique → batalha → vitória (remoção + respawn) → captura (remoção sem respawn + card do jogador).

`test_mining.gd` cobre a `MiningTable` (distribuição normalizada, especialidade por classe, amostragem sobre 4.000 sorteios, perfil de trabalho), o `PlayerRoster` (captura vira reserva, troca não reordena, teto de slots) e o fluxo no `WorldRoot`. A asserção que importa é a de ponta a ponta: trocar a ativa por uma criatura de outra classe muda a companheira, a distribuição de minério **e** o cooldown, os três de uma vez. Se um dia essa falhar, a fórmula parou de ler um dos dois lados e o jogo ficou igual com qualquer criatura à frente.

Trocar a ativa por outra da mesma classe passaria em tudo sem provar nada — por isso o teste usa um Draconis contra o starter Loricati, de propósito.

`test_merchant.gd` fecha o laço: minerar produz, o comerciante compra, a bolsa paga, e o que se compra faz alguma coisa. A asserção que mais importa é negativa — **nenhum consumível pode ser minerável**. Enquanto todo item era minério, o export mandava a tabela inteira para `mining.items`; o primeiro consumível cadastrado teria virado minério de chão. O filtro por categoria conserta, e este teste é o que impede alguém de removê-lo.

Também prende o "tudo ou nada" das duas pontas: sem saldo, nem a bolsa nem o inventário se mexem; vender o que não se tem não credita nada.

`test_companion.gd` separa "seguir" de "estar preso". A diferença é fácil de descrever e fácil de perder de vista, então o teste prende cada metade: não parte no mesmo quadro do comando, não orbita quando o jogador gira parado, não corta a diagonal na curva, e se orienta pela própria marcha em vez de copiar a do jogador. O "jogador" ali é um `Node3D` movido à mão em passos fixos — sem física nem input, porque o atraso de largada é da ordem de um oitavo de segundo e o jitter do motor esconderia justamente essa margem.

`test_team.gd` responde "uma expedição custa alguma coisa?". Não testa `hp = hp - dano`; testa a cadeia inteira — sair ferido de uma batalha, entrar ferido na próxima, e a espera no mapa sendo o único jeito de desfazer isso. Inclui a armadilha da regeneração fracionária: 10% de 84 HP por minuto dá 0,023 HP por quadro a 60 fps, e sem acumulador a cura inteira desaparece no arredondamento. O teste roda o mesmo minuto em passo de segundo e em passo de quadro e exige que os dois cheguem ao mesmo lugar.

`test_items.gd` responde "comprar cura serve para alguma coisa?". Antes dele os emplastros eram compráveis, vendíveis e precificados, e **nada os consumia** — o laço econômico terminava numa vitrine. A asserção que mais importa também é negativa: **cura nula não consome o item**, medida nos dois níveis (o `WorldRoot` recusa antes de tocar na bolsa, e a lista de alvos já apaga quem está cheio). Prende também que `30` em `heal_percent` são trinta por cento e não trinta vezes, e que um mineral na bolsa não aparece na lista de cura.

`test_staging.gd` responde "a imagem mostra o que o overlay narra?". A asserção que mais importa é a da **simetria**: o ponto médio entre os dois não pode escorregar, porque é onde eles se encontraram — se um dia um dos lados passar a fazer todo o trabalho, é ela que pega. A do domador é a mesma medida por outro lado: montar a cena **com** e **sem** ele e exigir que o ponto do encontro caia no mesmo lugar. A segunda é a única que prova fiação em vez de geometria: uma fase inteira do teste espera **quadros reais do motor**, sem chamar `step`, com o mundo pausado. Sem ela, `PROCESS_MODE_ALWAYS` poderia cair e todo o resto continuaria verde.

Ela também prende que o encaramento é medido **no plano**: a bancada põe os dois corpos em alturas diferentes de propósito (companheira no chão, selvagem meia cápsula acima), e um produto escalar em 3D mediria a inclinação entre eles em vez do encaramento — foi exatamente assim que a primeira versão do teste falhou com `dot 0.913`, que é o cosseno de 1,4 m de desnível e não um erro de yaw.

`test_glyphs.gd` responde "só arena concede Glifo?". `PlayerProgress` é `Node`, não `RefCounted`, então o teste é o primeiro a precisar de `free()` explícito nas instâncias — sem isso o `ObjectDB` vaza em silêncio e só aparece no aviso de saída do processo. Isola o save de teste do save real do jogador (`use_path_for_test`, nunca `user://progress.cfg`) e prova as duas metades: uma batalha `is_wild = false` vencida concede o Glifo (idempotente num refight), e uma vitória selvagem — mesmo par, mesma semente — nunca chama `grant_glyph`. A metade que fica sem cobertura headless é a árvore de cena inteira (clique no duelista, `WorldRoot._on_arena_engaged`); testar isso pediria o padrão `_initialize`/`_process` que `test_playable.gd` usa, não o `_init` síncrono que basta aqui.

`scripts/dev/setup_project.gd` gerou o input map e a cena inicial. É andaime de bootstrap — daqui em diante a edição normal é pelo editor.

### Sonda de balanceamento

```powershell
& $godot --headless --script res://scripts/dev/balance_probe.gd
& $godot --headless --script res://scripts/dev/balance_probe.gd -- 0.22 3 3.0
```

Simula o elenco inteiro lutando contra si mesmo (2.600 batalhas) e reporta taxa de vitória por criatura, duração média e quanto o Despertar Ancestral realmente vira o jogo. Não falha nem afirma nada — é leitura, para tuning sair de números em vez de impressão.

Os três argumentos opcionais sobrescrevem, nesta ordem: constante de dano, duração do Despertar, escala de enchimento da carga. Servem para medir o efeito de uma mudança **antes** de gravá-la no bestiário.

## Assets 3D

O corpo de cada criatura vem do **`modelUrl` do bundle**, não de convenção de nome. `CreatureActor.model_path` resolve nesta ordem:

1. **`res://models/<caminho do modelUrl>`** — espelhado do bestiário pelo `pnpm game:export`, que copia todo `.glb` referenciado junto com o `bestiary.json`. Hoje são os placeholders animados do Quaternius (CC0), compartilhados N:1 — várias criaturas apontam o mesmo arquivo, e é o catálogo que decide qual corpo cada uma usa (botão "vincular/alterar modelo" na ficha do bestiário).
2. **`res://CRT-XXX.glb` na raiz** — legado dos modelos Meshy, sem animação. Só vale quando a criatura não tem `modelUrl` resolvível.
3. **Cápsula** colorida pelo elemento — o fallback de sempre.

Depois de um export com modelos novos, rode `--headless --import` (ou abra o editor) para o Godot importá-los antes de dar play.

**Props de bioma** chegam pelo mesmo export, em `models/biomes/` (preparados por `pnpm models:biomes` no bestiário). `megakit/` (Stylized Nature MegaKit do Quaternius, CC0) veste o terrestre: vegetação e pedras em escala real (CommonTree ~7 m) — samambaias escaladas 2,5–3× e cogumelos 3–4× dão a vegetação carbonífera do PZ-03; são `.gltf` com texturas **compartilhadas** de propósito (o Godot deduplica recursos por caminho; `.glb` embutiria uma cópia da casca em cada árvore). `aquatic/` (11 props gerados no Meshy) cobre o marinho do PZ-01: corais, algas e formações em `.glb` individuais, **normalizados em ~1×1×1 pelo Meshy** — a escala de cada peça é decisão da cena (recifes 2–5×, o arco 8–9× como landmark).

Quem aplica isso é **`scripts/world/map_dressing.gd`** (`MapDressing.apply`, chamado por `WorldRoot._ready`, mesmo padrão RefCounted/static do `WorldPopulator`): ambiência subaquática (fog azul `~0.011`, luz fria), landmarks fixos à mão (com colisão cilíndrica só nos maciços — o arco é passagem por baixo) e vegetação miúda espalhada com semente fixa, respeitando um raio livre em torno dos pontos do `WorldPopulator` e da origem do jogador. Layout é posição de cena, não de bestiário — o catálogo diz *o que* vive no mapa; o mundo diz *onde*.

### Relevo e solo

**`scripts/world/map_terrain.gd`** substitui em runtime o `Ground` chapado de `main.tscn` (mesmo nome de nó — o clique de mundo e o `test_world` continuam funcionando): uma grade de 61×61 a 1 m que gera malha, colisão (`HeightMapShape3D`) e a consulta `height_at` **da mesma fonte**, então visual, física e consulta nunca discordam. O desenho é deliberado:

- **Centro plano (altura 0) até `FLAT_RADIUS` = 16 m** — todo o gameplay que assume plano (POIs do `WorldPopulator`, origem do jogador, encenação de duelo) vive aí e continua correto sem mudar.
- **Colinas suaves (até 2,5 m, ruído com semente fixa) só na zona externa**, e um **rim de borda (+3,5 m)** que fecha a leitura do mapa na câmera ortográfica — relevo é apresentação com colisão, não labirinto.
- **Uma costa na borda -Z**: platô raso (+1,6 m, rampa entre z −16 e −21) reservado a NPCs e portais — comerciante e posto do Relicário vivem lá (`WorldPopulator`), o spawner não deixa criatura nascer na faixa (`MapTerrain.on_coast`, com margem para a deriva de patrulha) e o `MapDressing` não espalha bioma nela. O shader pinta a faixa emersa num tom seco (`color_coast`), com a base da rampa continuando molhada.
- Corpos com física (jogador, selvagens) seguem o relevo pela colisão; quem não tem física pergunta: a companheira (`terrain.height_at` no lugar do antigo `GROUND_Y`, que virou fallback de bancada), o spawner (nasce apoiado) e os props do `MapDressing`.

O **solo** é um shader próprio (`shaders/terrain_ground.gdshader`): dois tons misturados por ruído em espaço de mundo (sem UV) + um terceiro tom nas inclinações, com a paleta por mapa vinda de `MapDressing.ground_palette`. Armadilha registrada: a frente de um triângulo no Godot é a ordem **horária** — na ordem OpenGL (anti-horária) o chão inteiro é backface-culled e o mapa flutua sobre o fundo.

**Animação.** Os clipes chegam com o vocabulário normalizado na conversão do bestiário (`convert-placeholders.mjs`): `Idle`, `Walk`, `Run`, `Attack`, `Attack2`, `HitReact`, `Death`, mais extras por família — quadrúpedes têm `Eating`, voadores não têm `Walk` e seguem no `Idle` de flutuação. A criatura selvagem nasce em `Idle` e patrulha em `Walk`; a companheira troca de clipe pelo próprio ritmo de marcha e desliga o bob sintético quando o corpo tem rig. O importador de glTF não marca loop em nada, então `LOOPED_CLIPS` em `creature_actor.gd` marca só os clipes contínuos — nunca `Death`.

Orçamento por asset para os modelos definitivos, conforme `direcao-3d-arte`:

| Papel | Triângulos | Textura |
|---|---|---|
| Chefe/hero | 5k–8k | 1024² |
| Regular | 2k–4k | 512² |
| Enxame | 500–1.5k | 256² |

Loops mínimos por criatura definitiva, a 24 fps, **nos mesmos nomes do vocabulário normalizado** — o código já os consome por esses nomes: `Idle`, `Walk`, `Run`, `Attack`, `Attack2`, `HitReact`, `Death`. Extras como `Yes`/`No`/`Wave` (feedback de captura/vitória) são bem-vindos.

Criaturas Loricati usam **rig flutuante** — sem rig locomotor por perna, deslizamento com bob vertical de ~5 cm. Cobre ~60% do elenco atual.

Os `.glb` espelhados em `models/` são versionados via **git-lfs** (`.gitattributes` já cobre `*.glb`; confira `git lfs status` antes do commit — blob commitado direto fica no histórico para sempre). Os `CRT-XXX.glb` da raiz viraram peso morto de 8–27 MB cada desde que todo o elenco tem `modelUrl`; podem ser arquivados fora do repo. Quando os modelos definitivos voltarem (animados), importe o `.glb` mestre — o do bestiário serve texturas KTX2 otimizadas para browser, que não é o que o Godot quer.

## Convenção de escala

**1 metro real = 1 unidade Godot.** Escala real, sem exagero dramático — um trilobita de 15 cm aparece pequeno e um Arthropleura de 2,5 m aparece grande.
