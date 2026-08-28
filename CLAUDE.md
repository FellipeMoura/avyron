# CLAUDE.md — briefing para sessões do Claude Code

Contexto para trabalhar neste repositório. Complementa o `README.md`, que descreve o que existe e como rodar; aqui está como trabalhar e o que não fazer.

Pendências de produto ficam no `ROADMAP.md`. A rodada de saneamento estrutural de agosto de 2026 — o que foi consertado, como foi provado e o que sobrou — está em [AUDITORIA.md](AUDITORIA.md), e é de lá que uma sessão de continuidade deve partir.

## O que é isto

O **jogo**, em Godot 4.7.x (GDScript, Forward+). Câmera isométrica ortográfica travada em 30°/45°, exploração em tempo real, combate por turnos 1v1 com troca livre disputado no mesmo espaço do mapa.

O **catálogo** — criaturas, habilidades, itens, números de balanceamento — vive no repositório irmão em `../avyron-bestiary`, e chega aqui via `pnpm game:export`, que grava `data/bestiary.json` **e** espelha em `models/` todo `.glb` que o bundle referencia por `modelUrl`, mais os props de bioma em `models/biomes/` (diretório inteiro — `.gltf` com texturas compartilhadas, deduplicadas na importação). Este repo é código e asset; aquele é conteúdo — inclusive a decisão de qual corpo 3D cada criatura usa.

O bestiário **roda local** desde a versão 0.104. O deploy em produção foi aposentado — ele existia para um Claude web alimentar o catálogo por HTTP, e quem escreve hoje roda na mesma máquina.

## Regras invioláveis

1. **Nenhum número de tuning mora em código.** Dano, carga, captura, preço, taxa de minério, bolsa inicial, margem do comerciante — tudo vem do bundle, que vem do banco. Se você está prestes a escrever uma constante que um designer poderia querer ajustar, ela pertence ao bestiário. As exceções legítimas são constantes de *apresentação* (velocidade de giro da câmera, amplitude de bob) e de *engenharia* (tamanho de chunk, epsilon).

   A forma geral dessa regra — quando algo é tabela do bestiário, quando é documento de design e quando é deste repositório — está em `../avyron-bestiary/CLAUDE.md`, seção **"Onde cada informação mora"**. O teste curto: o que o jogo lê em runtime é sempre tabela; do que ele não lê, o que sobreviveria a uma troca de motor é documento, e o que não sobreviveria (posição de nó, névoa, colisão, seed) é daqui. Vale consultar antes de criar sistema novo com dado novo.

2. **`data/bestiary.json` é gerado. Nunca edite à mão.** A próxima exportação sobrescreve. Número errado se corrige no bestiário e re-exporta.

3. **Depois de criar qualquer `class_name`, rode `--headless --import`.** O cache de classes globais do Godot só é atualizado na importação, e sem isso o parser não conhece a classe nova — o erro é `Identifier "X" not declared in the current scope`, que parece erro de digitação e não é.

4. **A frente de um nó é `-Z`.** Para encarar uma direção: `atan2(-dir.x, -dir.z)`. Usar `atan2(x, z)` alinha `+Z` e o corpo anda de costas — já aconteceu, e foi o teste de cena jogável que pegou.

5. **Encarar e afastar são medidas no plano.** Os corpos apoiam o Y em regras diferentes — `CreatureActor` sobe meia cápsula, `CompanionActor` fica em `GROUND_Y` com o mesh deslocado — então qualquer produto escalar ou distância entre dois deles mede o desnível junto se não achatar antes. O sintoma é um valor quase certo (`dot 0.913` em vez de `1.0`), que lê como imprecisão de giro e é geometria de outra dimensão.

## Como o código se divide

```
scripts/data/     bundle e fórmulas puras (BestiaryData, CombatMath, MiningTable, ItemEffects)
scripts/battle/   máquina de turnos (Battle, Combatant, BattleAction) — sem nós, sem sinais
scripts/world/    mapa, atores, jogador, time, inventário
scripts/ui/       telas e painéis
scripts/dev/      suítes headless e sondas
```

A separação que importa: **`data/` indexa e calcula, não decide.** `BestiaryData` só busca no bundle; `CombatMath`, `MiningTable` e `ItemEffects` só aplicam fórmula. **`BestiaryData.stats_at_level` é o funil único dos stats** — combate, time, ficha e painel da ativa passam todos por ele, e é por isso que o bônus de classe entra ali e não em `Combatant`: aplicado no combatente, a luta veria um número e a ficha mostraria outro. Quem decide é `battle/` e `world/`. Quando surgir um sistema novo com números, ele segue esse par — um índice em `BestiaryData`, uma classe de fórmula ao lado de `CombatMath`. `ItemEffects` é o exemplo mais recente disso.

Cuidado com `effectValue`: é uma coluna só servindo códigos de efeito que a interpretam de formas diferentes — `heal_percent` guarda pontos percentuais (30, 70, 100), `capture_bonus` guarda multiplicador cru (1.5, 2.5, 4.0). Ler o campo sem olhar o `effectCode` ao lado dá um número plausível e errado.

`Battle` é `RefCounted` puro de propósito: sem nós, sem sinais, sem árvore de cena. É o que torna 2.600 batalhas simuláveis em segundos na sonda de balanceamento e o que deixa a apresentação livre para consumir os eventos no ritmo que quiser.

## Testes

Quinze suítes headless, todas em `scripts/dev/`. Rodam sem editor. O padrão:

```gdscript
extends SceneTree
func _initialize() -> void:   # monta a cena
func _process(_d) -> bool:    # roda os testes num quadro, devolve true para sair
```

**Rodar os testes no `_initialize` não funciona** para nada que dependa da árvore: um nó adicionado à raiz antes de a árvore estar viva não conta como dentro dela, e `global_position` devolve transform vazio — toda medição vira zero.

**`queue_free()` é diferido.** Teste que remove um nó e confere a remoção no mesmo quadro falha por artefato, não por bug. Confira o estado síncrono (a referência que caiu) ou use `free()` em bancadas que você controla.

**Bancada com `_process` manual precisa de `set_process(false)`.** Senão o motor também chama, e cada passo conta dobrado.

**`class_name` novo não existe para o `--script` até o projeto ser reimportado.** O Godot resolve tipo global pelo `.godot/global_script_class_cache.cfg`, que é escrito na importação — rodar headless com `--script` não re-escaneia. O sintoma engana: as suítes continuam "OK", com contagens *menores*, e os erros reais (`Could not parse global class "X"`, `Could not find type "Y" in the current scope`) saem no stderr enquanto o teste segue e reporta verde no que sobrou. Depois de criar um script com `class_name`, rode uma vez:

```powershell
& $godot --headless --editor --quit-after 40
```

Isso regenera o cache e cria o `.uid` do arquivo novo. Só então as contagens voltam ao normal.

Screenshot de verificação: crie um `scripts/dev/shot_*.gd` descartável, rode com `--resolution 1600x900`, salve em `user://`, **apague o andaime depois**. Teste headless não vê layout.

## Convenções

- **Português** em tudo que o jogador lê e em todo comentário de código. Identificadores em inglês, seguindo o Godot.
- **Escala real: 1 metro = 1 unidade.** Um trilobita de 15 cm é pequeno, um Arthropleura de 2,5 m é grande. Sem exagero dramático.
- **O corpo vem do `modelUrl` do bundle**, resolvido por `CreatureActor.model_path` nesta ordem: `res://models/<modelUrl>` (espelhado pelo export — hoje os placeholders animados do Quaternius, compartilhados N:1 entre criaturas), depois o legado `res://CRT-XXX.glb` na raiz (Meshy, sem animação), e por fim a cápsula colorida pelo elemento. O que já é definitivo é tudo o mais — escala, máquina de estados, raio de detecção — e independe de qual fonte o corpo usou.
- **A cor da criatura é do elemento, e vem do catálogo.** Cada elemento traz no bundle uma `palette` — `shadow`/`mid`/`highlight` (uma RAMPA lida por luminância), `aura` e `spread`. `ElementPalette` a consome: recolore os placeholders compartilhados por um shader (`shaders/element_palette.gdshader`) e acende a aura do Despertar Ancestral. O `ELEMENT_COLORS` codificado em `CreatureActor` **não existe mais** — "de que cor é Fogo" é decisão de conteúdo (regra 1), e o que sobrou em código são constantes de apresentação (espessura da casca, alcance da luz, janela de luminância do atlas). Três coisas que não são óbvias: a recoloração só entra em `res://models/placeholders/` (os `.glb` legados do Meshy têm sombreado assado e sairiam sujos); `spread` desloca a POSIÇÃO na rampa por criatura, nunca o matiz, então duas criaturas do mesmo elemento diferem sem sair da família; e a aura tem cor própria porque na cor do corpo — que agora é a cor do elemento — ela sumiria. Ver `scripts/world/element_palette.gd`.
- **Clipes de animação seguem o vocabulário normalizado** (`Idle`, `Walk`, `Run`, `Swim`, `Attack`, `Attack2`, `HitReact`, `Death`…), garantido na conversão pelo bestiário. O importador de glTF não marca loop em nada: `CreatureActor._prepare_animations` marca só os clipes contínuos (`LOOPED_CLIPS`) — nunca `Death`. Trocar de clipe é sempre via `_play_clip`/`_update_clip`, que silenciam quando o clipe não existe (voadores não têm `Walk`). **A escolha do clipe é sempre uma escada de marcha e meio** — `Idle` → `Walk` → `Run` por limiar de m/s, `Swim` quando submerso, nunca um literal fixo no chamador: o jogador anda a 5,2 m/s, que é corrida, e foi o binário `Idle`/`Walk` que produzia o deslize.
- **`AnimationPlayer` é pausável.** Corpo movido com a árvore parada precisa de `PROCESS_MODE_ALWAYS` no player dele, senão o clipe fica *selecionado e congelado no quadro zero* — o corpo atravessa a cena numa pose estática e o defeito lê como "escolheram o clipe errado", que é a pista errada. Quem liga é a `BattleStaging` (`staged_animating`), só enquanto ela é dona do corpo: ligado sempre, uma criatura pega no meio do `Walk` por uma tela de loja andaria no lugar em vez de ficar parada.
- **Bioma é consulta por posição, não declaração.** `MapBiomes.biome_at(pos)` responde a partir de `maps[].biomeRegions` no bundle, avaliando as regiões na ordem do catálogo e parando na primeira que contém o ponto. Duas coisas não são óbvias e custam caro se esquecidas. **As coordenadas são normalizadas em ±1 sobre o meio-lado do mapa**, e quem divide é o Godot — é isso que faz a partição sobreviver a redimensionar o terreno sem reautorar dado, e é isso que quebra se alguém mudar uma fronteira de relevo (`COAST_RAMP_START` e companhia) sem mexer na região correspondente: a mineração passa a responder pelo lugar errado, em silêncio. `test_data.gd` VARRE o eixo medindo onde o bioma troca, justamente para essa divergência não passar. E o `DEFAULT_BIOME` do `WorldRoot` **não é mais o bioma do mapa** — virou fallback para dado faltando (mapa sem partição, ponto fora de todas as regiões); tratá-lo como "o bioma" refaz o furo que a rodada fechou.

- **Bioma ainda não decide nada além de mineração.** Spawn de criatura, ambiência e névoa continuam por predicado geográfico em código (`on_coast`, `on_island`), não por `biome_at`. Quem for ligar bioma a spawn — um bioma sem fauna, por exemplo — escolhe entre um quinto predicado geográfico e fazer o keep-out do spawner derivar da partição; a segunda é a que não precisa de código novo a cada bioma, mas nenhuma das duas existe hoje.

- **O PZ-01 é o leito de um mar, e nadar é o estado normal.** 87,3% do mapa responde "submerso" (remedido depois de a costa virar lobo: ela caiu de faixa cheia para 14,1% do mapa, e o que era praia nos cantos virou mar); o seco são dois trechos declarados — o platô da costa e a **ilha da arena**, no meio do mapa, onde o jogo abre. Quem responde é `MapTerrain.submerged` — **fora desses dois é sempre submerso**, independentemente da altura (recife não é ilhota), e só neles a cota decide, porque é neles que a rampa atravessa a superfície. Trecho seco novo é geografia declarada (um predicado como `on_coast`/`on_island`), nunca um afrouxamento da regra de altura. A cota vem de `MapDressing.water_line` e é a MESMA que fragmenta a névoa: separar as duas faria a imagem contradizer o corpo.
- **Corpo movido de fora implementa o contrato de encenação.** Na abertura do duelo o mundo está pausado e nenhum dos três corpos processa: quem os leva aos postos é `BattleStaging`, e ela precisa de três coisas de cada um — `staged_ground_offset()` (quanto a origem fica acima do chão, porque as três regras divergem), `staged_gait(speed)` (a marcha imposta, para o corpo escolher o clipe pela mesma escada de sempre) e `staged_animating(bool)` (deixar o `AnimationPlayer` rodar com a árvore parada). Os três são chamados por **nome** (`Node.call`), não por tipo, para a bancada de `Node3D` solto da suíte não ser obrigada a implementá-los. Corpo novo que a encenação venha a mover entra por aí; sem os métodos ele volta a deslizar sem apoio, em silêncio.

- **Humanos (jogador e NPCs) são UM sistema visual: `CharacterRig`.** O kit de personagens (`models/characters/`, espelhado pelo bestiário) traz corpos, cabelos e peças de outfit rigados no mesmo esqueleto de 65 ossos; um humano é uma *receita* de nomes de peça montada em runtime. A receita do NPC vem do bundle (`merchants[].appearance` / `duelists[].appearance` — conteúdo do catálogo, tabela `npc_appearances`); a do jogador é `PlayerController.DEFAULT_RECIPE` até existir tela de criação, e quando existir, persiste no save — nunca no bestiário. Receita vazia = cápsula, mesmo fallback de criatura sem modelo. Vestido, o corpo base entra só como cabeça (variante `Head_*`) — o corpo inteiro sob a roupa vazaria nas animações.
- **O set do jogador tem três peças, e só uma tem tabela própria.** O Relicário fica em `relics`/`relic_stats`/`relic_rules` porque as colunas dele são de captura ponta a ponta; Amplificador e Encantador ficam em `equipment`/`equipment_stats`/`equipment_recipes` porque são passivos que *tieram* em vez de subir de nível. Não existe `equipment_rules`, de propósito: o único número global do sistema é o clamp acumulado, que é de `Battle` e vale para toda fonte de modificador — tabela sem consumidor é a lição da migration `0014`, e ela não se repete. **O alvo do modificador sai do `slot`, nunca do `effectCode`** (`amplifier` no time do jogador, `enchanter` no adversário); os dois codificarem o alvo deixaria os dois discordarem.

- **Modificador de combate tem um ponto de aplicação só: `Battle._apply_modifier`.** Habilidade de suporte e equipamento passam por ele, e é ele que aplica `MODIFIER_MIN/MAX`. Aplicar `attack_modifier` direto de qualquer outro lugar — do loadout, de uma tela — dá ao teto acumulado um segundo dono, e a soma passa a estourar por um caminho e não pelo outro. É por isso que `PlayerLoadout.modifiers()` devolve dado cru em vez de mexer no `Combatant`.

- **Posse é o que a bancada tem e o posto do Relicário não.** `PlayerLoadout` separa fabricado (`_owned`) de vestido (`_equipped`), e `equip()` recusa o que o jogador não fabricou. O `RelicStationScreen` deixa vestir qualquer modelo do catálogo porque lá não existe sistema de aquisição — o furo está no ROADMAP e não deve ser copiado para peça nova. Quem for desenhar aquisição de relicário tem em `PlayerLoadout` a forma já provada.

- **Minério exclusivo é ausência de linha, não regra de código.** Os três minérios glaciais (`ITM-024/025/026`) só têm taxa de bioma em `BIO-014`, e `MiningTable._weight_of` lê "bioma presente sem este minério" como peso zero. Isso colide de frente com a regra de `mineracao` de que **todo bioma precisa do conjunto completo de taxas** — a regra vale para os minérios comuns, e cumpri-la literalmente para um exclusivo o torna minerável em toda parte, sem erro em lugar nenhum. `test_equipment.gd` varre os catorze biomas para acusar. O lado da **classe**, esse sim, é obrigatório nas cinco: sem ele o produto dá zero e o minério some até de onde deveria sair.

- **Toda tela é modal-que-pausa ou janela-de-HUD — não existe terceira.** Overlay modal (duelo, loja, posto do Relicário, bancada) entra como `CanvasLayer` em `PROCESS_MODE_ALWAYS`, faz `get_tree().paused = true` e entra em `WorldRoot._modal_open()`; nó pausado não recebe input, então é o pause que impede `F` de minerar no meio de uma negociação. Janela de HUD (time `T`, set `E`, bolsa `V`) **não** pausa — o mundo segue vivo atrás, e ela se guarda sozinha, como `_roster_open()`. Escolher a família errada é o jeito de vazar input: uma tela que não pausa e não tem guarda deixa o mapa responder por baixo dela. `_modal_open()` é o ponto único — tela modal nova entra lá, e `test_merchant.gd` (`_test_modal_guard`) prende o invariante.
- **Ponto fixo clicável herda de `InteractableActor`.** Comerciante, arena, posto do Relicário, bancada e guardião do portal são a mesma coisa mecanicamente: `StaticBody3D` (o clique é raycast físico), alcance de interação, placa flutuante, apoio no chão, e um sinal `engaged` que não conhece tela nenhuma. A subclasse traz só o que a distingue — corpo, estado próprio e a silhueta da placa. `CreatureActor` **não** entra: ela responde por seleção + segundo clique, contrato diferente. `WorldRoot.handle_click_at` e `WorldSelection.pick_body` testam contra o tipo base, então ator novo não exige edição em nenhum dos dois — antes eram duas listas de classes concretas mantidas à mão, e esquecer a segunda fazia o clique não fazer nada, sem erro.
- **Quem apoia corpo no chão usa `ground_on_spot()`, nunca `position.y = ...`.** O `y` do spot é a altura do terreno naquele ponto — zero no centro plano, mas não na costa —, e a origem do ator é o centro do corpo. Somar meia altura funciona nos dois casos; atribuir só funciona em chão plano e enterra o ator assim que ele se move para terreno elevado. Os atores já divergiram nisso (dois somavam, dois atribuíam) e estavam certos por coincidência de posição; `test_merchant.gd` (`_test_actor_grounding`) prende a regra.
- **Bioma sem `mining_rates` é a armadilha silenciosa da casa, e ela cresceu com a partição.** `MiningTable` trata lado ausente por inteiro como neutro (×1), de propósito — sem criatura ativa, o bioma decide sozinho. O efeito colateral é que bioma sem taxa nenhuma não dá erro: `peso_classe × peso_bioma` vira só-classe, a picareta continua entregando minério com outra distribuição, e o sintoma é "a picareta mudou de perfil" meses depois. Enquanto o mundo declarava um bioma só, bastava conferir aquele; com a partição o jogador pisa em **qualquer um do mapa**, então `test_data.gd` cobra taxas de todo bioma **alcançável**. Bioma novo entra com as 11 taxas ou não entra — é o que o documento `mineracao` do bestiário já manda.

- **Campo do bundle é promessa: ou alguém lê, ou ele não viaja.** `creature.biome` e `creature.role` saíam no bundle sem nenhum leitor e com dois terços das linhas nulas; saíram em 2026-08 e continuam no catálogo como anotação editorial. Vale para o caminho inverso também: `map_biomes` só passou a ser exportado quando ganhou consumidor de verdade (a conferência acima) — exportar antes teria só trocado um campo morto por outro.

- **Suíte vermelha significa quebrado; alvo de conteúdo sai como aviso.** `test_data.gd` separa as duas coisas com `_check` e `_warn`, e `pnpm game:export` usa o mesmo par (aborta / avisa-e-escreve). Os dois guardas têm de concordar sobre qual é qual: eles já divergiram, e foi por aí que `CRT-013` saiu num bundle conhecendo um golpe `awakeningOnly` sem ter Despertar — golpe que aparece na ficha e nunca pode ser usado. O export não olhava, e o teste reprovava na cobertura 1:1 (que é meta) sem checar o golpe morto (que é erro).
- **Classe é especialização de atributo, não linhagem.** Cada classe do bundle traz `primaryStat` (um dos cinco: `hp`, `attack`, `defense`, `speed`, `charge`) e `primaryStatBonusPct`. `stats_at_level` multiplica **aquele stat e nenhum outro**, depois da curva de nível. O `1.20` não existe em GDScript — é regra 1 aplicada: mudar o bônus das classes é um PATCH no bestiário. Também **não existe matchup CLS×CLS**: o bônus é o mesmo contra qualquer adversário, e nenhum valor lê a classe do oponente. Se aparecer necessidade de uma matriz entre classes, ela não é bem-vinda — é a regra do Changelog 0.01, e o `test_data.gd` a prende em duas frentes.
- **Terminologia travada:** "Despertar Ancestral" é o único termo. *Evolução* e *Forma Ancestral* estão descontinuados e a API do bestiário rejeita com 422.
- Comentário explica **por quê**, não o quê. Os comentários deste repo carregam o histórico das decisões — quando mudar uma, atualize o comentário junto ou ele vira mentira.

## Coisas para NÃO fazer

- Não escrever constante de balanceamento em código (regra 1). O multiplicador de classe é o caso mais recente: `CombatMath.stat_with_class_bonus` recebe o percentual como parâmetro de propósito, e travá-lo em 1.20 passaria em todos os testes de hoje.
- Não presumir classe pela linhagem da criatura. Artrópode não é uma classe, sinapsídeo não é uma classe — o vínculo foi desfeito em 2026-08 e não existe validação taxonômica em lugar nenhum.
- Não editar `data/bestiary.json` (regra 2).
- Não commitar `.glb`, `.png` ou áudio sem LFS — o `.gitattributes` já cobre, mas confira `git lfs status` se um binário aparecer no diff. Blob commitado direto fica no histórico para sempre.
- Não adicionar tabela ao bestiário sem incluí-la em `packages/db/src/tables.ts` lá — o dump sai sem ela em silêncio.
- Não comparar versão (`0.NN`) como texto: `'0.99' > '0.104'` em ordenação lexicográfica.
- Não deixar andaime de screenshot commitado.
- Não escrever `position.y = ...` para apoiar ator no chão. Use `ground_on_spot()` (regra acima).
- Não adicionar classe concreta às listas de `is` do `WorldRoot`/`WorldSelection`. Ponto fixo clicável herda de `InteractableActor` e já é coberto.
- Não aplicar `attack_modifier`/`defense_modifier` fora de `Battle._apply_modifier` — o clamp acumulado tem um dono só.
- Não cadastrar taxa de bioma para minério exclusivo "para completar a cobertura". A ausência É a exclusividade.
- Não abrir tela nova sem escolher a família: ou pausa a árvore e entra em `WorldRoot._modal_open()`, ou não pausa e se guarda sozinha. Tela que não faz nem um nem outro deixa o mapa responder por baixo dela.

## Onde procurar

- **README.md** — o que existe, como rodar, e o raciocínio de cada sistema
- **ROADMAP.md** — o que está pendente e em que ordem
- **`scripts/data/bestiary_data.gd`** — o contrato com o bundle
- **`scripts/battle/battle.gd`** — a máquina de turnos, e o comentário sobre `replace_active` vs `_do_switch`
- **`scripts/world/interactable_actor.gd`** — a base dos pontos fixos clicáveis e o contrato do apoio no chão
- **`scripts/world/world_root.gd`** — `_modal_open()` e o comentário sobre as duas famílias de tela; é o árbitro de quem recebe input
- **`scripts/world/player_progress.gd`** — o único estado que persiste em disco hoje (Glifos); autoload `Progress`, nunca referenciado pelo identificador global bare fora deste arquivo (mesmo motivo de `Bestiary`)
- **`scripts/world/arena_actor.gd`** / **`portal_guardian_actor.gd`** — arena e guardião do portal (documento `glifos-e-portais` no bestiário). Desde 2026-08 os dois são **dados**: o duelo vem de `duelists[].duel` no bundle e o guardião só é instanciado quando `maps[].connections` traz uma travessia com `requiredGlyph`. Travessia dentro de uma era é livre, então o PZ-01 hoje **não tem guardião** — e isso é o dado mandando, não conteúdo removido. `Glifo concedido vazio` também é estado normal: só a arena do último mapa de uma era concede
- **`scripts/dev/test_data.gd`** — o guarda do contrato; rode depois de todo `game:export`. Espelha os critérios do export: `_check` para erro de dado, `_warn` para meta de conteúdo
- **`scripts/world/player_loadout.gd`** — posse e slots do resto do set; `scripts/ui/crafting_screen.gd` é a bancada que fabrica e `test_equipment.gd` prende as duas asserções negativas (minério glacial não vaza; receita incompleta não cobra)
- **`scripts/dev/test_glyphs.gd`** — `PlayerProgress` isolado + a condição de concessão de Glifo (vitória de arena, nunca vitória selvagem)
- **`scripts/dev/test_palette.gd`** — comportamento da recoloração e da aura (o *contrato* da paleta no bundle fica em `test_data.gd`, com o resto do que espelha o export)
- **`scripts/world/creature_actor.gd`** — resolução de modelo (`model_path`), montagem do visual e animação; `CompanionActor` consome o mesmo contrato
- **`scripts/world/element_palette.gd`** — a identidade visual por elemento: rampa do catálogo, recoloração do corpo, aura do Despertar. O comentário de topo explica por que é shader e não textura gerada, e por que a aura é casca IRMÃ da malha
- **`scripts/world/character_rig.gd`** — humanos por receita (jogador e NPCs); `test_characters.gd` guarda o kit, as receitas do bundle e a fusão das bibliotecas de animação
- **`scripts/world/map_dressing.gd`** — ambiência e props de cenário por mapa (apresentação pura, padrão `WorldPopulator`); o layout do PZ-01 vive aqui
- **`scripts/world/map_terrain.gd`** — relevo com colisão e a consulta `height_at`; planície central plana até 16 m (onde vive o gameplay de chão plano), colinas e rim só na zona externa, e os dois trechos emersos reservados a NPCs/portais — a costa da borda -Z (`on_coast`) e a ilha da arena no miolo (`on_island`), as duas sem bioma e sem spawn. A origem do mapa **não é mais altura zero**: é o topo da ilha, a 2,6 m. Malha, física e consulta saem da mesma grade — nunca discordam
- **`../avyron-bestiary/CLAUDE.md`** — o briefing do bestiário
- **`../avyron-bestiary/docs/DATA_WORKFLOW.md`** — como inserir e corrigir dados
