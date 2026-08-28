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
| **Classe** | especialização de atributo da criatura — **não** linhagem. São cinco, com nomes ficcionais; quais existem e o que cada uma especializa vem do bundle (`classes[]`), não desta tabela |
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
Água → Fogo → Natureza → Terra → Eletricidade → Água
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
2. **Importar este repo.** Botão `Import` → aponte para `c:\code\fellipe\avyron\project.godot` → `Import & Edit`. Da segunda vez em diante ele já aparece na lista; duplo clique abre.
3. **Play.** `F5` (ou o botão ▶ no canto superior direito) roda a cena principal definida em `project.godot`, que é o mapa. Para rodar o duelo direto, abra `scenes/duel.tscn` na aba de cenas e aperte `F6` (roda **só** a cena atual).

Se pedir para escolher a Main Scene na primeira execução, aponte para `scenes/main.tscn` — está fixado no `project.godot`, mas versões novas do Godot às vezes perguntam mesmo assim.

**Mapa** (`scenes/main.tscn`) — WASD anda, **F minera**, **T abre o time**, **E abre o set do jogador**, **V esconde/reexibe a bolsa**, câmera isométrica travada seguindo com lookahead. O cenário do PZ-01 (ambiência subaquática + recifes) é vestido em runtime por `MapDressing.apply`, e o chão chapado da cena é substituído pelo relevo do `MapTerrain` — ver "Assets 3D". O jogo abre no topo da **ilha da arena**, no meio do mapa; o resto é mar, e se atravessa nadando. A **criatura ativa** do jogador (starter, `CRT-002` por padrão) segue atrás dele — puramente visual, sem colisão nem clique; corpo rigado anima `Idle`/`Walk`/`Run` pela marcha, cápsula usa o bob leve.

### A marcha e o clipe

Velocidade única, sem tecla de corrida: `WALK_SPEED` = 5,2 m/s. O nome é herança — **5,2 m/s é marcha de corrida**, já que um humano andando faz ~1,4 m/s — e era exatamente daí que vinha o deslize do jogador: o corpo viajava a 5,2 tocando o ciclo de `Walk`, calibrado num `WALK_SPEED` anterior de 4,0 e nunca remedido depois de ele subir 30%. Defasagem dessa ordem nenhum blend cobre.

A correção foi dar o **clipe certo à marcha**, não mexer na velocidade: `CharacterRig.update_motion` virou uma escada `Idle → Walk → Run` com limiar em 2,2 m/s, e o jogador está sempre acima dele. A escada mora no rig, e não no chamador, porque humano é UM sistema visual — um NPC que um dia passear a 1,5 m/s ganha o `Walk` pela mesma chamada que dá `Run` ao jogador. Trocar o literal por `"Run"` teria tirado o andar do sistema inteiro para consertar um corpo só.

A companheira ganhou a mesma escada pelo mesmo motivo: o teto dela é `WALK_SPEED × 1,12`, então ela acompanha um jogador que corre — e tocar `Walk` nessa marcha a faria deslizar ao lado dele exatamente como ele deslizava. Ela cai para `Walk` quando o corpo não tem `Run`, porque os placeholders variam.

Se ainda restar deslize, o ajuste seguinte é a **cadência** (`speed_scale` do `AnimationPlayer`), não o clipe nem a velocidade — os dois compõem, não são alternativas.

#### Nadar é o estado normal, não a exceção

O PZ-01 é o **leito de um mar**: fora dos dois trechos emersos está tudo debaixo d'água, e por isso o domador atravessa o mapa **nadando** e só fica de pé quando sobe a rampa da vila da costa ou a da ilha da arena. Medido na grade do terreno: **77,1% das células respondem "submerso"** pela regra abaixo (56,8% estão de fato abaixo da cota — a diferença são os recifes que passam da linha e continuam sendo recife).

Quem responde "estou na água?" é o terreno (`MapTerrain.submerged`), e a regra tem duas metades:

- **Fora da costa e da ilha, sempre submerso** — independentemente da altura. Um recife que sobe 2,5 m continua sendo recife. A leitura alternativa (testar só a cota) foi descartada com número na mão: 315 células do anel externo passam da linha por causa das colinas, e o jogador emergiria de pé no meio do recife em cada uma delas. Ilhota de verdade é **geografia declarada** (`on_coast`, `on_island`), não altura que calhou de passar da cota — por isso a ilha ganhou predicado próprio em vez de a regra afrouxar para todo mundo.
- **Na costa e na ilha, a altura decide** — são os dois lugares em que a rampa atravessa a superfície no meio da subida, exatamente como a névoa já conta.

A cota é a **mesma** que fragmenta a névoa (`MapDressing.PZ01_WATER_LINE` = 1,25 m), e essa igualdade é o contrato: nadar numa cota e trocar a murk noutra faria a imagem contradizer o corpo. A submersão é medida nos **pés**, não no centro do corpo — testar o centro o faria sair da água meio metro antes de o corpo sair.

Duas decisões do corpo submerso:

- **`Swim` também parado.** O kit traz um `Swim_Idle`, e ele fica de fora de propósito: é pose de boiar na **superfície**, com o corpo inteiro pendurado 1,41 m abaixo da origem do rig, contra 0,19 m do `Swim`. Alternar entre os dois faria o corpo subir e descer 1,2 m a cada parada — e, aqui, os pés do boiador entrariam no leito, porque a coluna d'água do PZ-01 não tem essa folga. Quem para embaixo d'água continua dando braçada para ficar no lugar, que é o que um corpo submerso faz.
- **A flutuação é constante, não medida.** `Swim` deita o corpo em torno da origem do rig — que são os pés —, então tocado cru o nadador arrasta a barriga no leito. `SWIM_LIFT` o põe pairando 0,9 m acima. Amarrar essa altura ao ponto mais baixo do esqueleto seria tentador e está errado: ele oscila ao longo da braçada, e o corpo quicaria ao contrário dos membros — o mesmo motivo que impede usar essa medida num ciclo de caminhada. Só a **borda** é interpolada (0,35 s ao entrar e sair d'água), casada com o crossfade do clipe.

O movimento não muda: mesma velocidade, mesma cápsula de colisão em pé, mesma física. Foi pedida a animação, e `WALK_SPEED` é o denominador da coleira da companheira — mexer nele desregula os dois de uma vez.



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

Como o combate acontece no mesmo espaço, o par que aparece na luta é o par que a exploração deixou ali: a companheira atrás do domador e a selvagem onde a perseguição parou — de costas, colados ou a oito metros. `BattleStaging` corrige isso enquanto o duelo dura: os três **andam** até os postos de batalha, apoiados no relevo, e param com os dois combatentes se **encarando** na distância de duelo — aproximando-se se estiverem longe, afastando-se se estiverem perto demais. O **domador** entra na composição atrás da própria criatura, virado para o adversário junto com ela.


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

Cinco decisões que o teste prende:

- **Pode mexer na posição direto porque o mundo está pausado.** Nó pausado não processa, então a máquina de estados da `CreatureActor` e a trilha da `CompanionActor` estão as duas congeladas; `BattleStaging` roda com `PROCESS_MODE_ALWAYS`, como a câmera, e tem controle exclusivo dos dois corpos. É o que dispensa física, colisão e trava de prioridade. A encenação é liberada **antes** de o mundo voltar a andar, senão perseguição e trilha disputariam o mesmo `global_position` com ela.
- **A correção é metade para cada um.** O ponto médio não se move, então a briga acontece onde eles se encontraram em vez de escorregar para o lado do mais lento — e nenhum dos dois faz todo o trabalho, que é o que faria a cena ler como "um foge" em vez de "os dois se medem".
- **O domador fica de fora dessa simetria.** O posto dele é *derivado* da posição da criatura, não negociado com ninguém: puxá-lo para o cálculo faria o ponto do encontro escorregar na direção de quem está só assistindo. Ele também anda mais rápido que os combatentes — a marca dele está presa a um corpo que também se move, e com o mesmo ritmo ele nunca a alcançaria. O teto do passo dele é `PlayerController.WALK_SPEED`, a mesma marcha com que ele corre pelo mapa: tomar posto correndo lê igual a correr, porque é o clipe `Run` nos dois casos.
- **Andar, não escorregar.** Os três corpos estão pausados e não conseguem se mexer sozinhos, então é a encenação que faz por eles as três coisas que separam caminhada de deslize: entrega a **marcha** (`staged_gait`, e cada corpo escolhe `Idle`/`Walk`/`Run`/`Swim` com a mesma escada da exploração), aponta o corpo **para onde ele vai** enquanto falta caminho — só nos últimos metros ele gira para encarar o adversário —, e **reencosta no chão** a cada passo. O ritmo é proporcional ao que falta, como a coleira da companheira: quem está longe parte correndo e chega andando, e a própria desaceleração produz `Run → Walk → Idle` sem ninguém orquestrar.
- **Escolher o clipe não basta: `AnimationPlayer` também é pausável.** Com o mundo parado ele não avança, e o clipe certo ficava **selecionado e congelado no quadro zero** — os três corpos atravessavam a cena numa pose estática, que é o deslize de volta por outra porta. Medido antes da correção: `current_animation_position` = 0,000 em todos os quadros da caminhada. `staged_animating` liga o modo `PROCESS_MODE_ALWAYS` no `AnimationPlayer` de cada corpo enquanto a encenação está na árvore, e o devolve quando ela sai — e ela sai **antes** de o mundo despausar. Ligar isso o tempo todo seria pior: numa tela de loja, uma criatura pega no meio do `Walk` andaria no lugar em vez de ficar parada.


#### O relevo, e por que a altura passou a ser assunto da encenação

Enquanto o mapa era plano, empurrar só X/Z era correto — a altura era zero em toda parte. Com `MapTerrain` deixou de ser, e o defeito era exatamente esse: **a selvagem nasce num raio de 22 m e a zona plana acaba em 16**, então a maioria dos duelos começa em ladeira.

Empurrar no plano ali enterra o corpo na colina, e como a física está pausada ninguém despenetra durante a luta. O jogador e a selvagem são `CharacterBody3D`: no `paused = false` o `move_and_slide` encontra a cápsula funda dentro do `HeightMapShape3D` e a expulsa — era isso que prendia o jogador no solo ou o arremessava. Medido no mundo real, numa linha de duelo que sobe o flanco: **o jogador terminava 0,99 m abaixo da superfície** (a cápsula inteira enterrada, já que ela mede 0,9 m do centro aos pés) e a companheira 0,33 m no ar. Com o reapoio, os três ficam em 0,00.

Cada corpo declara o próprio apoio (`staged_ground_offset`), porque as três regras divergem e sempre divergiram: a selvagem sobe meia cápsula, a companheira tem a origem *no* chão com o mesh deslocado no filho, o jogador apoia no centro da cápsula de colisão. Uma média entre as três deixaria um enterrado e outro flutuando.

Perto da borda havia um segundo defeito, pior: o posto do domador é derivado para **fora** do par — atrás da própria criatura, no sentido oposto ao adversário. Com o duelo engatado perto da borda de spawn, esse posto caía além dos ±30 m da malha, onde não há chão nenhum, e o jogador ia junto: literalmente cair do mapa. `MapTerrain.clamp_to_bounds` apara o **ponto de destino**, não só a posição escrita — um posto inalcançável deixaria o domador empurrando a parede para sempre, correndo no lugar, e o erro dele nunca zeraria.

**Sem terreno injetado nada disso roda e o Y fica intocado.** É o contrato antigo, e é o que mantém a bancada de `Node3D` solto da suíte medindo geometria pura sem ter de conhecer relevo — as asserções de "a altura não foi tocada" continuam válidas lá, e `_test_terrain` prende a regra nova com um `MapTerrain` de verdade.


Uma zona morta de 12 cm em torno da distância ideal impede o tremor a dois, pelo mesmo motivo que `CompanionActor.STOP_DISTANCE` existe. E o eixo do confronto é lembrado de um quadro para o outro: dois corpos exatamente sobrepostos não têm direção entre si, e sem essa memória o afastamento escolheria um rumo diferente a cada quadro.

**Ciclo de vida no mapa** — vencer o combate remove o adversário do mapa, joga um slot de respawn na fila do `CreatureSpawner`, sorteia os drops dele (ver [Nível e XP](#nível-e-xp)) e concede XP à criatura que terminou a luta. Depois de 20–40s, o slot vira uma criatura nova (espécie e posição sorteadas do pool do bioma). Fuga e derrota do jogador liberam a criatura de origem para ser reengajada. **Captura** remove o adversário sem respawn, o põe no time como reserva no próprio nível que tinha no encontro, e concede XP de captura ao relicário equipado.

### Pontos fixos do mapa

Comerciante, arena, posto do Relicário e guardião do portal são **um sistema só**, `InteractableActor`. Mecanicamente fazem a mesma coisa: são `StaticBody3D` porque o clique do mundo é um raycast físico, têm o mesmo alcance de interação (4,5 m), uma placa flutuante que diz "dá para interagir" sem ícone de HUD, e emitem `engaged` — sem conhecer tela nenhuma. Quem escuta decide o que abrir.

O que cada subclasse traz é só o que a distingue:

| | corpo | placa | estado próprio |
|---|---|---|---|
| `MerchantActor` | `CharacterRig` ou cápsula | cubo âmbar | código e ofertas do bestiário |
| `ArenaActor` | `CharacterRig` ou cápsula | cubo ember | oponente, nível, Glifo concedido |
| `RelicStationActor` | cápsula | anel (torus) | — |
| `PortalGuardianActor` | bloco alto | prisma | Glifo exigido, destino, `can_pass()` |

`CreatureActor` **não** herda daqui: ela responde por seleção e segundo clique, contrato diferente de "engata direto".

**O apoio no chão é o contrato que mais importa.** `ground_on_spot()` **soma** meia altura ao `y` do spot, que já é a altura do terreno naquele ponto. Atribuir daria o mesmo número só enquanto o ator estivesse em chão plano — e os quatro já divergiram nisso: comerciante e posto (na costa, elevada) somavam, arena e guardião (no centro plano) atribuíam, e os dois pares acertavam por coincidência de posição. Mover um deles exigia lembrar de editar o ator *e* o `WorldPopulator`, sem nada acusando a falta de um dos dois. Hoje é uma chamada só, e `test_merchant.gd` (`_test_actor_grounding`) reprova se alguém voltar a atribuir.

**Ator novo custa uma subclasse e nada mais.** `WorldRoot.handle_click_at` e `WorldSelection.pick_body` testam contra `InteractableActor`, não contra a lista de classes concretas — que eram duas listas mantidas à mão, e esquecer a segunda fazia o raycast devolver `null`: clique que não faz nada, sem erro.

### Telas e input

Toda tela do jogo cai em **uma de duas famílias**, e a escolha decide quem protege o mundo de responder por baixo dela.

| | Pausa a árvore | Mundo atrás | O que segura o input |
|---|---|---|---|
| Duelo, loja, posto do Relicário | sim | congelado | o pause |
| Janela do time (`T`), set (`E`), bolsa (`V`) | não | vivo | guarda explícito |

**Overlay modal** entra como `CanvasLayer` em `PROCESS_MODE_ALWAYS` e faz `get_tree().paused = true`. Nó pausado não recebe callback de input, então o `WorldRoot` simplesmente para de existir para o teclado e o mouse — é por isso que `F` não minera durante uma negociação. A tela sobrevive porque se declarou `ALWAYS`; o mundo não.

**Janela de HUD** não pausa nada: o HP continua regenerando, as criaturas continuam patrulhando. Por isso ela precisa de guarda escrito à mão — `elif keycode == KEY_F and not _roster_open()` é carga estrutural de verdade, não redundância.

`WorldRoot._modal_open()` é o ponto único que responde "tem modal por cima?". Ele existe para os pontos de entrada **públicos** (`handle_click_at`, `trigger_mine`, `toggle_roster_window`…), que são públicos porque teste headless não sintetiza mouse e por isso pulam o pause. Em jogo ele é a segunda linha; em teste é a única. Antes de 2026-08 esse predicado estava escrito à mão em dez lugares, em quatro composições diferentes que discordavam entre si sobre quais telas contavam — e nada acusava, porque o pause segurava tudo de qualquer jeito. Guarda que parece ser a proteção sem ser é pior que nenhum. `test_merchant.gd` (`_test_modal_guard`) prende o invariante.

## Time e mineração

**A criatura ativa amarra os três sistemas.** Quem está à frente no time é a mesma criatura em toda parte: anda ao lado do jogador, entra no duelo, e — pela **classe** dela — decide o que a mineração produz e em que ritmo. Trocar quem vai à frente não é ajuste de menu; muda o que sai do chão no próximo `F`.

### Bioma: consultado por posição

A fórmula de mineração é `normalizar(peso_classe × peso_bioma)` — o bioma diz o que o chão tem, a classe da criatura ativa diz o que ela sabe achar. Os dois pesos vêm do bundle.

**O bioma é resposta da POSIÇÃO do jogador**, desde 2026-08-28. Andar da costa para o recife troca o que a picareta entrega, sem menu nenhum — e o painel da criatura ativa mostra a troca acontecendo, com o nome do bioma acima da lista de minérios preferidos.

Quem responde é `scripts/world/map_biomes.gd` (`MapBiomes.biome_at(pos)`), alimentado por `maps[].biomeRegions` no bundle — a tabela `map_biome_regions` do bestiário, que descreve cada bioma como uma forma (`band`, `circle`, `rect`) e para na **primeira região que contém o ponto**. É a ordem que deixa uma região pequena e específica se sobrepor a uma grande e genérica sem recorte geométrico: a específica só precisa vir antes. A última do PZ-01 é um catch-all cobrindo o mapa inteiro, e é ele que garante cobertura total por construção.

**As coordenadas são normalizadas em ±1 sobre o meio-lado do mapa, não metros**, e essa escolha é o que faz a partição sobreviver a um redimensionamento do terreno: crescer o `MapTerrain.SIZE` reposiciona todas as fronteiras junto, na mesma proporção, sem reescrever uma linha de catálogo. Quem divide pelo meio-lado é o Godot; o bundle não sabe quantos metros o mapa tem, e não deve saber. O preço é que redimensionar é grátis mas **redesenhar não é** — mudar o mapa de tamanho sem que as fronteiras devam acompanhar exige reautorar a região.

O acoplamento que isso cria é medido, não confiado: as notas do catálogo amarram números normalizados a constantes do relevo (`-0.533` é o `COAST_RAMP_START` sobre o meio-lado de 30 m), e `test_data.gd` **varre o eixo perguntando onde o bioma troca** em vez de conferir o número. Mexer no `COAST_RAMP_START` sem reautorar a região descolaria a fronteira do bioma da rampa do terreno, e o sintoma seria o jogador subindo para o seco com a mineração ainda respondendo "mar raso".

`WorldRoot.DEFAULT_BIOME` continua existindo, mas mudou de papel: é o **fallback** para mapa sem partição autorada e para ponto fora de todas as regiões. Os dois casos são de dado, não de posição, e quem grita por eles é `_assert_biome_belongs_to_map()`, uma vez na abertura — a consulta em si roda todo quadro e é obrigada a ficar calada.

A armadilha que isso reabriu, e por que as travas ficaram: `MiningTable` trata **lado ausente por inteiro** como neutro (×1), de propósito — sem criatura ativa, o bioma decide sozinho. Um bioma sem taxa nenhuma não dá erro; a fórmula vira só-classe e a picareta continua entregando minério, com outra distribuição. Enquanto o mundo declarava um bioma só, bastava conferir aquele. Com a partição, o jogador pisa em **qualquer um**, então `test_data.gd` cobra taxas de todo bioma alcançável, e não só do declarado.

Três guardas, em três alturas:

| onde | o quê | porta |
|---|---|---|
| `export-game-data.mjs` | bioma do mapa que região nenhuma reivindica | aviso |
| `test_data.gd` | cobertura total, fronteira × relevo, taxas dos alcançáveis | reprova |
| `test_playable.gd` | o **mundo** responder por posição (sonda em três lugares) | reprova |

A separação entre as duas suítes é deliberada: `test_data` prova que a geometria das regiões está certa; `test_playable` prova que o `WorldRoot` está de fato perguntando. Um `current_biome()` correto com um cache que nunca acompanha passaria na primeira e deixaria a mineração presa no bioma da abertura — que era exatamente o estado anterior, e ele passava em tudo.

**A partição do PZ-01 está fechada** desde 2026-08-28: cinco biomas, **sete regiões**, cobertura total e nenhum bioma inalcançável. Sete e não cinco porque duas formas do desenho não cabem numa primitiva — o lobo da costa é retângulo ∪ círculo (círculo com centro preso ao mapa não faz "largo e raso") e o mar profundo é um L. **Várias regiões apontando para o mesmo bioma** já era permitido pelo modelo; foi aqui que precisou.

| bioma | do plano |
|---|---|
| Mar raso (catch-all) | 37,2% |
| Mar Profundo | 28,0% |
| Jardins Recifais | 17,4% |
| Costa Primordial | 12,5% |
| Plataforma Glacial | 4,9% |

A ordem de avaliação é o desenho: o glacial vem **antes** do mar profundo e é ele que recorta a faixa dele, e é assim que os dois lugares vazios do mapa ficam emendados nos cantos de baixo em vez de disputarem o mesmo chão.

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

Subir de nível pede as duas condições ao mesmo tempo, igual ao Relicário: **XP cheio e o material da própria classe da criatura** que sobe (um item `material` por classe, ligado por `items.class_id` — `BestiaryData.class_material_item` resolve) — o material vem de **drops** de combate, não do comerciante. Sem o material na bolsa, a barra trava no teto em vez de estourar; o próximo ganho de XP (a próxima vitória) resolve sozinho assim que o jogador tiver o item. `PlayerRoster.grant_xp_at` e `PlayerRelic.grant_capture_xp` compartilham a mesma curva (`ProgressionMath`), extraída quando o segundo consumidor apareceu.

**Drops** — criatura derrotada em combate (não capturada — capturar não a mata) rola cada entrada de `creature.drops` **independentemente** (`LootTable.roll`): zero, um ou vários itens na mesma vitória, sem relação entre as chances. O material de subida de nível é só mais um item nessa lista, com a classe do **derrotado** decidindo qual material cai — nunca a de quem venceu. `WorldRoot._grant_drops` joga o que caiu direto na bolsa e mostra uma mensagem; nada cai se o roll não der em nada, e a HUD fica quieta.

**Mineração** — `F` coleta um mineral sorteado por:

```
chance(mineral) = normalizar(peso_classe × peso_bioma)

cooldown = 3 s / speedModifier da classe ativa
```

O **bioma** diz o que o chão tem; a **classe da criatura ativa** diz o que ela sabe achar. Os dois pesos vêm do bundle (`mining.rates`), e é a multiplicação que faz a troca de ativa ser sentida — no Mar raso (BIO-001), a escavadora tira âmbar fóssil 16,2 % das vezes contra 3,5 % da prospectora, que em troca acha prata 11,8 % contra 0,8 %.

O `workFunction` de cada classe também dá o papel e o ritmo:

Os três papéis de trabalho existentes são `excavator`, `burrower` e `prospector`, traduzidos por `MiningTable.ROLE_LABELS`. **Papel de trabalho e classe não são 1:1** — classe é especialização de combate, papel é ritmo de mineração, e não há motivo para uma classe nova exigir um papel novo. Qual classe tem qual papel e qual ritmo está em `workFunction` no bundle, nunca aqui: transcrever a tabela criaria um segundo lugar para ela discordar do catálogo.

A fórmula vive em `scripts/data/mining_table.gd`; `BestiaryData` só indexa o bundle. É a mesma separação que existe entre `CombatMath` e os dados de combate — **nenhum peso, nome ou taxa de minério está escrito em código.** Balancear mineração é `POST /mining-rates` no bestiário e re-exportar, não um commit aqui.

`scripts/data/ore_table.gd` — que carregava cinco minérios inventados em constante — foi removida quando o export passou a trazer o bloco `mining`.

**Painéis** — bolsa e inventário no canto superior esquerdo, criatura ativa no superior direito (status + perfil de mineração + os três minerais mais prováveis para ela ali). Todos somem durante o combate e a negociação, e voltam ao fechar — exceto a bolsa se o jogador pediu para escondê-la com `V`: essa escolha é dele, não do overlay, e sobrevive ao fechar loja/posto/duelo (`WorldRoot._inventory_hidden`).

**Set do jogador** (`E`, `player_set_window.gd`) — janela central somente-leitura com o que está equipado. Três seções: o Relicário (nome, nível, XP, afinidade — "—" quando neutra, slots, taxa de captura), o Amplificador e o Encantador (modelo, tier e o efeito em uma frase). O plano de crescer por **seção** e não por janela nova foi o que se cumpriu quando o set saiu de uma peça para três. Slot vazio diz *onde se resolve* ("fabrique na bancada"), não só que está vazio — sem isso a peça fica invisível até o jogador topar com o ponto no mapa. Diferente do posto do relicário: o posto (`Tab`, ponto fixo do mapa) é onde o equipamento se *gerencia* (depositar/retirar/trocar de modelo); esta janela é só a *visão* dele, de qualquer lugar. Fecha com `Esc`, mutuamente exclusiva com a janela do time (`T`) — as duas são overlays centrais e se sobreporiam.

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

**Buff de combate — removido.** O Relicário não concede mais bônus de ataque nem qualquer outro status direto em batalha; `DuelScreen._apply_relic_buff` e o uso de `Combatant.attack_modifier` pelo relicário saíram do duelo. As colunas `relic-stats.combatBuffBase`/`combatBuffPerLevel` **saíram do catálogo** em 2026-08 (migration `0014`). Elas ficaram um tempo como curva vestigial — desligadas mas cadastradas — e a consequência foi pior que a duplicação: o posto do Relicário exibia "buff 6.2" para um número que nenhuma peça do combate lia, e três dos quatro modelos guardavam `5`/`0.3` em vez do `0` que a própria regra mandava. Coluna sem consumidor não fica neutra: vira promessa na tela. Buffs de combate, quando existirem, são peça de outro slot do set do jogador — não do Relicário.

**Posto do relicário** — ponto fixo no mapa (`RelicStationActor`, mesmo padrão de clique-para-interagir do comerciante), com quatro modos (`Tab` circula): status do equipado, depositar um ativo no storage, retirar um guardado, e trocar de modelo — só habilitado com o time ativo **vazio**, forçando "esvaziar os slots antes de trocar" como o design exige. Sem sistema de posse ainda, a troca deixa escolher qualquer modelo do catálogo — o mesmo furo que a aquisição já é, só tornado visível aqui.

`PlayerRoster` tem três níveis por causa disso: **ativo** (limitado por `slotCapacity`, via `set_capacity()`), **storage** (sem limite de código, só acessível no posto) e o HP/regeneração que já valiam para os dois. Time cheio na hora da captura continua fazendo a captura escapar, exatamente como antes — só que "cheio" agora depende do relicário equipado, não de um teto fixo de seis.

### Amplificador e Encantador

As outras duas peças do set (documento `equipamentos` no bestiário). São **passivas**: valem a batalha inteira, não custam turno, não se consomem.

| Slot | Alvo | Modelos |
|---|---|---|
| `amplifier` | a criatura do jogador | `EQP-001/002/003` — `buff_attack` +5/+10/+15 % |
| `enchanter` | a criatura adversária | `EQP-004/005/006` — `debuff_attack` −5/−10/−15 % |

As duas se vestem ao mesmo tempo — são slots diferentes, não alternativas. O que compete dentro de um slot são os **tiers**.

**O consumidor já existia.** `Combatant.attack_modifier`/`defense_modifier` e os quatro códigos `buff_*`/`debuff_*` estavam em jogo desde as habilidades de suporte (`HAB-019` a `HAB-022`); o equipamento entrou como segunda fonte do mesmo modificador, não como sistema paralelo. `Battle._apply_modifier` é o ponto único que os aplica — foi extraído de `_apply_status` quando a segunda fonte apareceu, e o clamp acumulado (`MODIFIER_MIN/MAX`, 0,25–4,0) continua com um dono só.

**O passivo é mais fraco que o golpe que custa a rodada, e isso é regra.** `HAB-020` dá +30% gastando o turno; o T3 daqui dá +15% de graça. Se empatassem, o golpe de suporte viraria conteúdo morto — `test_equipment.gd` prende a comparação contra o valor que estiver no catálogo, não contra um número escrito no teste.

**`Battle.apply_loadout` aplica no time inteiro**, não só em quem está em campo. A peça é do domador, não da criatura: aplicar só na ativa obrigaria a reaplicar em `_do_switch` e em `replace_active`, três lugares para o mesmo efeito. Quem decide o alvo é o **slot**, nunca o `effectCode` — slot desconhecido é ignorado em vez de aplicado no alvo errado.

**Tiers, não níveis.** Não há barra de XP: a progressão é a mineração. Um nível pediria decidir o que enche a barra de cada peça, e isso é um sistema novo por peça. Os tiers são crafts independentes — o T2 não consome o T1 —, então nenhum modelo pode ficar inalcançável por ter sido comido por outro.

#### A bancada, e a posse

`CraftingBenchActor` — ponto fixo na vila da costa, mesma família de `InteractableActor` do comerciante e do posto, silhueta de prisma baixo e largo (de longe tem de ler como mesa, não como pessoa).

| Tecla | |
|---|---|
| `Tab` | alterna amplificador / encantador |
| `1`–`9` | age na linha — **fabrica**, **veste** ou **tira**, conforme o estado |
| `Esc` | sai |

Uma tecla, três destinos, e a linha diz qual antes de o jogador apertar. A receita mostra `tem/precisa` por ingrediente — o mesmo raciocínio do "restaura 12 (desperdicia 92)" da janela de cura: o número que decide o próximo gesto é a diferença.

**A bancada é a única fonte das duas peças**, e é isso que fecha aqui o furo que o Relicário ainda tem. `PlayerLoadout` guarda **posse** e **equipado** separados, e `equip()` recusa o que o jogador não fabricou — no posto do Relicário dá para vestir qualquer modelo do catálogo sem nunca o ter conquistado, porque lá não existe sistema de aquisição.

A tela não decide nada: emite `craft_requested`/`equip_requested` e o `WorldRoot` — que tem a bolsa **e** o loadout — mede, recusa, cobra e registra, nessa ordem. Mesmo contrato de `RosterWindow.item_use_requested`. A conferência é **tudo ou nada**: a receita inteira é medida antes de o primeiro minério sair, senão faltar o terceiro ingrediente deixaria o jogador sem os dois primeiros e sem a peça.

**Tirar não é perder** — desequipar esvazia o slot e mantém a posse. Lutar sem o Encantador é jogada legítima, e cobrar trinta cobres por experimentar seria punir o teste.

#### Os minérios glaciais

O Amplificador se faz de Cobre, Prata e Âmbar Fóssil, mineráveis em qualquer canto do PZ-01. O Encantador se faz de `ITM-024` **Sal de Degelo**, `ITM-025` **Nácar Fóssil** e `ITM-026` **Prata Errática** — que só saem da Plataforma Glacial (`BIO-014`).

Cada um espelha em valor um minério do mapa (20 / 30 / 60), então **os dois lados custam exatamente o mesmo em óbolos** por tier — 330, 820 e 1 860. O que separa as duas linhas é geografia, não preço: *o Encantador não é a peça cara, é a peça longe.*

**A exclusividade não é código.** É a ausência de linha em `mining_rates`: os três só têm taxa de bioma em `BIO-014`, e `MiningTable._weight_of` lê "bioma presente mas sem este minério" como peso zero. Isso tem um modo de falha silencioso e vale saber: o documento `mineracao` manda todo bioma ter o conjunto **completo** de taxas, e quem cumprir isso literalmente para os minérios novos torna o Encantador fabricável sem sair da vila. `test_equipment.gd` varre os catorze biomas exatamente por isso.

O lado da **classe**, esse sim, é obrigatório nas cinco: sem linha de classe o produto `classe × bioma` dá zero e o minério ficaria inalcançável mesmo pisando no glacial.

### Arena e Glifos

Documento de regra no bestiário: `glifos-e-portais`. Um **Glifo** é conquista permanente, não item — não se vende, não se craft, não dropa de combate comum. O **Campeão da Arena** (`NPC-002`, `role = duelist` no bestiário) é o primeiro duelista jogável: clicar nele de perto abre o mesmo `duel.tscn` de sempre, mas com `DuelScreen.is_wild = false` — `Battle` recusa captura nessa configuração (`_do_capture`), então a arena é sempre golpe contra golpe até alguém cair. `PlayerProgress.grant_glyph` é idempotente, então refazer a arena depois de já ter o Glifo não reanuncia nem duplica nada.

**O duelo vem do catálogo, não daqui.** Contra quem a arena luta, em que nível e qual Glifo ela concede saíram das constantes do `WorldPopulator` em 2026-08 e vivem em `npc_duelists`, chegando em `duelists[].duel` no bundle. O nível era o caso indefensável — número de balanceamento em código, contra a regra 1. `grantsGlyph` **nulo é normal**: pelo modelo fechado no bestiário, todo mapa tem arena mas só a do último mapa de uma era concede Glifo; as intermediárias são duelo com recompensa própria. O save guarda o **código** (`GLF-001`) e a tela mostra o **nome** (`Daleth`), que é o que permite renomear a letra sem invalidar progresso.

O **Guardião do portal** (`PortalGuardianActor`, silhueta em bloco alto — não repete cápsula nem torus de nenhum outro ator) barra a passagem até o jogador ter o Glifo. `can_pass()` é a checagem de lógica, separada de qualquer texto — o requisito vale mesmo se a mensagem nunca aparecesse.

**Ele só existe onde o catálogo pede.** Guardião é a forma física de uma travessia que exige Glifo (`map_connections`), e travessia **dentro** de uma era é livre: como PZ-01 → PZ-02 não exige nada, **o PZ-01 não tem mais guardião**. Isso não é conteúdo removido do jogo, é conteúdo que passou a seguir o dado — uma linha com `requiredGlyphCode` o traz de volta, sem tocar em código. `test_merchant.gd` prende o "se e somente se". O guardião volta a aparecer quando existir a travessia PZ-03 → Titanor, que é a que exige Daleth.

**Primeiro estado que sobrevive a fechar o jogo.** Tudo o resto aqui (time, bolsa, relicário) é só em memória — `PlayerProgress` (autoload `Progress`) é o único que grava em disco, em `user://progress.cfg`, na hora que o Glifo é concedido. É formato pequeno de propósito (uma lista de códigos), mas a seção existe para crescer quando o resto do save também precisar persistir, sem precisar de arquivo novo.

A arena fica no mapa que o bestiário disser (`npcs.map_id`); **onde** ela é plantada é posição de cena, mesmo raciocínio de `MERCHANT_SPOT`/`RELIC_STATION_SPOT`. A **arena fica no topo da ilha** do miolo do mapa (`MapTerrain.ISLAND_*`), o único chão seco fora da vila da costa: um platô cercado de mar é a imagem que "arena" pede, e o adro de loja e portal não dava. `PORTAL_SPOT` continua reservado na planície, a caminho da costa, para quando houver travessia exigente de novo. O Glifo Zayin (Titanor) está no catálogo sem arena e sem travessia: não existe mapa de Titanor para prender neles — e é exatamente disso que o export avisa, sem abortar.

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

Quinze suítes headless, sem dependência de editor:

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
& $godot --headless --script res://scripts/dev/test_staging.gd      # os tres andam ao posto, apoiados no relevo
& $godot --headless --script res://scripts/dev/test_glyphs.gd       # Glifo de arena, nunca de vitória selvagem
& $godot --headless --script res://scripts/dev/test_characters.gd   # kit de personagens, rig por receita
& $godot --headless --script res://scripts/dev/test_palette.gd      # cor por elemento, aura do Despertar
& $godot --headless --script res://scripts/dev/test_equipment.gd    # set: exclusividade glacial, bancada, passivo
```

`test_playable.gd` é o único que sobe a árvore de cena com física ativa e injeta input. Responde "dá para jogar?" em vez de "as contas fecham?" — e foi ele que pegou o corpo andando de costas, que nenhum teste de lógica isolada veria.

`test_data.gd` é o guarda do contrato com o bestiário: se o formato do bundle mudar, se uma fórmula sair do lugar ou se o export deixar passar uma criatura sem stats, estoura ali em vez de virar bug de runtime. Rode depois de todo `game:export`.

**Erro e alvo saem por portas diferentes.** `_check` reprova a suíte; `_warn` reporta e deixa passar, e o resumo vira `OK — N verificacoes passaram (1 aviso(s))`. A regra: suíte vermelha significa *quebrado*, não *incompleto*. Criatura sem Despertar é incompleta — ela joga, só não usa o medidor de carga, e o `DATA_WORKFLOW` chama esse passo de opcional de propósito. Já uma criatura sem Despertar que **conhece um golpe `awakeningOnly`** é quebrada: o golpe aparece na ficha e nunca pode ser usado, porque `Combatant` o filtra por `is_awakened`.

`pnpm game:export` usa exatamente o mesmo par de critérios — aborta no golpe inalcançável, avisa na cobertura. Isso é deliberado: os dois guardas já discordaram, e a fresta era exatamente essa. O export não olhava nenhuma das duas coisas, e o teste reprovava na cobertura sem checar o golpe morto — foi assim que `CRT-013` saiu num bundle jogando com 5 golpes contra 6 do resto do elenco, com a suíte vermelha apontando para o sintoma errado.

Ele também exige o bloco `mining` — minerais nomeados, toda classe do elenco com pesos e perfil de trabalho, nenhum peso apontando para mineral inexistente. O jogo *sobe* sem mineração (só avisa, porque combate não depende de minério), mas um export sem ela é um export velho, e é aqui que isso tem de doer, não numa tecla `F` que não faz nada.

`test_encounter.gd` cobre o loop completo de encontro — spawn → clique → batalha → vitória (remoção + respawn) → captura (remoção sem respawn + card do jogador).

`test_mining.gd` cobre a `MiningTable` (distribuição normalizada, especialidade por classe, amostragem sobre 4.000 sorteios, perfil de trabalho), o `PlayerRoster` (captura vira reserva, troca não reordena, teto de slots) e o fluxo no `WorldRoot`. A asserção que importa é a de ponta a ponta: trocar a ativa por uma criatura de outra classe muda a companheira, a distribuição de minério **e** o cooldown, os três de uma vez. Se um dia essa falhar, a fórmula parou de ler um dos dois lados e o jogo ficou igual com qualquer criatura à frente.

Trocar a ativa por outra da mesma classe passaria em tudo sem provar nada — por isso o teste usa duas criaturas de classes diferentes, de propósito.

`test_merchant.gd` fecha o laço: minerar produz, o comerciante compra, a bolsa paga, e o que se compra faz alguma coisa. A asserção que mais importa é negativa — **nenhum consumível pode ser minerável**. Enquanto todo item era minério, o export mandava a tabela inteira para `mining.items`; o primeiro consumível cadastrado teria virado minério de chão. O filtro por categoria conserta, e este teste é o que impede alguém de removê-lo.

Também prende o "tudo ou nada" das duas pontas: sem saldo, nem a bolsa nem o inventário se mexem; vender o que não se tem não credita nada.

`test_companion.gd` separa "seguir" de "estar preso". A diferença é fácil de descrever e fácil de perder de vista, então o teste prende cada metade: não parte no mesmo quadro do comando, não orbita quando o jogador gira parado, não corta a diagonal na curva, e se orienta pela própria marcha em vez de copiar a do jogador. O "jogador" ali é um `Node3D` movido à mão em passos fixos — sem física nem input, porque o atraso de largada é da ordem de um oitavo de segundo e o jitter do motor esconderia justamente essa margem.

`test_team.gd` responde "uma expedição custa alguma coisa?". Não testa `hp = hp - dano`; testa a cadeia inteira — sair ferido de uma batalha, entrar ferido na próxima, e a espera no mapa sendo o único jeito de desfazer isso. Inclui a armadilha da regeneração fracionária: 10% de 84 HP por minuto dá 0,023 HP por quadro a 60 fps, e sem acumulador a cura inteira desaparece no arredondamento. O teste roda o mesmo minuto em passo de segundo e em passo de quadro e exige que os dois cheguem ao mesmo lugar.

`test_items.gd` responde "comprar cura serve para alguma coisa?". Antes dele os emplastros eram compráveis, vendíveis e precificados, e **nada os consumia** — o laço econômico terminava numa vitrine. A asserção que mais importa também é negativa: **cura nula não consome o item**, medida nos dois níveis (o `WorldRoot` recusa antes de tocar na bolsa, e a lista de alvos já apaga quem está cheio). Prende também que `30` em `heal_percent` são trinta por cento e não trinta vezes, e que um mineral na bolsa não aparece na lista de cura.

`test_staging.gd` responde "a imagem mostra o que o overlay narra?". A asserção que mais importa é a da **simetria**: o ponto médio entre os dois não pode escorregar, porque é onde eles se encontraram — se um dia um dos lados passar a fazer todo o trabalho, é ela que pega. A do domador é a mesma medida por outro lado: montar a cena **com** e **sem** ele e exigir que o ponto do encontro caia no mesmo lugar. A segunda é a única que prova fiação em vez de geometria: uma fase inteira do teste espera **quadros reais do motor**, sem chamar `step`, com o mundo pausado. Sem ela, `PROCESS_MODE_ALWAYS` poderia cair e todo o resto continuaria verde.

A terceira é `_test_terrain`, com um `MapTerrain` de verdade em vez da bancada plana: exige que cada corpo termine em `height_at + o apoio que ele mesmo declara`, que **nenhum fique abaixo do relevo**, e que a marcha entregue seja positiva andando e zero parado. `_test_bounds` monta o caso da borda — o posto do domador projetado para fora da malha — e exige que ninguém saia dos limites **e** que o erro dele ainda zere, que é o que separa "aparado" de "empurrando a parede para sempre". `_test_animating` prende a última: o modo de animar pausado entra em todos os corpos enquanto a encenação está na árvore e sai quando ela é liberada. As bancadas sem terreno continuam exigindo que a altura **não** seja tocada: os dois contratos convivem, e é essa diferença que o `terrain` nulo seleciona.

`test_characters.gd` guarda a escada de marcha nas duas pontas que importam: correr a 5,2 m/s (tocar `Walk` ali é o deslize que motivou a escada) e nadar submerso, que é o estado normal da exploração. `test_world.gd` guarda a regra da água — submerso fora da costa em qualquer altura, o pé da rampa ainda molhado, o platô seco, e a cota igual à da névoa.



Ela também prende que o encaramento é medido **no plano**: a bancada põe os dois corpos em alturas diferentes de propósito (companheira no chão, selvagem meia cápsula acima), e um produto escalar em 3D mediria a inclinação entre eles em vez do encaramento — foi exatamente assim que a primeira versão do teste falhou com `dot 0.913`, que é o cosseno de 1,4 m de desnível e não um erro de yaw.

`test_equipment.gd` responde "minerar longe compra alguma coisa?". Antes dele o mapa tinha cinco biomas e **um** motivo para andar até qualquer um — a taxa de minério — e nada que o jogador quisesse o bastante para atravessar o mar gelado. As duas asserções que mais importam são negativas, como sempre: **minério glacial não sai de nenhum outro bioma** (varre os catorze × cinco classes, porque a exclusividade é ausência de linha e ausência some sem sintoma) e **receita incompleta não cobra nada** (faltando um dos três ingredientes, os outros dois continuam na bolsa — é o defeito que uma varredura ingênua `for line: remove(...)` produz e que passa em todo o resto da suíte). Prende também o espelho de custo entre os dois slots, a recusa de vestir o que não se fabricou, e que o buff atravessa a troca de criatura.

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

### Cor por elemento e a aura do Despertar

Os placeholders são compartilhados N:1 — 27 dos 30 corpos dividem apenas **dois** atlas de textura. Sem mais nada, o elenco inteiro sai da mesma cor, e o jogador não distingue de longe o que está enfrentando. **`scripts/world/element_palette.gd`** resolve isso recolorindo o corpo pela paleta do elemento, que vem do catálogo (`elements.palette*` no bestiário, editável em `/elements` na UI dele).

O mecanismo é uma **rampa lida por luminância**, não uma tintura. O atlas do Quaternius é paleta chapada — 1024×1024 com ~50 cores distintas, 84% da imagem em branco não usado —, então `shaders/element_palette.gdshader` mede a luminância de cada texel e usa esse valor para amostrar um `GradientTexture1D` de três paradas: `shadow` no mais escuro, `mid` no meio, `highlight` no mais claro. É isso que faz **"amarelo com preto" caber num elemento só**: Eletricidade é uma rampa que sai de quase-preto e chega em amarelo, e a forma do bicho distribui as duas pontas sozinha. Rotação de matiz não conseguiria — ela preserva as relações entre cores e nunca transforma uma cor em duas.

Três decisões que custaram tentativa:

- **Shader, não textura gerada.** Gerar um atlas variante por elemento com `Image` significaria ~1 milhão de pixels percorridos em GDScript por variante, mais um cache para invalidar toda vez que a paleta mudasse. Nada se perde no shader porque esses placeholders **não têm normal map nem metallic-roughness** — o material do `.glb` é só o atlas de base color.
- **A saturação decide quem é recolorido.** Remapear tudo pela luminância pinta dentes, olhos e garras junto e o bicho vira uma mancha. Texel neutro (branco, cinza, preto) passa quase intacto; quem é saturado — o corpo — vai inteiro para a rampa.
- **Os limiares são medidos em espaço GAMA.** Com o hint `source_color` o Godot já linearizou o texel na amostragem, e comparar limiar de sRGB contra valor linear foi o defeito que fez as seis criaturas saírem da mesma cor suja. O `fragment()` reconverte antes de medir e mistura em linear.

`spread` (por elemento) permite que cada criatura ocupe uma faixa dentro da família: `ElementPalette.creature_bias` deriva do **código** da criatura — nunca sorteia, senão a mesma criatura mudaria de cor entre partidas e entre os dois corpos que a representam — um deslocamento aplicado como **gama** sobre a posição na rampa. Gama preserva as pontas, então a criatura clareia ou escurece dentro da família e nunca vaza para outro elemento.

A **aura do Despertar Ancestral** é do duelo e só do duelo. São duas coisas: uma casca aditiva da própria malha, inflada ao longo da normal com `cull_front` (o halo é o interior do fundo da casca escapando da silhueta), e uma `OmniLight3D` na cor do elemento. Na câmera isométrica com névoa é a **luz** que se lê de longe — o halo sozinho some no cenário. A casca entra como **irmã** do `MeshInstance3D`, não filha: o `skeleton` de uma malha rigada é um NodePath relativo, e mantida a vizinhança ele continua resolvendo para o mesmo `Skeleton3D`, então a aura acompanha a animação sem nenhum código de sincronia.

Quem acende é `EncounterDirector`, ligado ao sinal `rendered` da `DuelScreen` — que dispara a cada mudança de estado, porque numa máquina de turnos não há o que amostrar entre um turno e outro. O estado é **espelhado** da batalha, não acumulado a partir dos eventos do log: despertar, reverter por tempo, cair em combate e trocar de criatura são quatro caminhos que apagam a aura, e reagir a evento exigiria acertar os quatro.

A aura tem **cor própria** (`paletteAura`), e não o `highlight` reaproveitado, por um motivo que só aparece quando as duas metades existem juntas: com o corpo já recolorido pelo elemento, uma aura na mesma cor some justamente na criatura em que ela deveria gritar.

Corpo legado do Meshy **não** é recolorido — base color assada com normal e metallic-roughness próprios sairia suja. O portão é o prefixo `res://models/placeholders/`, e `test_palette.gd` o prende.

**Props de bioma** — o que encomendar, com que orçamento e por quê, está em [`../avyron-bestiary/docs/BIOME_PROPS.md`](../avyron-bestiary/docs/BIOME_PROPS.md): o contrato que todo prop precisa cumprir (origem na base, normalizado em 1×1×1, sem frente, uma superfície), a densidade por bioma e o pedido de 21 peças que falta para o PZ-01. Eles chegam pelo mesmo export, em `models/biomes/` (preparados por `pnpm models:biomes` no bestiário). `megakit/` (Stylized Nature MegaKit do Quaternius, CC0) veste o terrestre: vegetação e pedras em escala real (CommonTree ~7 m) — samambaias escaladas 2,5–3× e cogumelos 3–4× dão a vegetação carbonífera do PZ-03; são `.gltf` com texturas **compartilhadas** de propósito (o Godot deduplica recursos por caminho; `.glb` embutiria uma cópia da casca em cada árvore). `aquatic/` (11 props gerados no Meshy) cobre o marinho do PZ-01: corais, algas e formações em `.glb` individuais, **normalizados em ~1×1×1 pelo Meshy** — a escala de cada peça é decisão da cena (recifes 2–5×, o arco 8–9× como landmark).

Quem aplica isso é **`scripts/world/map_dressing.gd`** (`MapDressing.apply`, chamado por `WorldRoot._ready`, mesmo padrão RefCounted/static do `WorldPopulator`): ambiência subaquática (fog azul `~0.011`, luz fria), landmarks fixos à mão (com colisão cilíndrica só nos maciços — o arco é passagem por baixo) e vegetação miúda espalhada com semente fixa, respeitando um raio livre em torno dos pontos do `WorldPopulator` e da origem do jogador. Layout é posição de cena, não de bestiário — o catálogo diz *o que* vive no mapa; o mundo diz *onde*.

### Relevo e solo

#### O tamanho do mapa, e o que escala com ele

**O PZ-01 tem 120 × 120 m desde 2026-08-28** (era 60). O alvo declarado é **350 m**, e a conta que o define é de tempo, não de gosto: a 5,2 m/s (velocidade única — nadar e andar são iguais, `submerged` só troca o clipe), **30 s de travessia por bioma** dão 156 m por bioma, que com cinco biomas pedem 350 m de lado.

Os 120 m são a etapa intermediária, e o critério da parada é densidade: levar os 44 props de hoje para 350 m os diluiria para 1 a cada 2.784 m² — o mapa não ficaria grande, ficaria deserto. 120 m é o maior lado que o acervo atual veste (132 props, 1 a cada ~109 m²).

| | 60 m (antes) | 120 m (hoje) | 350 m (alvo) |
|---|---|---|---|
| travessia lado a lado | 11,5 s | **23,1 s** | 67 s |
| vértices do terreno | 3.721 | 14.641 | 123.201 |
| props | 44 | 132 | ~1.500 |
| criaturas | 8 | 24 | ~270 |

O que os 350 m vão exigir e os 120 m não exigiram: `MultiMesh` para o scatter, população de criatura local ao jogador em vez de contagem fixa, e medir os 245 mil triângulos de terreno em vez de assumi-los.

**A regra que torna o próximo resize barato** está escrita no cabeçalho do `map_terrain.gd`, e é a parte que importa: cada constante do relevo cai em um de dois grupos. **Escalam com o mapa** as feições cujo papel é ocupar uma fração dele — `FLAT_RADIUS` e `COAST_RAMP_START`, porque planície e costa são biomas, e bioma que não cresce junto encolhe até sumir. **Têm tamanho próprio** as alturas (`HILL_HEIGHT`, `RIM_HEIGHT`, `COAST_HEIGHT`), a largura da rampa da costa (é conta de inclinação) e a ilha inteira (ela cabe uma arena — dobrá-la daria 36 m de platô para um duelista só). Trocar uma constante de grupo por engano é o que quebra o mapa.

E a consequência boa: **o mapa dobrou e as três regiões de bioma do catálogo não precisaram de uma linha de mudança.** Como costa e anel de recife escalaram na proporção, `-0.533` e `r 0.5` continuam apontando para os mesmos lugares — `test_data` mediu a fronteira em z = −32,00 contra um `COAST_RAMP_START` de −32,00. É exatamente o que as coordenadas normalizadas prometiam, verificado num resize real em vez de assumido.

#### O relevo

**`scripts/world/map_terrain.gd`** substitui em runtime o `Ground` chapado de `main.tscn` (mesmo nome de nó — o clique de mundo e o `test_world` continuam funcionando): uma grade de 121×121 a 1 m que gera malha, colisão (`HeightMapShape3D`) e a consulta `height_at` **da mesma fonte**, então visual, física e consulta nunca discordam. O desenho é deliberado:

- **Planície central plana (altura 0) até `FLAT_RADIUS` = 32 m** — o gameplay que assume plano (POIs do `WorldPopulator`, encenação de duelo) vive aí. Com uma exceção declarada, a ilha logo abaixo: quem apoia corpo perto da origem **pergunta a altura**, não presume zero.
- **Colinas suaves (até 2,5 m, ruído com semente fixa) só na zona externa**, e um **rim de borda (+3,5 m)** que fecha a leitura do mapa na câmera ortográfica — relevo é apresentação com colisão, não labirinto.
- **Uma costa na borda -Z, em forma de LOBO** (+1,6 m, alcançando z = −32,4 m no meio e recuando para −43 nas laterais) reservada a NPCs e portais — comerciante e posto do Relicário vivem lá (`WorldPopulator`), o spawner não deixa criatura nascer na faixa (`MapTerrain.on_coast`, com margem para a deriva de patrulha) e o `MapDressing` não espalha bioma nela. O shader pinta a faixa emersa num tom seco (`color_coast`), com a base da rampa continuando molhada.
- **Uma ilha no meio do mapa**: platô de 8 m de diâmetro (+2,6 m) que carrega a **arena** e é onde o domador abre o jogo, de pé, antes de descer para o mar. Mesmas regras da costa — `MapTerrain.on_island` mantém criatura fora dela (keep-out de 11 m) e o `MapDressing` não espalha coral em terra seca; o shader pinta o topo com o mesmo `color_coast`, em faixa radial em vez de banda de Z. A largura da rampa é conta, não gosto: a inclinação máxima de um `smoothstep` é `1,5 · altura / vão`, e 2,6 m em 5 m de vão dá **38°**, abaixo dos 45° que o `CharacterBody3D` aceita como piso — encurtar o vão sem refazer a conta transforma a ilha em parede e tranca a arena lá em cima. `test_world` cobra os dois: a rampa andável e a arena no topo plano.
- **A iluminação é fragmentada por altura, não por região** (um `Environment` só): a névoa fria é **névoa de altura** — densa abaixo da linha d'água (`PZ01_WATER_LINE`, logo abaixo do topo do platô) e rala acima, então o leito fica imerso na murk e a costa emerge para um ar limpo. O tom quente do trecho seco vem de **omnis de preenchimento locais** sobre a vila da costa e sobre a ilha (sem sombra — banho de cor, não fonte de leitura); sol e ambiente globais continuam frios para o mar. A regra é "chão que emerge sai da murk também na luz" — trecho seco novo ganha a sua omni. Nota de tuning: na câmera ortográfica inclinada o raio de visão atravessa pouco da camada baixa, então `fog_height_density` precisa ser alto (~1.0) — valores tímidos não acumulam murk nenhuma.
- Corpos com física (jogador, selvagens) seguem o relevo pela colisão; quem não tem física pergunta: a companheira (`terrain.height_at` no lugar do antigo `GROUND_Y`, que virou fallback de bancada), o spawner (nasce apoiado) e os props do `MapDressing`.

O **solo** é um shader próprio (`shaders/terrain_ground.gdshader`): dois tons misturados por ruído em espaço de mundo (sem UV) + um terceiro tom nas inclinações, com a paleta por mapa vinda de `MapDressing.ground_palette`. A **geografia da costa** (onde a areia seca é pintada) saiu dos defaults do shader e passou a vir do `MapTerrain`, junto com a da ilha, pelo mesmo motivo: é geografia, e geografia é do terreno. São cinco medidas em vez de dois limiares desde que a costa virou lobo — a mesma forma composta que levanta a malha, para que a tinta e o relevo não possam divergir.

#### A costa é um lobo, e a forma vem do catálogo

Até 2026-08-28 a costa era faixa cheia: `smoothstep` puro sobre z, a largura inteira do mapa. O desenho espacial aprovado a redesenhou como lobo — largo no topo, descendo só no meio —, e **o relevo teve de acompanhar**: com a faixa mantida, 47% do chão SECO responderia "mar raso", ou seja, o jogador de pé na areia dos cantos com a mineração dizendo que ele está nadando.

As constantes `COAST_CENTER_X`, `COAST_LOBE_R`, `COAST_RECT_HALF_W` e `COAST_RECT_Z` do `MapTerrain` são a tradução em metros das duas regiões que o catálogo usa para a costa (`RGN-001` e `RGN-006`). Mudar uma sem reautorar a outra recria exatamente o buraco que essa rodada fechou — e `test_data` mede a fronteira **na linha de centro do lobo** para pegar a divergência, enquanto `test_world` cobra que o canto do topo seja mar, que é o que distingue um lobo de uma faixa.

O alcance máximo da costa mar adentro (`COAST_RAMP_START`) continua existindo como número único para o shader, os testes e as notas do catálogo conferirem — mas deixou de ser a fronteira em toda a largura: agora só vale no meio. Armadilha registrada: a frente de um triângulo no Godot é a ordem **horária** — na ordem OpenGL (anti-horária) o chão inteiro é backface-culled e o mapa flutua sobre o fundo.

**Animação.** Os clipes chegam com o vocabulário normalizado na conversão do bestiário (`convert-placeholders.mjs`): `Idle`, `Walk`, `Run`, `Attack`, `Attack2`, `HitReact`, `Death`, mais extras por família — quadrúpedes têm `Eating`, voadores não têm `Walk` e seguem no `Idle` de flutuação. A criatura selvagem nasce em `Idle` e patrulha em `Walk`; a companheira troca de clipe pelo próprio ritmo de marcha e desliga o bob sintético quando o corpo tem rig. O importador de glTF não marca loop em nada, então `LOOPED_CLIPS` em `creature_actor.gd` marca só os clipes contínuos — nunca `Death`.

Orçamento por asset para os modelos definitivos, conforme `direcao-3d-arte`:

| Papel | Triângulos | Textura |
|---|---|---|
| Chefe/hero | 5k–8k | 1024² |
| Regular | 2k–4k | 512² |
| Enxame | 500–1.5k | 256² |

Loops mínimos por criatura definitiva, a 24 fps, **nos mesmos nomes do vocabulário normalizado** — o código já os consome por esses nomes: `Idle`, `Walk`, `Run`, `Attack`, `Attack2`, `HitReact`, `Death`. Extras como `Yes`/`No`/`Wave` (feedback de captura/vitória) são bem-vindos.

Os artrópodes do elenco usam **rig flutuante** — sem rig locomotor por perna, deslizamento com bob vertical de ~5 cm. Cobre ~60% do elenco atual.

Os `.glb` espelhados em `models/` são versionados via **git-lfs** (`.gitattributes` já cobre `*.glb`; confira `git lfs status` antes do commit — blob commitado direto fica no histórico para sempre). Os `CRT-XXX.glb` da raiz viraram peso morto de 8–27 MB cada desde que todo o elenco tem `modelUrl`; podem ser arquivados fora do repo. Quando os modelos definitivos voltarem (animados), importe o `.glb` mestre — o do bestiário serve texturas KTX2 otimizadas para browser, que não é o que o Godot quer.

## Convenção de escala

**1 metro real = 1 unidade Godot.** Escala real, sem exagero dramático — um trilobita de 15 cm aparece pequeno e um Arthropleura de 2,5 m aparece grande.
